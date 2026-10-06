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
/// else handles — a trap, a bad access, an abort, a `kill -HUP`, the user's
/// `⌃\` — puts the shell's line discipline back, and then lets the signal do
/// what it would have done.
///
/// The debt is every input mode `Terminal.enableRawMode` and the startup
/// negotiation turned on: the kitty keyboard protocol's pushed flags, mouse
/// tracking, focus and palette reports, bracketed paste, modifyCursorKeys and
/// a pinned grapheme-clustering mode; the output modes TUIkit changes
/// (`Terminal.outputModesOff`): the end of a synchronized update, should the
/// signal land in the middle of a frame that holds the display, and autowrap
/// back on; and the cursor, shown again (`Terminal.signalDebt` spells it). The kitty
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
/// `SIGQUIT` is the exception. It is the user's quit key, `⌃\`, which the
/// terminal driver turns into the signal (raw mode keeps only that one signal
/// character live), and a quit is not a crash: there is no report to keep,
/// and the user asked to leave. So it pays what a normal quit writes — a
/// delete for each image the app put in the terminal, the styling reset, the
/// debt above, and the alternate screen left (`Terminal.quitDebt`) — and then
/// ends by the signal's default action, the shell's "Quit: 3", never through
/// the handler that was there before: that is the Swift runtime's crash
/// reporter, which would print a backtrace, call it a crash, and on a
/// terminal wait half a minute for a key. Of the rest of a quit's teardown it
/// does nothing: no focus is given up, a setting saved a moment before may
/// not be on disk, and under tmux the client hooks stay installed until their
/// next firing removes them (`TerminalHost.tmuxClientChangeHookArguments`),
/// as after a crash — removing them forks tmux, no call for a signal handler.
///
/// ## Which signals
///
/// - **The crashes** (`SIGSEGV`, `SIGBUS`, `SIGILL`, `SIGTRAP`, `SIGABRT`,
///   `SIGFPE`, `SIGSYS`): always taken, handing on to the handler that was
///   there before — the Swift runtime's crash reporter keeps its
///   `SA_SIGINFO` handler and its alternate stack.
/// - **The quit** (`SIGQUIT`): always taken, and ended by the default action
///   (above). An app that wants `⌃\` for itself has no way to: the driver
///   takes the key before the app could see it, as a shell's does.
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
/// (`sigaction`) — for `SIGQUIT`, the default (`signal(3)`) — and `raise(2)`
/// the signal again, which is delivered to that handler, or the default
/// action, as soon as this one returns. Installed
/// with `SA_ONSTACK`, so on a stack overflow it runs on whatever alternate
/// stack the thread has rather than on the stack that overflowed.
enum FatalSignalTerminalRestore {

    /// The signals that end the process with nothing run on the way out:
    /// always taken, chained to the handler before.
    private static let crashSignals: [Int32] = [
        SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGABRT, SIGFPE, SIGSYS,
    ]

    /// The user's quit key's signal: always taken, paid as a quit
    /// (``owedOnQuit``) and ended by its default action.
    private static let quitSignals: [Int32] = [SIGQUIT]

    /// The signals that end the process quietly by default, and that nothing
    /// in TUIkit handles: taken only where their disposition is still the
    /// default.
    private static let terminatingSignals: [Int32] = [
        SIGHUP, SIGUSR1, SIGUSR2, SIGALRM, SIGVTALRM, SIGPROF, SIGXCPU, SIGXFSZ,
    ]

    /// Every list, in the order ``previous`` and ``taken`` are indexed: the
    /// ones always taken first.
    private static let signals = crashSignals + quitSignals + terminatingSignals

    /// How many of ``signals`` are always taken.
    private static let alwaysTaken = crashSignals.count + quitSignals.count

    /// The most bytes a debt can be. Not private so a test can check that the
    /// longest debts `Terminal.signalDebt` and `Terminal.quitDebt` spell fit:
    /// ``arm(owing:onQuit:restoring:)`` would cut off the rest.
    static let capacity = 256

    /// The most bytes a quit's debt can be: ``capacity``, and the image
    /// deletes a quit writes first (`Terminal.quitFarewell`).
    static let quitCapacity = capacity + Terminal.quitFarewellCapacity

    /// The owed bytes, and how many of them are owed: zero when nothing is.
    /// Written only on the main actor, read only by the handler.
    nonisolated(unsafe) private static let owed = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
    nonisolated(unsafe) private static var owedCount = 0

    /// What a `SIGQUIT` pays instead: what a quit writes, the alternate screen
    /// left with the rest.
    nonisolated(unsafe) private static let owedOnQuit = UnsafeMutablePointer<UInt8>.allocate(capacity: quitCapacity)
    nonisolated(unsafe) private static var owedOnQuitCount = 0

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

    /// Owes the terminal `sequence`, or `quitSequence` for a `SIGQUIT`, and
    /// `termios` if there is one, should the process die of a signal,
    /// installing the handlers the first time.
    @MainActor
    static func arm(owing sequence: String, onQuit quitSequence: String, restoring termios: termios?) {
        let bytes = Array(sequence.utf8.prefix(capacity))
        let quitBytes = Array(quitSequence.utf8.prefix(quitCapacity))
        owedCount = 0
        owedOnQuitCount = 0
        owesTermios = false
        for (index, byte) in bytes.enumerated() { owed[index] = byte }
        for (index, byte) in quitBytes.enumerated() { owedOnQuit[index] = byte }
        if let termios { savedTermios.pointee = termios }
        owedCount = bytes.count
        owedOnQuitCount = quitBytes.count
        owesTermios = termios != nil
        installIfNeeded()
    }

    /// Owes the terminal nothing. The handlers stay installed and pass every
    /// signal straight on, a `SIGQUIT` to its default action.
    @MainActor
    static func disarm() {
        owedCount = 0
        owedOnQuitCount = 0
        owesTermios = false
    }

    @MainActor
    private static func installIfNeeded() {
        guard !installed else { return }
        installed = true
        for (index, signal) in signals.enumerated() {
            taken[index] = false
            if index >= alwaysTaken {
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
        handlerAddress(of: action) == 0
    }

    /// `action`'s handler, as an address, through each C library's spelling
    /// of the union that holds it: 0 for `SIG_DFL`, 1 for `SIG_IGN`.
    private static func handlerAddress(of action: sigaction) -> Int {
        #if canImport(Darwin)
            unsafeBitCast(action.__sigaction_u, to: Int.self)
        #elseif canImport(Glibc)
            unsafeBitCast(action.__sigaction_handler, to: Int.self)
        #elseif canImport(Musl)
            unsafeBitCast(action.__sa_handler, to: Int.self)
        #endif
    }

    /// The handler ``setHandler(_:)`` installs, a C function that calls
    /// ``handle(_:)``.
    private static let handler: @convention(c) (Int32) -> Void = { signal in
        Self.handle(signal)
    }

    /// ``handler``'s address, as ``handlerAddress(of:)`` reads one.
    static var handlerAddress: Int { unsafeBitCast(handler, to: Int.self) }

    /// Sets `action`'s handler to ``handle(_:)``, through each C library's
    /// spelling of the union that holds it.
    private static func setHandler(_ action: inout sigaction) {
        #if canImport(Darwin)
            action.__sigaction_u = __sigaction_u(__sa_handler: handler)
        #elseif canImport(Glibc)
            action.__sigaction_handler = .init(sa_handler: handler)
        #elseif canImport(Musl)
            action.__sa_handler = .init(sa_handler: handler)
        #endif
    }

    /// Whether a `SIGQUIT` sent now ends the process: whether its disposition
    /// is this handler, which pays the debt and ends by the default action,
    /// or the default action itself. Not where the app ignores the signal, or
    /// installed a handler of its own after TUIkit's: what that does is the
    /// app's. Asked by the quit key's report before it waits for its signal
    /// to end the process (`QuitKeyReport`), which it would otherwise wait
    /// for for ever.
    static func quitEndsTheProcess() -> Bool {
        var current = sigaction()
        guard sigaction(SIGQUIT, nil, &current) == 0 else { return false }
        return endsTheProcess(handlerAddress: handlerAddress(of: current))
    }

    /// ``quitEndsTheProcess()``'s rule, for a disposition's handler
    /// address: the default's (0), or ``handlerAddress``.
    static func endsTheProcess(handlerAddress address: Int) -> Bool {
        address == 0 || address == handlerAddress
    }

    /// The handler: pay, restore, re-raise — a `SIGQUIT` to its default
    /// action.
    private static func handle(_ signal: Int32) {
        let quitting = signal == SIGQUIT
        let count = quitting ? owedOnQuitCount : owedCount
        if count > 0 { _ = write(STDOUT_FILENO, quitting ? owedOnQuit : owed, count) }
        owedCount = 0
        owedOnQuitCount = 0
        if owesTermios {
            _ = tcsetattr(STDIN_FILENO, TCSANOW, savedTermios)
            owesTermios = false
        }
        if quitting {
            restoreDefault(signal)
        } else if let index = signals.firstIndex(of: signal), taken[index] {
            sigaction(signal, previous + index, nil)
        }
        raise(signal)
    }

    /// Puts the default action back for `number`. `signal(3)` is
    /// async-signal-safe. Apart from ``handle(_:)``, whose parameter's name
    /// hides the function's.
    private static func restoreDefault(_ number: Int32) {
        _ = signal(number, SIG_DFL)
    }
}

#else

/// No signals on wasip1, so nothing can die of one with a debt outstanding.
enum FatalSignalTerminalRestore {
    @MainActor static func disarm() {}
}

#endif
