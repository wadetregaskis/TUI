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

// MARK: - Paying the terminal back on a crash

/// Writes what the terminal is owed when the process dies of a signal it
/// cannot survive — a trap, a bad access, an abort — and then lets the signal
/// do what it would have done.
///
/// One debt today: the kitty keyboard protocol's pushed flags. Their "report
/// all keys as escape codes" enhancement sends every key as an escape code,
/// Return and the letters included, so a shell left on a screen with them
/// pushed cannot even be typed `reset` at. A normal exit, Ctrl-C, `kill` and
/// a suspend all pop the flags (`Terminal.disableRawMode`); this covers the
/// deaths that skip every one of those.
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
/// Only async-signal-safe calls: `write(2)` the owed bytes, put back the
/// handler that was there before (`sigaction`, so the Swift runtime's own
/// crash reporter keeps its `SA_SIGINFO` handler and its alternate stack), and
/// `raise(2)` the signal again, which is delivered to that handler as soon as
/// this one returns. Installed with `SA_ONSTACK`, so on a stack overflow it
/// runs on whatever alternate stack the thread has rather than on the stack
/// that overflowed.
///
/// `SIGINT` and `SIGTERM` are not here: the run loop's dispatch sources turn
/// them into an orderly shutdown, which pops on its way out. `SIGKILL` cannot
/// be caught at all — see `Documentation/Terminal-compatibility.md`, "The
/// kitty keyboard protocol", for what that leaves and how to recover from it.
enum FatalSignalTerminalRestore {

    /// The signals that end the process with nothing run on the way out.
    private static let signals: [Int32] = [SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGABRT, SIGFPE, SIGQUIT]

    /// The most bytes a debt can be.
    private static let capacity = 64

    /// The owed bytes, and how many of them are owed: zero when nothing is.
    /// Written only on the main actor, read only by the handler.
    nonisolated(unsafe) private static let owed = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
    nonisolated(unsafe) private static var owedCount = 0

    /// The handlers that were installed before this one, one per entry of
    /// ``signals``, restored by the handler before it re-raises.
    nonisolated(unsafe) private static let previous = UnsafeMutablePointer<sigaction>.allocate(
        capacity: signals.count)
    nonisolated(unsafe) private static var installed = false

    /// Owes the terminal `sequence` should the process die of a signal,
    /// installing the handlers the first time.
    @MainActor
    static func arm(owing sequence: String) {
        let bytes = Array(sequence.utf8.prefix(capacity))
        owedCount = 0
        for (index, byte) in bytes.enumerated() { owed[index] = byte }
        owedCount = bytes.count
        installIfNeeded()
    }

    /// Owes the terminal nothing. The handlers stay installed and pass every
    /// signal straight on.
    @MainActor
    static func disarm() {
        owedCount = 0
    }

    @MainActor
    private static func installIfNeeded() {
        guard !installed else { return }
        installed = true
        for (index, signal) in signals.enumerated() {
            var action = sigaction()
            setHandler(&action)
            sigemptyset(&action.sa_mask)
            action.sa_flags = SA_ONSTACK
            sigaction(signal, &action, previous + index)
        }
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
        if let index = signals.firstIndex(of: signal) {
            sigaction(signal, previous + index, nil)
        }
        raise(signal)
    }
}

#else

/// No signals on wasip1, so nothing can die of one with a debt outstanding.
enum FatalSignalTerminalRestore {
    @MainActor static func arm(owing sequence: String) {}
    @MainActor static func disarm() {}
}

#endif
