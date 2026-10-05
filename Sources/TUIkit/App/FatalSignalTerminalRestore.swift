//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FatalSignalTerminalRestore.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// Signal handlers are POSIX; wasip1 has none, and no crash to survive.
#if !canImport(WASILibc)

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

// MARK: - Paying the terminal back on a signal

/// Writes what the terminal is owed when the process dies of a signal nothing
/// else handles — a trap, a bad access, an abort, a `kill -HUP` — puts the
/// shell's line discipline back, and then lets the signal do what it would
/// have done.
///
/// The debt is every input mode `Terminal.enableRawMode` and the startup
/// negotiation turned on: the kitty keyboard protocol's pushed flags, mouse
/// tracking, focus and palette reports, bracketed paste, modifyCursorKeys and
/// a pinned grapheme-clustering mode; and the cursor, shown again. The kitty
/// flags are the urgent part. Their "report all keys as escape codes"
/// enhancement sends every key as an escape code, Return and the letters
/// included, so a shell left with them pushed cannot even be typed `reset`
/// at. And the termios the shell had: left raw, a shell does not echo and
/// does not end a line on Return. A normal exit, `SIGINT`, `SIGTERM` and a
/// suspend all tear down in order (`Terminal.disableRawMode`); this covers
/// the deaths that skip every one of those.
///
/// The alternate screen is left up, and the frame on it: a crash's report
/// (`Fatal error: …`) is written to it before the trap, and leaving it would
/// take the report off the screen with it. With the input modes and termios
/// back, `reset` or `tput rmcup` can be typed to clear it.
///
/// ## Which signals
///
/// - **The crashes** (`SIGSEGV`, `SIGBUS`, `SIGILL`, `SIGTRAP`, `SIGABRT`,
///   `SIGFPE`, `SIGQUIT`, `SIGSYS`): always taken, handing on to the handler
///   that was there before — the Swift runtime's crash reporter keeps its
///   `SA_SIGINFO` handler and its alternate stack.
/// - **The quiet terminations** (`SIGHUP`, `SIGUSR1`, `SIGUSR2`, `SIGALRM`,
///   `SIGVTALRM`, `SIGPROF`, `SIGXCPU`, `SIGXFSZ`): catchable, they end the
///   process by default, and TUIkit handles none of them. Taken only where
///   nothing else has: a handler or an ignore the app installed first is the
///   app's, and paying the debt on a signal the app goes on running after
///   would hand it a terminal in the wrong modes.
///
/// `SIGINT` and `SIGTERM` are not here: the run loop's dispatch sources turn
/// them into an orderly shutdown, which tears down on its way out (the PTY
/// smoke kills with both). `SIGPIPE` is ignored, so it ends nothing. `SIGKILL`
/// cannot be caught at all — see `Documentation/Terminal-compatibility.md`,
/// "The kitty keyboard protocol", for what that leaves and how to recover.
///
/// ## Why a process-wide global
///
/// A signal handler is a C function pointer: it captures nothing and can be
/// handed nothing. What it writes therefore has to live where it can find it
/// without help, which is a fixed buffer allocated once, before any handler
/// is installed. It is not a singleton in the sense the project forbids —
/// nothing reads it to find a service — it is the one channel a signal has.
///
/// ## What the handler may do
///
/// Only async-signal-safe calls: `write(2)` the owed bytes, `tcsetattr(3)`
/// the saved termios, put back the handler that was there before
/// (`sigaction`), and `raise(2)` the signal again, which is delivered to that
/// handler — or the default action — as soon as this one returns. Installed
/// with `SA_ONSTACK`, so on a stack overflow it runs on whatever alternate
/// stack the thread has rather than on the stack that overflowed.
enum FatalSignalTerminalRestore {

    /// The signals that end the process with nothing run on the way out:
    /// always taken, chained to the handler before.
    private static let crashSignals: [Int32] = [
        SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGABRT, SIGFPE, SIGQUIT, SIGSYS,
    ]

    /// The signals that end the process quietly by default, and that nothing
    /// in TUIkit handles: taken only where their disposition is still the
    /// default.
    private static let terminatingSignals: [Int32] = [
        SIGHUP, SIGUSR1, SIGUSR2, SIGALRM, SIGVTALRM, SIGPROF, SIGXCPU, SIGXFSZ,
    ]

    /// Both lists, in the order ``previous`` and ``taken`` are indexed.
    private static let signals = crashSignals + terminatingSignals

    /// The most bytes a debt can be.
    private static let capacity = 256

    /// The owed bytes, and how many of them are owed: zero when nothing is.
    /// Written only on the main actor, read only by the handler.
    nonisolated(unsafe) private static let owed = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
    nonisolated(unsafe) private static var owedCount = 0

    /// The termios the shell had, put back by the handler while
    /// ``owesTermios`` is set.
    nonisolated(unsafe) private static let savedTermios = UnsafeMutablePointer<termios>.allocate(capacity: 1)
    nonisolated(unsafe) private static var owesTermios = false

    /// The handlers that were installed before this one, one per entry of
    /// ``signals``, restored by the handler before it re-raises.
    nonisolated(unsafe) private static let previous = UnsafeMutablePointer<sigaction>.allocate(
        capacity: signals.count)
    /// Which entries of ``signals`` this installed a handler for.
    nonisolated(unsafe) private static let taken = UnsafeMutablePointer<Bool>.allocate(capacity: signals.count)
    nonisolated(unsafe) private static var installed = false

    /// Owes the terminal `sequence`, and `termios` if there is one, should the
    /// process die of a signal, installing the handlers the first time.
    @MainActor
    static func arm(owing sequence: String, restoring termios: termios?) {
        let bytes = Array(sequence.utf8.prefix(capacity))
        owedCount = 0
        owesTermios = false
        for (index, byte) in bytes.enumerated() { owed[index] = byte }
        if let termios { savedTermios.pointee = termios }
        owedCount = bytes.count
        owesTermios = termios != nil
        installIfNeeded()
    }

    /// Owes the terminal nothing. The handlers stay installed and pass every
    /// signal straight on.
    @MainActor
    static func disarm() {
        owedCount = 0
        owesTermios = false
    }

    @MainActor
    private static func installIfNeeded() {
        guard !installed else { return }
        installed = true
        for (index, signal) in signals.enumerated() {
            taken[index] = false
            if index >= crashSignals.count {
                var current = sigaction()
                guard sigaction(signal, nil, &current) == 0, isDefault(current) else { continue }
            }
            var action = sigaction()
            setHandler(&action)
            sigemptyset(&action.sa_mask)
            action.sa_flags = SA_ONSTACK
            taken[index] = sigaction(signal, &action, previous + index) == 0
        }
    }

    /// Whether `action` is the default disposition, `SIG_DFL` — a null
    /// handler in every C library's union.
    private static func isDefault(_ action: sigaction) -> Bool {
        #if canImport(Darwin)
            unsafeBitCast(action.__sigaction_u, to: Int.self) == 0
        #elseif canImport(Glibc)
            unsafeBitCast(action.__sigaction_handler, to: Int.self) == 0
        #elseif canImport(Musl)
            unsafeBitCast(action.__sa_handler, to: Int.self) == 0
        #endif
    }

    /// Sets `action`'s handler to ``handle(_:)``, through each C library's
    /// spelling of the union that holds it.
    private static func setHandler(_ action: inout sigaction) {
        let handler: @convention(c) (Int32) -> Void = { signal in
            Self.handle(signal)
        }
        #if canImport(Darwin)
            action.__sigaction_u = __sigaction_u(__sa_handler: handler)
        #elseif canImport(Glibc)
            action.__sigaction_handler = .init(sa_handler: handler)
        #elseif canImport(Musl)
            action.__sa_handler = .init(sa_handler: handler)
        #endif
    }

    /// The handler: pay, restore, re-raise.
    private static func handle(_ signal: Int32) {
        if owedCount > 0 {
            _ = write(STDOUT_FILENO, owed, owedCount)
            owedCount = 0
        }
        if owesTermios {
            _ = tcsetattr(STDIN_FILENO, TCSANOW, savedTermios)
            owesTermios = false
        }
        if let index = signals.firstIndex(of: signal), taken[index] {
            sigaction(signal, previous + index, nil)
        }
        raise(signal)
    }
}

#else

/// No signals on wasip1, so nothing can die of one with a debt outstanding.
enum FatalSignalTerminalRestore {
    @MainActor static func disarm() {}
}

#endif
