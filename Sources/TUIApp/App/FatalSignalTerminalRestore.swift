//  🖥️ TUI — A Terminal UI framework for Swift
//  FatalSignalTerminalRestore.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// Signal handlers are POSIX; wasip1 has none, and no crash to survive.
import Synchronization
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
/// a pinned grapheme-clustering mode; the output modes TUI changes
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
/// `SIGQUIT` is the exception. It is the user's quit key, `⌃\`, turned into the
/// signal by the terminal driver (where raw mode leaves it that one signal
/// character) or by the app itself, and a quit is not a crash: there is no report to keep,
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
/// ## An `exit()` with the debt owed
///
/// An app that ends the process itself — `exit(0)` from a button's action,
/// or a library that calls `exit` — runs no teardown either, and dies of no
/// signal. So the first arming also registers an `atexit(3)` handler, which
/// pays a quit's debt (``owedOnQuit``) and puts the termios back, as a
/// `SIGQUIT` does: the process is ending at the app's word, there is no crash
/// report to keep, and the alternate screen is left. It does nothing where
/// the debt was paid or disarmed — after an orderly teardown
/// (`Terminal.disableRawMode`), the `exit` that ends every normal run. The
/// rest of the quit's teardown is skipped, as for a `SIGQUIT`.
///
/// ## Which signals
///
/// - **The crashes** (`SIGSEGV`, `SIGBUS`, `SIGILL`, `SIGTRAP`, `SIGABRT`,
///   `SIGFPE`, `SIGSYS`): always taken, handing on to the handler that was
///   there before — the Swift runtime's crash reporter keeps its
///   `SA_SIGINFO` handler and its alternate stack.
/// - **The quit** (`SIGQUIT`): always taken, and ended by the default action
///   (above). An app that wants `⌃\` for itself binds it, and raw mode takes
///   the key from the driver (`Terminal.maskQuitKey(for:confirming:)`). A
///   signal from outside, `kill -QUIT`, never asks.
/// - **The quiet terminations** (`SIGHUP`, `SIGUSR1`, `SIGUSR2`, `SIGALRM`,
///   `SIGVTALRM`, `SIGPROF`, `SIGXCPU`, `SIGXFSZ`): catchable, they end the
///   process by default, and TUI handles none of them. Taken only where
///   nothing else has: a handler or an ignore the app installed first is the
///   app's, and paying the debt on a signal the app goes on running after
///   would hand it a terminal in the wrong modes.
///
/// `SIGINT` and `SIGTERM` are not here: the run loop's dispatch sources turn
/// them into an orderly shutdown, which tears down on its way out (the PTY
/// smoke kills with both). `SIGPIPE` is ignored, so it ends nothing. `SIGKILL`
/// cannot be caught at all — see `Documentation/Terminals/Terminal compatibility survey.md`,
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
/// Only async-signal-safe calls: `write(2)` the owed bytes — whole, through
/// a short write, an interruption or a full descriptor, waiting for room with
/// `poll(2)` up to a deadline (``writeOwed(_:count:to:)``) — `tcsetattr(3)`
/// the saved termios, put back the handler that was there before
/// (`sigaction`) — for `SIGQUIT`, the default (`signal(3)`) — and `raise(2)`
/// the signal again, which is delivered to that handler, or the default
/// action, as soon as this one returns. Installed
/// with `SA_ONSTACK`, so on a stack overflow it runs on the thread's
/// alternate stack rather than on the stack that overflowed — which a thread
/// does not have unless something gives it one. Without it the kernel cannot
/// deliver the `SIGSEGV` at all, and kills the process with the debt unpaid:
/// deep view nesting is a known way to overflow the render's stack. So each
/// thread that runs the main actor's work is given one
/// (``provideAlternateStack()``): the main thread when the handlers are
/// installed, and whichever thread the run loop finds itself on at each
/// iteration — on Linux the main actor is drained by cooperative pool
/// threads from its first suspension, and not always the same one.
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
    /// in TUI handles: taken only where their disposition is still the
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

    /// One debt, in atomics, since a handler can take no lock: written only on
    /// the main actor, read by the handler, which may run on any thread at any
    /// moment. ``count`` publishes what is written before it: the handler sees
    /// no count without the bytes and the pop that go with it.
    ///
    /// A static of this type is initialized lazily on its first read, so
    /// ``installIfNeeded()`` reads each one before any handler is installed:
    /// from then on a read is a load.
    private struct Debt: ~Copyable, Sendable {
        /// The owed bytes. The pointer never changes, and no lock can guard
        /// what it points at: the release of ``count`` orders them.
        ///
        /// `nonisolated(unsafe)`, as ``savedTermios`` and ``previous`` are: a
        /// signal handler can take no lock and is handed no context, so it reads
        /// a static, and what it writes to the terminal or hands to the kernel
        /// has to be plain memory. `Atomic` refuses a pointer, which is not
        /// `Sendable`, and an address kept as an integer would be this with the
        /// type taken away.
        nonisolated(unsafe) private let bytes: UnsafeMutablePointer<UInt8>  // swiftlint:disable:this concurrency_escape

        /// How many of ``bytes`` are owed: zero when nothing is.
        private let count = Atomic<Int>(0)

        /// Where the debt's pop of the kitty keyboard flags lies
        /// (`KeyboardProtocolQuery.pop`), with `popEnd` 0 where it owes none:
        /// what the handler leaves out once the stall watchdog has popped the
        /// flags itself (``notePoppedByWatchdog(_:)``).
        private let popStart = Atomic<Int>(0)
        private let popEnd = Atomic<Int>(0)

        init(capacity: Int) {
            bytes = .allocate(capacity: capacity)
        }

        /// Owes nothing.
        func clear() {
            count.store(0, ordering: .releasing)
        }

        /// Reads the debt, to no effect but this: a static's first read runs its
        /// initializer, which a handler must not be the one to do.
        func touch() {
            _ = count.load(ordering: .relaxed)
        }

        /// Owes `debt`, its pop at `pop`. Clears it first, so a signal arriving
        /// in between finds nothing rather than half of it.
        func arm(_ debt: [UInt8], pop: Range<Int>?) {
            clear()
            for (index, byte) in debt.enumerated() { bytes[index] = byte }
            popStart.store(pop?.lowerBound ?? 0, ordering: .relaxed)
            popEnd.store(pop?.upperBound ?? 0, ordering: .relaxed)
            count.store(debt.count, ordering: .releasing)
        }

        /// Takes what is owed and writes it, without the pop where `leavingOutPop`.
        /// Async-signal-safe.
        func pay(leavingOutPop: Bool) {
            let owed = count.exchange(0, ordering: .acquiringAndReleasing)
            guard owed > 0 else { return }
            let base = UnsafePointer(bytes)
            let start = popStart.load(ordering: .relaxed)
            let end = popEnd.load(ordering: .relaxed)
            if leavingOutPop, end > 0, end <= owed {
                writeOwed(base, count: start)
                writeOwed(base + end, count: owed - end)
            } else {
                writeOwed(base, count: owed)
            }
        }
    }

    /// What a crash pays.
    private static let crashDebt = Debt(capacity: capacity)

    /// What a `SIGQUIT` pays instead: what a quit writes, the alternate screen
    /// left with the rest.
    private static let quitDebt = Debt(capacity: quitCapacity)

    /// Whether the stall watchdog (`StallWatchdog`) has popped the kitty
    /// flags and the run loop has not pushed them back: then the pop in the
    /// debt would be a second one, of an entry this process never pushed —
    /// on a terminal whose screens share one stack, the shell's. Written by
    /// the watchdog's thread and the main thread under the terminal's write
    /// lock, read by the handler: atomic, which no exclusivity check watches
    /// and no lazy initializer guards once ``installIfNeeded()`` has read it.
    private static let poppedByWatchdog = Atomic(false)

    /// The stall watchdog popped the kitty flags (`true`), or the run loop
    /// pushed them back or popped them itself (`false`): from now on the
    /// handler writes the debt without its pop, or with it. Any thread.
    static func notePoppedByWatchdog(_ popped: Bool) {
        poppedByWatchdog.store(popped, ordering: .relaxed)
    }

    /// The termios the shell had, put back by the handler while
    /// ``owesTermios`` is set.
    nonisolated(unsafe) private static let savedTermios = UnsafeMutablePointer<termios>.allocate(capacity: 1)  // swiftlint:disable:this concurrency_escape
    private static let owesTermios = Atomic(false)

    /// The handlers that were installed before this one, one per entry of
    /// ``signals``, restored by the handler before it re-raises.
    nonisolated(unsafe) private static let previous =  // swiftlint:disable:this concurrency_escape
        UnsafeMutablePointer<sigaction>.allocate(capacity: signals.count)
    /// Which entries of ``signals`` this installed a handler for, a bit each.
    private static let taken = Atomic<UInt64>(0)
    @MainActor private static var installed = false

    /// Owes the terminal `sequence`, or `quitSequence` for a `SIGQUIT`, and
    /// `termios` if there is one, should the process die of a signal,
    /// installing the handlers the first time.
    @MainActor
    static func arm(owing sequence: String, onQuit quitSequence: String, restoring termios: termios?) {
        let bytes = Array(sequence.utf8.prefix(capacity))
        let quitBytes = Array(quitSequence.utf8.prefix(quitCapacity))
        owesTermios.store(false, ordering: .releasing)
        crashDebt.arm(bytes, pop: popRange(in: bytes))
        quitDebt.arm(quitBytes, pop: popRange(in: quitBytes))
        if let termios { savedTermios.pointee = termios }
        owesTermios.store(termios != nil, ordering: .releasing)
        installIfNeeded()
    }

    /// Where the kitty flags' pop lies in `debt`, if it owes one. Found by
    /// its bytes, which nothing else in a debt spells: a debt is escape
    /// sequences, and an image delete's or a title's never holds `CSI < u`.
    private static func popRange(in debt: [UInt8]) -> Range<Int>? {
        debt.firstRange(of: popBytes)
    }

    /// `KeyboardProtocolQuery.pop`'s bytes.
    private static let popBytes = Array(KeyboardProtocolQuery.pop.utf8)

    /// Owes the terminal nothing. The handlers stay installed and pass every
    /// signal straight on, a `SIGQUIT` to its default action; the `atexit`
    /// handler pays nothing.
    @MainActor
    static func disarm() {
        crashDebt.clear()
        quitDebt.clear()
        owesTermios.store(false, ordering: .releasing)
    }

    @MainActor
    private static func installIfNeeded() {
        guard !installed else { return }
        installed = true
        // Read once here, so the handler never runs a lazy initializer.
        _ = poppedByWatchdog.load(ordering: .relaxed)
        _ = savedTermios
        _ = owesTermios.load(ordering: .relaxed)
        _ = taken.load(ordering: .relaxed)
        crashDebt.touch()
        quitDebt.touch()
        for (index, signal) in signals.enumerated() {
            if index >= alwaysTaken {
                var current = sigaction()
                guard sigaction(signal, nil, &current) == 0, isDefault(current) else { continue }
            }
            var action = sigaction()
            setHandler(&action)
            sigemptyset(&action.sa_mask)
            action.sa_flags = SA_ONSTACK
            if sigaction(signal, &action, previous + index) == 0 {
                taken.bitwiseOr(1 << UInt64(index), ordering: .relaxed)
            }
        }
        _ = atexit(exitHandler)
        provideAlternateStack()
    }

    // MARK: The alternate signal stack

    /// How big an alternate signal stack ``provideAlternateStack()`` makes:
    /// room for the handler, a few hundred bytes of locals and its calls, and
    /// for the handler it hands a crash on to, many times over.
    static let alternateStackSize = 64 * 1024

    /// Gives the calling thread an alternate signal stack, unless it has one
    /// — this function's, or another's (the Swift runtime's crash reporter
    /// may have given the main thread one), which is kept. Called on the
    /// main actor: by ``installIfNeeded()``, and by the run loop at each
    /// iteration, which on Linux may be on another pool thread than the one
    /// before. Costs one thread-local lookup on a thread already seen.
    ///
    /// A stack made here is freed when its thread ends, by the thread-local
    /// key's destructor, so a pool thread that comes and goes leaks nothing.
    static func provideAlternateStack() {
        let key = alternateStackKey
        guard pthread_getspecific(key) == nil else { return }
        var current = stack_t()
        guard sigaltstack(nil, &current) == 0 else { return }
        guard current.ss_flags & Int32(SS_DISABLE) != 0 else {
            // Another's: kept, and noted, so the next look is the lookup.
            _ = pthread_setspecific(key, UnsafeRawPointer(foreignStack))
            return
        }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: alternateStackSize, alignment: 16)
        var stack = stack_t()
        stack.ss_sp = memory
        stack.ss_size = alternateStackSize
        stack.ss_flags = 0
        guard sigaltstack(&stack, nil) == 0 else {
            memory.deallocate()
            return
        }
        _ = pthread_setspecific(key, UnsafeRawPointer(memory))
    }

    /// What ``alternateStackKey`` holds for a thread whose alternate stack is
    /// another's: never an allocation's address.
    private static var foreignStack: UnsafeMutableRawPointer { UnsafeMutableRawPointer(bitPattern: 1)! }

    /// The thread-local key that holds the alternate stack
    /// ``provideAlternateStack()`` made for each thread, or ``foreignStack``,
    /// and frees it as the thread ends (``releaseAlternateStack(_:)``).
    private static let alternateStackKey: pthread_key_t = {
        var key = pthread_key_t()
        // The destructor's parameter is optional in Glibc's and Musl's
        // spelling, not in Darwin's; the release takes either.
        _ = pthread_key_create(&key) { value in
            Self.releaseAlternateStack(value)
        }
        return key
    }()

    /// Frees an alternate stack ``provideAlternateStack()`` made, as its
    /// thread ends: turned off first, so the thread never has a stack that
    /// is gone. Left alone (a few KiB leaked) where it is not the thread's
    /// stack any more, or cannot be turned off.
    private static func releaseAlternateStack(_ value: UnsafeMutableRawPointer?) {
        guard let value, value != foreignStack else { return }
        var current = stack_t()
        guard sigaltstack(nil, &current) == 0, current.ss_sp == value else { return }
        var off = stack_t()
        off.ss_flags = Int32(SS_DISABLE)
        guard sigaltstack(&off, nil) == 0 else { return }
        value.deallocate()
    }

    /// What ``installIfNeeded()`` registers with `atexit(3)`: a C function
    /// that calls ``payOnExit()``.
    private static let exitHandler: @convention(c) () -> Void = {
        Self.payOnExit()
    }

    /// Pays a quit's debt, and the termios, where the process is ending by
    /// `exit(3)` with them still owed: an app's own `exit()`, which skips
    /// the teardown. Nothing after an orderly teardown, which disarmed it.
    /// See the type's "An `exit()` with the debt owed".
    private static func payOnExit() {
        pay(asQuit: true)
    }

    /// Whether `action` is the default disposition, `SIG_DFL` — a null
    /// handler in every C library's union.
    private static func isDefault(_ action: sigaction) -> Bool {
        handlerAddress(of: action) == 0
    }

    /// `action`'s handler, as an address, through each C library's spelling
    /// of the union that holds it: 0 for `SIG_DFL`, 1 for `SIG_IGN`.
    private static func handlerAddress(of action: sigaction) -> Int {
        // Compared with ``handler``'s address (`endsTheProcess`), so listed
        // under address_identity in Tools/DedupCheck/manifest.json, whose check
        // fails if `-deduplicate` gives that address to another function.
        // swiftlint:disable function_address_identity
        #if canImport(Darwin)
            unsafeBitCast(action.__sigaction_u, to: Int.self)
        #elseif canImport(Glibc)
            unsafeBitCast(action.__sigaction_handler, to: Int.self)
        #elseif canImport(Musl)
            unsafeBitCast(action.__sa_handler, to: Int.self)
        #endif
        // swiftlint:enable function_address_identity
    }

    /// The handler ``setHandler(_:)`` installs, a C function that calls
    /// ``handle(_:)``.
    private static let handler: @convention(c) (Int32) -> Void = { signal in
        Self.handle(signal)
    }

    /// ``handler``'s address, as ``handlerAddress(of:)`` reads one.
    static var handlerAddress: Int {
        // Compared: Tools/DedupCheck/manifest.json, address_identity.
        // swiftlint:disable:next function_address_identity
        unsafeBitCast(handler, to: Int.self)
    }

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
    /// installed a handler of its own after TUI's: what that does is the
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
        pay(asQuit: quitting)
        if quitting {
            restoreDefault(signal)
        } else if let index = signals.firstIndex(of: signal),
            taken.load(ordering: .relaxed) & (1 << UInt64(index)) != 0
        {
            sigaction(signal, previous + index, nil)
        }
        raise(signal)
    }

    /// Writes what is owed — a quit's debt where `quitting`, a crash's
    /// otherwise — and puts the shell's termios back, and owes nothing from
    /// then on: so a debt is paid once, by whichever of the handler and the
    /// `atexit` handler comes first. Async-signal-safe calls only.
    ///
    /// Without the kitty flags' pop where the stall watchdog popped them
    /// already (``poppedByWatchdog``): the debt in two writes, either side of
    /// it.
    private static func pay(asQuit quitting: Bool) {
        let leavingOutPop = poppedByWatchdog.load(ordering: .relaxed)
        if quitting {
            quitDebt.pay(leavingOutPop: leavingOutPop)
            crashDebt.clear()
        } else {
            crashDebt.pay(leavingOutPop: leavingOutPop)
            quitDebt.clear()
        }
        if owesTermios.exchange(false, ordering: .acquiringAndReleasing) {
            _ = tcsetattr(STDIN_FILENO, TCSANOW, savedTermios)
        }
    }

    /// Writes `count` bytes of `bytes` to standard output whole, if the
    /// terminal takes them in time.
    ///
    /// One `write(2)` is not enough: it may take only part (a pty whose
    /// buffer is nearly full), be interrupted by another signal before it
    /// takes anything (`EINTR`), or find no room at all where another program
    /// left standard output non-blocking (`EAGAIN`) — and what is cut off is
    /// the rest of the debt: the kitty flags' pop, the input modes, the
    /// cursor. So: the rest again after a short write or an interruption, and
    /// a `poll(2)` for room on a full descriptor, each wait at most 50 ms,
    /// twenty of them in all — a terminal that takes nothing in that long is
    /// not reading, and the process must still die. Both calls are
    /// async-signal-safe. Every try that takes nothing counts against the
    /// waits, an interruption and a write that took nothing and reported
    /// nothing included, so nothing here can spin.
    ///
    /// The limits are literals here, not static properties: a static is
    /// initialized lazily on first read, and a handler must not be the
    /// first to read one.
    ///
    /// Internal, with `descriptor`, so a test can fill a pipe.
    static func writeOwed(_ bytes: UnsafePointer<UInt8>, count: Int, to descriptor: Int32 = STDOUT_FILENO) {
        let waitMilliseconds: Int32 = 50
        let maximumWaits = 20  // a second in all
        var written = 0
        var waits = 0
        while written < count {
            let result = write(descriptor, bytes + written, count - written)
            if result > 0 {
                written += result
                continue
            }
            // `errno` is the thread's, and read before anything can change it.
            let error = result < 0 ? errno : 0
            let interrupted = error == EINTR
            let full = error == 0 || error == EAGAIN || error == EWOULDBLOCK
            guard interrupted || full, waits < maximumWaits else { return }
            waits += 1
            guard full else { continue }
            var room = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
            _ = poll(&room, 1, waitMilliseconds)
        }
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
    @MainActor static func provideAlternateStack() {}
}

#endif
