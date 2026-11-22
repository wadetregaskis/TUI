//  🖥️ TUI — A Terminal UI framework for Swift
//  FatalSignalTerminalRestore+Windows.swift
//
//  What the terminal is owed when a Windows process ends with no teardown: a
//  crash, Ctrl-Break, or an `exit()` of the app's own.
//
//  Created by Wade Tregaskis
//  License: MIT

#if os(Windows)

import Synchronization
import TUIFoundation
import WinSDK

/// Writes what the terminal is owed, and puts the console's modes back, when
/// the process ends without the teardown: the Windows half of
/// `FatalSignalTerminalRestore.swift`, whose type documentation says what is
/// owed and why. The debts are the same strings (`Terminal.signalDebt`,
/// `Terminal.quitDebt`); what differs is how a process dies.
///
/// ## How a Windows process dies
///
/// - **A crash** — an access violation, a trap (Swift's `fatalError`, a
///   failed precondition, an overflow), a stack overflow — is a structured
///   exception nothing handles, which reaches the unhandled-exception filter.
///   This installs one that pays a crash's debt (the alternate screen and the
///   report on it left up, as on POSIX) and the console's modes, then hands the
///   exception to the filter that was there before, or to the system's own
///   handling. A stack overflow runs the filter on the stack that overflowed,
///   in what the system keeps back for it: ``provideAlternateStack()`` keeps
///   more back, as `sigaltstack` gives a POSIX thread a stack to run on.
/// - **`abort()`** raises the C library's `SIGABRT` and then ends the process
///   with no exception at all, so the filter never runs: a `SIGABRT` handler
///   pays a crash's debt first.
/// - **Ctrl-Break** is what ⌃\ is on POSIX: the key a hung app quits by. The
///   console raises `CTRL_BREAK_EVENT` for it in every mode, on a thread it
///   starts for the purpose, so it quits an app whose run loop is stuck. It
///   pays a quit's debt — the alternate screen left — and ends the process with
///   `STATUS_CONTROL_C_EXIT`, the code the console's own handling would end it
///   with. The other control events (⌃C where it is not a key, a closed window,
///   a logoff, a shutdown) are an orderly shutdown's (`SignalManager`).
/// - **`exit()`**, from an app that ends the process itself, runs `atexit`
///   handlers: one pays a quit's debt, as on POSIX.
///
/// Debts are kept under a lock rather than in atomics, as nothing here runs in
/// a signal handler's straitjacket: the filter, the console's thread and an
/// `atexit` handler may all take locks. A crash on the main thread while it
/// holds this lock — arming, for a few microseconds — would deadlock on it, so
/// the crash paths only try it (``withLockIfAvailable``) and pay nothing if
/// they cannot have it.
enum FatalSignalTerminalRestore {

    /// What is owed, and to which console.
    private struct Owed {
        /// What a crash pays.
        var crash: [UInt8] = []
        /// What a quit pays: Ctrl-Break, ⌃\ read as the quit key, or `exit()`.
        var quit: [UInt8] = []
        /// The console's modes as the shell had them.
        var modes: ConsoleModes?
    }

    private static let owed = Mutex(Owed())

    /// The most bytes a crash's debt is, as the POSIX arm's buffer holds: what
    /// ``arm(owing:onQuit:restoring:)`` cuts a debt to, so a test holds the debts
    /// to one bound on every platform.
    static let capacity = 256

    /// The most bytes a quit's debt is: ``capacity`` and the image deletes a
    /// quit writes first (`Terminal.quitFarewell`).
    static let quitCapacity = capacity + Terminal.quitFarewellCapacity

    /// Whether the handlers are installed. Main actor only.
    @MainActor private static var installed = false

    /// The unhandled-exception filter that was there before this one's, handed
    /// each exception after the debt is paid.
    private static let previousFilter = unsafe Mutex<LPTOP_LEVEL_EXCEPTION_FILTER?>(nil)

    /// Owes the terminal `sequence`, or `quitSequence` for a quit, and `modes`
    /// if there are any, should the process end without its teardown,
    /// installing the handlers the first time.
    @MainActor
    static func arm(owing sequence: String, onQuit quitSequence: String, restoring modes: ConsoleModes?) {
        owed.withLock {
            $0 = Owed(
                crash: Array(sequence.utf8.prefix(capacity)), quit: Array(quitSequence.utf8.prefix(quitCapacity)),
                modes: modes)
        }
        installIfNeeded()
    }

    /// Owes the terminal nothing. The handlers stay installed and pass every
    /// event straight on.
    @MainActor
    static func disarm() {
        owed.withLock { $0 = Owed() }
    }

    /// Keeps back enough of the calling thread's stack for the
    /// unhandled-exception filter to run on after a stack overflow: the
    /// system's default is a few kilobytes, which the debt's write and the
    /// filter's own frames could overrun, and then the process dies with the
    /// debt unpaid. What `sigaltstack` is to the POSIX handler, asked of each
    /// thread the run loop runs on, as that is.
    @MainActor
    static func provideAlternateStack() {
        var size = ULONG(64 * 1024)
        _ = unsafe SetThreadStackGuarantee(&size)
    }

    /// Pays a quit's debt and ends the process as Ctrl-Break does: the user's
    /// quit key, read by the input chain with nothing left to ask
    /// (`QuitKeyReport`).
    ///
    /// Ended by `TerminateProcess`, as POSIX ends a quit by `SIGQUIT`'s default
    /// action: nothing else runs. Not `ExitProcess`, which then runs every
    /// DLL's detach code under the loader's lock, and a hung app is what this
    /// is for: a main thread stuck holding that lock, or the C runtime's,
    /// would leave the quit waiting on it for ever. The debt is written and
    /// the modes put back first, so nothing is owed: after the terminal's
    /// write under way, if one is, so the debt follows the frame rather than
    /// landing inside it (``duringWrite(_:)``).
    static func quitNow() -> Never {
        quitting.store(true, ordering: .sequentiallyConsistent)
        _ = awaitWrites(within: writeWait)
        pay(asQuit: true, waiting: true)
        _ = unsafe TerminateProcess(GetCurrentProcess(), UINT(bitPattern: Self.controlCExit))
        ExitProcess(UINT(bitPattern: Self.controlCExit))
    }

    /// `STATUS_CONTROL_C_EXIT`, what a console process ended by Ctrl-C or
    /// Ctrl-Break exits with when nothing handles the event.
    private static let controlCExit = Int32(bitPattern: 0xC000_013A)

    // MARK: - A quit and the frame in flight

    /// How many of the terminal's writes are under way (``duringWrite(_:)``).
    private static let writes = Atomic<Int>(0)

    /// Whether a quit is paying its debt: a write that begins from then on
    /// waits for the process to end instead.
    private static let quitting = Atomic(false)

    /// The longest a quit waits for a write under way before it pays its debt
    /// regardless: a write blocked for good — a conhost window with text being
    /// selected holds every write until the selection ends — must not stop
    /// the quit.
    static let writeWait: Duration = .milliseconds(250)

    /// Runs `body`, one of the terminal's writes, so that a quit's debt never
    /// lands inside it (`Terminal.withWriteGate`).
    ///
    /// Ctrl-Break's handler runs on a thread of the console's while the main
    /// thread writes on. Its debt written in the middle of a frame — inside an
    /// escape sequence, or with the rest of the frame following it onto the
    /// shell's screen — would be the mess it is there to clear up. So a quit
    /// waits for the write under way, up to ``writeWait``, and a write begun
    /// once the quit has begun waits for the process to end.
    ///
    /// What POSIX's `TerminalWriteGate` is to the stall watchdog, made of two
    /// atomics rather than a lock: a write costs two read-modify-writes and a
    /// load, and a quit can give up on a write that never ends, which no
    /// lock's waiter can. Each side stores its own flag and then reads the
    /// other's, sequentially consistent, so at least one of them sees the
    /// other: the write waits, or the quit does.
    static func duringWrite(_ body: () -> Void) {
        writes.wrappingAdd(1, ordering: .sequentiallyConsistent)
        if quitting.load(ordering: .sequentiallyConsistent) {
            writes.wrappingSubtract(1, ordering: .sequentiallyConsistent)
            // The quit ends the process; nothing here is to run before it does.
            while true { Sleep(INFINITE) }
        }
        body()
        writes.wrappingSubtract(1, ordering: .sequentiallyConsistent)
    }

    /// Waits until no write is under way (``duringWrite(_:)``), or `limit`
    /// has passed: whether the writes finished.
    static func awaitWrites(within limit: Duration) -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + limit
        while writes.load(ordering: .sequentiallyConsistent) > 0 {
            guard clock.now < deadline else { return false }
            Sleep(1)
        }
        return true
    }

    @MainActor
    private static func installIfNeeded() {
        guard !installed else { return }
        installed = true
        unsafe previousFilter.withLock { unsafe $0 = SetUnhandledExceptionFilter(exceptionFilter) }
        _ = signal(SIGABRT, abortHandler)
        _ = SetConsoleCtrlHandler(controlHandler, true)
        _ = atexit(exitHandler)
    }

    /// The unhandled-exception filter: pays a crash's debt, then passes the
    /// exception on.
    private static let exceptionFilter: @convention(c) (UnsafeMutablePointer<EXCEPTION_POINTERS>?) -> LONG = { pointers in
        Self.pay(asQuit: false, waiting: false)
        // Not redundant, whatever the rule says: the lock's answer is an optional
        // of the optional filter it holds, and `?? nil` flattens the two.
        // swiftlint:disable:next redundant_nil_coalescing
        let previous = unsafe Self.previousFilter.withLockIfAvailable { unsafe $0 } ?? nil
        if let previous = unsafe previous { return unsafe previous(pointers) }
        return EXCEPTION_CONTINUE_SEARCH
    }

    /// The C library's `SIGABRT` handler: pays a crash's debt; the process
    /// then ends as `abort()` ends it.
    private static let abortHandler: @convention(c) (Int32) -> Void = { _ in
        Self.pay(asQuit: false, waiting: false)
    }

    /// The console's control handler, for Ctrl-Break alone: the rest are
    /// `SignalManager`'s, and this passes them on. During a hand-off the
    /// Ctrl-Break is the other program's, which the console raises here too,
    /// and is taken and ignored, as `SIGQUIT` is on POSIX
    /// (`SignalManager.beginHandOff()`).
    static let controlHandler: @convention(c) (DWORD) -> WindowsBool = { event in
        guard event == DWORD(CTRL_BREAK_EVENT) else { return false }
        if SignalManager.isHandingOff.load(ordering: .sequentiallyConsistent) { return true }
        Self.quitNow()
    }

    /// What `atexit` calls: a quit's debt, where the process is ending by
    /// `exit()` with it still owed.
    private static let exitHandler: @convention(c) () -> Void = {
        Self.pay(asQuit: true, waiting: true)
    }

    /// Writes what is owed — a quit's debt where `quitting`, a crash's
    /// otherwise — and puts the console's modes back, and owes nothing from
    /// then on: so a debt is paid once, by whichever path comes first.
    ///
    /// - Parameter waiting: Whether to wait for the lock. Not on a crash's
    ///   path, which may be the lock's holder.
    private static func pay(asQuit quitting: Bool, waiting: Bool) {
        let debt =
            waiting
            ? owed.withLock { owed in
                defer { owed = Owed() }
                return owed
            }
            : owed.withLockIfAvailable { owed in
                defer { owed = Owed() }
                return owed
            }
        guard let debt else { return }
        let bytes = quitting ? debt.quit : debt.crash
        bytes.withUnsafeBufferPointer { buffer in
            guard var base = buffer.baseAddress else { return }
            var left = buffer.count
            while left > 0 {
                let written = unsafe StandardHandle.write(base, left)
                guard written > 0 else { break }
                unsafe base += written
                left -= written
            }
        }
        debt.modes?.apply()
    }
}

#endif
