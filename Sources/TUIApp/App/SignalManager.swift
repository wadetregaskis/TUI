//  🖥️ TUI — A Terminal UI framework for Swift
//  SignalManager.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIFoundation

// Signals, and the sources that watch them, are POSIX. WebAssembly's wasip1
// has neither — no `signal`, no libdispatch, and no process to send one — so
// the file splits here rather than at a dozen call sites, and the arm at the
// bottom answers the same questions with the only answers that platform has.
#if !canImport(WASILibc)

import Dispatch

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#endif

// MARK: - Signal Registration Barrier

/// Bridges libdispatch signal-source *registration* callbacks — which fire on a
/// Dispatch queue, possibly before the installer gets around to awaiting them —
/// into an async sequence the installer waits on.
///
/// Buffering is unbounded so a callback that arrives before the `await` is
/// never dropped. This lets ``SignalManager/install(wake:)`` block until every
/// source is actually armed, closing the startup race where a signal delivered
/// between `resume()` and "source armed" would be lost — preserving the old
/// synchronous `signal()`'s "Ctrl-C caught from the first instruction" guarantee.
private final class SignalRegistrationBarrier: Sendable {
    /// Registration notifications consumed by the installer.
    let events: AsyncStream<Void>

    /// Thread-safe producer used by the Dispatch registration handlers.
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        let pair = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .unbounded)
        self.events = pair.stream
        self.continuation = pair.continuation
    }

    /// A nonisolated Dispatch callback that records one registration.
    func callback() -> @Sendable () -> Void {
        { [continuation] in continuation.yield() }
    }

    /// Finishes the registration stream once every source is armed.
    func finish() {
        continuation.finish()
    }
}

// MARK: - Signal Manager

/// Manages POSIX signal handling for the application lifecycle via libdispatch
/// signal sources.
///
/// SIGWINCH (terminal resize), SIGINT / SIGTERM (graceful shutdown) and
/// SIGTSTP / SIGCONT (job control: Ctrl-Z has to hand the terminal back BEFORE
/// the process stops, or it strands the user's shell in raw mode on the
/// alternate screen — `d05786d3`, 2026-08-02) are monitored with
/// `DispatchSource.makeSignalSource` on the main queue. SIGPIPE is the one
/// signal here with no source: nothing wants to *observe* it, only to survive
/// a clipboard helper or a pty reader that went away mid-write, so
/// ``install(wake:)`` sets it to `SIG_IGN` process-wide and watches it no
/// further (`7152761f`, 2026-07-31).
///
/// Each source's handler runs on the main actor, sets an instance flag, and
/// wakes the demand-driven run loop directly. There is no async-signal-safe C handler, no
/// self-pipe, and no flag-poll layer: the loop still drains the flags each
/// iteration exactly as before (``shouldShutdown``, ``consumeResizeFlag()``),
/// but the flags are ordinary main-actor state pushed by the sources.
///
/// ## Why dispatch signal sources rather than `signal()` handlers?
///
/// A C signal handler may only call async-signal-safe functions, which is why
/// the previous design set aligned `Bool`s from the handler and woke the loop
/// through a self-pipe. A dispatch signal source moves that off the handler
/// entirely: libdispatch delivers the signal as an ordinary queued event, so the
/// handler is normal main-actor code — no torn reads, no self-pipe fd, no poll.
///
/// ## Usage
///
/// ```swift
/// let signals = SignalManager()
/// await signals.install(wake: { notifier.wake() })
/// while running {
///     if signals.shouldShutdown { break }
///     if signals.consumeResizeFlag() { invalidateAndRepaint() }
/// }
/// signals.stop()
/// ```
@MainActor
final class SignalManager {
    private typealias Disposition = @convention(c) (Int32) -> Void

    private enum Kind {
        case resize
        case shutdown
        case suspend
        case resumed
    }

    private struct Registration {
        let number: Int32
        /// What the source's handler sets: kept so a hand-off can make the
        /// source again (``endHandOff()``).
        let kind: Kind
        /// The disposition to restore on teardown, on Darwin, where `nil` is
        /// `SIG_DFL` — the usual case, and one to restore like any other. Unused
        /// on Linux, where the disposition must not be touched — see
        /// ``register(_:kind:barrier:)``.
        let previous: Disposition?
        let source: any DispatchSourceSignal
    }

    private var registrations: [Registration] = []

    /// Set by SIGWINCH; consumed by the loop to invalidate the frame-diff cache
    /// and repaint at the new size.
    private var terminalResized = false

    /// Set (sticky) by SIGINT / SIGTERM to request a graceful shutdown. The loop
    /// reads it and breaks so the terminal-restore teardown runs.
    private var needsShutdown = false

    /// Set by SIGTSTP (Ctrl-Z). The signal itself no longer stops the process
    /// (its default action is suppressed by the source registration), because
    /// stopping mid-frame would strand the user's shell in raw mode on the
    /// alternate screen. The loop consumes this, hands the terminal back, and
    /// then ACTUALLY stops — see `App.suspendUntilContinued`.
    private var suspendRequested = false

    /// Set by SIGCONT. The case this exists for is resuming from an *external*
    /// `SIGSTOP`, which cannot be caught — nothing was handed back, the shell
    /// had the terminal in our raw mode while the process slept and may have
    /// changed it, so the loop takes it back as a Ctrl-Z resume does and
    /// repaints (`AppRunner.recoverFromExternalStop`). (Our own suspend path arms
    /// ``expectSelfResume()`` before it stops, so the SIGCONT its `fg` raises
    /// is swallowed and doesn't double-repaint through here.)
    private var continueReceived = false

    /// Armed by the suspend path just before its self-`SIGSTOP`: the next
    /// SIGCONT is OURS (the `fg` that resumed us) and its repaint already
    /// happened inline, so the source swallows it instead of setting
    /// ``continueReceived``. One-shot. A consume-after-resume can't do this
    /// job: the source runs on the main QUEUE, which cannot fire until the
    /// synchronous resume path has finished — the flag it would consume isn't
    /// set yet.
    private var swallowNextContinue = false

    /// Wakes the demand-driven run loop when a signal lands while it is
    /// idle-blocked with nothing to render.
    private var wake: (@MainActor @Sendable () -> Void)?

    /// Whether a graceful shutdown was requested (SIGINT / SIGTERM).
    var shouldShutdown: Bool { needsShutdown }

    /// Returns `true` if the terminal was resized since the last call, then
    /// resets the flag (consume-on-read).
    func consumeResizeFlag() -> Bool {
        defer { terminalResized = false }
        return terminalResized
    }

    /// Returns `true` if a suspend (Ctrl-Z / SIGTSTP) was requested since the
    /// last call, then resets the flag (consume-on-read).
    func consumeSuspendFlag() -> Bool {
        defer { suspendRequested = false }
        return suspendRequested
    }

    /// Returns `true` if a SIGCONT arrived since the last call, then resets
    /// the flag (consume-on-read).
    func consumeContinueFlag() -> Bool {
        defer { continueReceived = false }
        return continueReceived
    }

    /// Arms the one-shot swallow for the suspend path's own resume — see
    /// ``swallowNextContinue``. Call immediately before the self-`SIGSTOP`.
    func expectSelfResume() {
        swallowNextContinue = true
    }

    /// Installs signal sources for SIGINT, SIGTERM, SIGWINCH, SIGTSTP and
    /// SIGCONT — registration order, which is the order they are armed in —
    /// and, before any of them, ignores SIGPIPE process-wide.
    ///
    /// `wake` is invoked from each source's main-actor handler so a signal that
    /// arrives while the loop is idle-blocked wakes it. This awaits each source's
    /// registration before returning, so a signal delivered *during* install is
    /// buffered by the barrier rather than dropped.
    ///
    /// - Parameter wake: Called (on the main actor) after a signal updates the
    ///   flags, to rouse the run loop.
    func install(wake: @escaping @MainActor @Sendable () -> Void) async {
        guard registrations.isEmpty else { return }
        self.wake = wake

        // SIGPIPE's default action is process termination, and a TUI app has
        // two routine ways to earn one: writing to a clipboard helper whose
        // stdin closed early (xclip with no display prints an error and exits
        // before reading), and writing frames to a pty whose reader vanished.
        // Either would kill the app mid-raw-mode — no deinit, terminal left on
        // the alternate screen. Ignore it process-wide so those writes return
        // EPIPE and fail gracefully instead. No dispatch source needed: nothing
        // wants to *observe* the signal, only to survive it. (Unlike INT/TERM
        // below, this is safe on Linux too — no libdispatch handler owns
        // SIGPIPE, so there is nothing to displace.)
        signal(SIGPIPE, SIG_IGN)

        let barrier = SignalRegistrationBarrier()
        register(SIGINT, kind: .shutdown, barrier: barrier)
        register(SIGTERM, kind: .shutdown, barrier: barrier)
        register(SIGWINCH, kind: .resize, barrier: barrier)
        // Ctrl-Z. Registration suppresses the default stop action on both
        // platforms (Darwin via the SIG_IGN below, Linux via libdispatch's own
        // handler), which is the point: stopping the moment the signal lands
        // would strand the user's shell in raw mode on the alternate screen.
        // The loop restores the terminal first, then stops for real.
        register(SIGTSTP, kind: .suspend, barrier: barrier)
        // The other side of an *external* SIGSTOP (uncatchable): repaint,
        // because the screen may have been disturbed while the process slept.
        register(SIGCONT, kind: .resumed, barrier: barrier)

        // Block until every source's registration handler has fired — i.e. all
        // sources are armed — so no early signal slips through the startup gap.
        var iterator = barrier.events.makeAsyncIterator()
        for _ in registrations { _ = await iterator.next() }
        barrier.finish()
    }

    private func register(_ number: Int32, kind: Kind, barrier: SignalRegistrationBarrier) {
        // A dispatch signal source changes NO disposition on either platform, so
        // the default action still applies unless we suppress it — but HOW we
        // suppress it differs:
        //   • Darwin (kqueue EVFILT_SIGNAL): the source fires in addition to the
        //     default action, and still fires under SIG_IGN. So SIG_IGN the
        //     signal (default=terminate for INT/TERM) and restore on teardown;
        //     SIGWINCH's default is already IGNORE, so that's a harmless no-op.
        //   • Linux (swift-corelibs-libdispatch): libdispatch installs and OWNS
        //     the signal's handler as part of source setup, which both feeds the
        //     source and displaces the terminate default. Calling SIG_IGN there
        //     would overwrite libdispatch's handler and BREAK delivery — so leave
        //     the disposition untouched.
        #if os(Linux)
            let previous: Disposition? = nil
        #else
            let previous = signal(number, SIG_IGN)
        #endif
        arm(number, kind: kind, barrier: barrier, previous: previous)
    }

    /// Makes the source for `number`, its handler setting `kind`'s flag, and
    /// keeps `previous` to restore on teardown: ``register(_:kind:barrier:)``'s
    /// second half, and all of a source made again after a hand-off.
    private func arm(_ number: Int32, kind: Kind, barrier: SignalRegistrationBarrier, previous: Disposition?) {
        let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
        source.setEventHandler { [weak self] in
            // Queue is `.main`, and the main queue is the main actor's
            // executor, so this is already the main actor's context —
            // `assumeIsolated` is a static-only bridge. Note the reason is the
            // executor, not a thread: on Linux the main actor is drained by a
            // cooperative pool thread, not the process main thread (measured;
            // see StackGuard's "Thread correctness" note).
            MainActor.assumeIsolated {
                guard let self else { return }
                switch kind {
                case .resize: self.terminalResized = true
                case .shutdown: self.needsShutdown = true
                case .suspend: self.suspendRequested = true
                case .resumed:
                    // Our own suspend's `fg` — already repainted inline.
                    if self.swallowNextContinue {
                        self.swallowNextContinue = false
                    } else {
                        self.continueReceived = true
                    }
                }
                // Set the flag THEN wake, so the resumed loop sees it already set.
                self.wake?()
            }
        }
        source.setRegistrationHandler(handler: barrier.callback())
        source.resume()
        registrations.append(Registration(number: number, kind: kind, previous: previous, source: source))
    }

    // MARK: Handing the terminal to another program

    /// What ``beginHandOff()`` changed, for ``endHandOff()`` to put back.
    private struct HandOffState {
        /// Each signal's action before the hand-off, whole: a handler's flags
        /// and mask with it (`FatalSignalTerminalRestore`'s `SIGQUIT` handler
        /// runs on the alternate stack).
        var actions: [(number: Int32, action: sigaction)]
        /// The calling thread's signal mask before the hand-off.
        var mask: sigset_t
        /// The sources cancelled for the hand-off, to be made again.
        var paused: [Registration]
    }

    /// Set while the terminal is handed to another program.
    private var handOffState: HandOffState?

    /// The sources made again after the last hand-off, and how many, for a
    /// test to wait until they are armed (``awaitRearmed()``).
    private var rearming: (barrier: SignalRegistrationBarrier, count: Int)?

    /// The signals whose sources a hand-off cancels: what a terminal in
    /// canonical mode sends the whole foreground group for ⌃C and ⌃Z.
    private static let pausedForHandOff: [Int32] = [SIGINT, SIGTSTP]

    /// Sets the signals up for the terminal being handed to another program
    /// (`AppRunner.handOffTerminal`): ⌃C, ⌃\\ and ⌃Z are signals again in the
    /// terminal's own settings, sent to every process in the foreground group,
    /// the app's included, and are meant for the other program.
    ///
    /// - `SIGINT` and `SIGQUIT` are ignored, as `system(3)` ignores them while
    ///   its child runs: neither ends the app, nor shuts it down once the
    ///   closure returns. `SIGINT`'s source is cancelled, as on Darwin a
    ///   kqueue source fires for an ignored signal too, and its handler would
    ///   run after the closure; a cancelled source's never does.
    /// - `SIGTSTP` takes its default action, stopping the app with the other
    ///   program, and the shell gets the job back; `fg` continues both. Its
    ///   source is cancelled for the same reason, so no suspend is pending
    ///   after. Unblocked on this thread, which on Linux may block it
    ///   (libdispatch blocks a signal on the thread it lands on, and reads it
    ///   from a `signalfd`), so that it can stop the process at all.
    ///
    /// `SIGTERM`, `SIGWINCH` and `SIGCONT` are watched as ever: a termination
    /// ends the app once the closure returns, and a resize repaints at the new
    /// size.
    func beginHandOff() {
        guard handOffState == nil else { return }
        let paused = registrations.filter { Self.pausedForHandOff.contains($0.number) }
        for registration in paused { registration.source.cancel() }
        registrations.removeAll { Self.pausedForHandOff.contains($0.number) }
        var actions: [(number: Int32, action: sigaction)] = []
        for number in [SIGINT, SIGQUIT, SIGTSTP] {
            var action = sigaction()
            guard unsafe sigaction(number, nil, &action) == 0 else { continue }
            actions.append((number, action))
        }
        // Each set by a call of its own, never from a list of handlers: a
        // handler is a C function pointer, and `SIG_IGN`'s is 1, one of the
        // low addresses Swift takes for `nil` of an `Optional` around a value
        // holding one. A loop over `[(Int32, Disposition?)]` ran no iteration
        // at all, its iterator's first element read as the end (measured,
        // Swift 6.2.4, debug build). `nil` is `SIG_DFL`, in every C library's
        // spelling of `signal`.
        signal(SIGINT, SIG_IGN)
        signal(SIGQUIT, SIG_IGN)
        signal(SIGTSTP, nil)
        var stop = sigset_t()
        unsafe sigemptyset(&stop)
        unsafe sigaddset(&stop, SIGTSTP)
        var mask = sigset_t()
        _ = unsafe pthread_sigmask(SIG_UNBLOCK, &stop, &mask)
        handOffState = HandOffState(actions: actions, mask: mask, paused: paused)
    }

    /// Puts back what ``beginHandOff()`` changed, as the app takes the
    /// terminal back: each signal's action, the thread's mask, and the
    /// sources it cancelled, made again.
    ///
    /// Each signal is ignored once more before its action is put back, which
    /// discards one still pending (POSIX: setting `SIG_IGN` discards a pending
    /// signal). On Linux a signal blocked on every thread waits pending, even
    /// ignored, and the source made again would read it from its `signalfd`:
    /// a ⌃C pressed in the other program would shut the app down after all.
    func endHandOff() {
        guard let state = handOffState else { return }
        handOffState = nil
        for (number, saved) in state.actions {
            signal(number, SIG_IGN)
            var action = saved
            _ = unsafe sigaction(number, &action, nil)
        }
        var mask = state.mask
        _ = unsafe pthread_sigmask(SIG_SETMASK, &mask, nil)
        // Made again without waiting for them to arm: the run loop goes on at
        // once. A signal in the moment before is lost, and only a `kill` can
        // send one then, since raw mode makes ⌃C and ⌃Z keys again first.
        let barrier = SignalRegistrationBarrier()
        for registration in state.paused {
            arm(registration.number, kind: registration.kind, barrier: barrier, previous: registration.previous)
        }
        rearming = (barrier, state.paused.count)
    }

    /// Whether the terminal is handed to another program.
    var isHandedOff: Bool { handOffState != nil }

    /// Returns once the sources the last ``endHandOff()`` made again are
    /// armed: for a test, which sends them a signal next.
    func awaitRearmed() async {
        guard let (barrier, count) = rearming else { return }
        rearming = nil
        var iterator = barrier.events.makeAsyncIterator()
        for _ in 0..<count { _ = await iterator.next() }
        barrier.finish()
    }

    /// Cancels the signal sources and restores prior dispositions (Darwin).
    /// Idempotent — safe to call more than once.
    func stop() {
        for registration in registrations {
            registration.source.cancel()
            #if !os(Linux)
                // Unconditionally: `nil` is SIG_DFL, not "nothing to restore".
                // Skipping it left ⌃C, `kill` and ⌃Z ignored for the rest of
                // the process, and for anything it launched afterwards.
                signal(registration.number, registration.previous)
            #endif
        }
        registrations.removeAll()
        wake = nil
    }
}

#else  // canImport(WASILibc)

// MARK: - WebAssembly

/// The same manager, on a platform with no signals to manage.
///
/// wasip1 has no `signal`, no `kill`, and no notion of a process group, so
/// every question this type answers has one honest answer there: nothing has
/// happened. It is a stub, and deliberately a *whole* one — the run loop asks
/// these questions on every frame, and the alternative to answering them here
/// is conditionals around each of the six call sites in `App`.
///
/// What is lost with the signals is worth naming: there is no resize
/// notification (a host that can resize has to say so some other way — see
/// `Documentation/WebAssembly port.md`), no Ctrl-C interrupt (the key reaches the
/// app through stdin like any other, and the app's own bindings handle it),
/// and no suspend/resume, which has no meaning in a browser tab.
@MainActor
final class SignalManager {

    /// Never true: nothing outside the app can ask it to stop.
    var shouldShutdown: Bool { false }

    /// Never true — see the type's doc for how a resize would have to arrive.
    func consumeResizeFlag() -> Bool { false }

    /// Never true: wasip1 has no job control.
    func consumeSuspendFlag() -> Bool { false }

    /// Never true: nothing can send a continue where nothing can stop.
    func consumeContinueFlag() -> Bool { false }

    /// A no-op: the suspend path it guards cannot run here.
    func expectSelfResume() {}

    /// A no-op: there is no foreground group to share signals with.
    func beginHandOff() {}

    /// A no-op, as ``beginHandOff()`` is.
    func endHandOff() {}

    /// A no-op. `wake` is unused because nothing here can wake the loop; stdin
    /// is the only event source, and the arrival notifier owns that.
    func install(wake: @escaping @MainActor @Sendable () -> Void) async {}

    /// A no-op, so the teardown path reads the same on every platform.
    func stop() {}
}

#endif
