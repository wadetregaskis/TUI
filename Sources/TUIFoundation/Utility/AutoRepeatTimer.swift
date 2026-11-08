//  🖥️ TUI — A Terminal UI framework for Swift
//  AutoRepeatTimer.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Auto-Repeat Timer

/// Fires an action once immediately, then again periodically
/// after a short initial delay, until cancelled.
///
/// Used by ``Stepper`` (and other discrete-step controls) to
/// implement "press-and-hold to keep adjusting" — the user
/// holds down on the increment / decrement arrow and the
/// stepper keeps ticking up / down at a steady cadence,
/// matching the system-stepper behaviour every desktop and
/// mobile OS ships.
///
/// The cadence is two numbers:
///
/// - ``initialDelayMs`` — the time between the initial fire
///   and the start of the repeat loop. Long enough that a
///   normal short-tap press only fires once.
/// - ``repeatIntervalMs`` — the gap between successive
///   repeats once the loop is going. Short enough to feel
///   responsive but slow enough that the user can stop
///   precisely.
///
/// The initial delay is only counted while the app is awake to
/// see a release; see ``start(action:)``, where a tap that the
/// run loop was too busy to finish reading would otherwise fire
/// twice.
///
/// Internally a single `Task` runs on the main actor. Starting
/// a new run while one is already going cancels the previous.
/// Cancelling is idempotent.
///
/// It waits on the clock it is given: the machine's in an app, and in a test a
/// clock the test steps (`TestClock`), which makes a press, a hold, and a
/// frame that outlasts the initial delay exact rather than a race against the
/// wall. A control's timer takes the environment's
/// (`EnvironmentValues.autoRepeatClock`).
@MainActor
package final class AutoRepeatTimer {
    /// The delay every "is this one gesture or two?" decision in the framework
    /// uses, in milliseconds.
    ///
    /// A static as well as a default so it can be read where a timer cannot be
    /// built — `Link`'s activation gate is `nonisolated` and this type is
    /// `@MainActor`. One number, three readers (this timer,
    /// `ScrollbarRenderer.autoRepeatInitialDelayNanos`, and that gate), all
    /// pinned together by test.
    nonisolated public static let defaultInitialDelayMs = 700

    /// Milliseconds between the initial action and the first
    /// repeat. Long enough that a brief tap fires only once,
    /// short enough that a held press starts repeating without
    /// feeling stuck.
    ///
    /// The default is 700, not the 400 it was: a careful click on a one-cell
    /// arrow commonly holds the button for 400–600 ms, so at 400 a deliberate
    /// click stepped twice and a slightly slower one stepped four times —
    /// timing-dependent, so it read as flaky rather than as a rule. The
    /// scrollbar's own auto-repeat measured the same span and landed on the
    /// same number first; the two are pinned together by a test, because a
    /// scrollbar arrow and a slider arrow are the same gesture and must not
    /// disagree about where a click ends. See
    /// `ScrollbarRenderer.autoRepeatInitialDelayNanos`.
    public let initialDelayMs: Int

    /// Milliseconds between successive repeats once the
    /// initial delay has elapsed.
    public let repeatIntervalMs: Int

    /// How much later than asked a sleep may return and still count as having
    /// been waited out — the slack for ordinary scheduling jitter and a frame
    /// or two of render, below which the run loop was reading input often
    /// enough for its silence to mean something. See ``start(action:)``.
    private static let latenessToleranceMs = 50

    /// The running task, or `nil` if not currently active.
    private var task: Task<Void, Never>?

    /// What the delays are waited on and measured by.
    ///
    /// An existential, kept, and opened once a hold by the generic
    /// `run(on:initialDelay:repeatInterval:action:)`: so no `Clock` reaches
    /// the type's signature, where a generic class could not keep
    /// ``defaultInitialDelayMs`` (a static stored property), and the four
    /// controls that keep one need not name its clock. Not a hot path either
    /// way: one wait every 80 ms of a hold.
    private let clock: any Clock<Duration>

    /// Creates a timer in the stopped state.
    ///
    /// - Parameters:
    ///   - initialDelayMs: See ``initialDelayMs``.
    ///   - repeatIntervalMs: See ``repeatIntervalMs``.
    ///   - clock: What the delays are waited on: by default the clock that
    ///     stops while the machine sleeps, as `MonotonicClock`, and the
    ///     `Task.sleep(nanoseconds:)` this used to make, do.
    public init(
        initialDelayMs: Int = AutoRepeatTimer.defaultInitialDelayMs, repeatIntervalMs: Int = 80,
        clock: any Clock<Duration> = SuspendingClock()
    ) {
        self.initialDelayMs = initialDelayMs
        self.repeatIntervalMs = repeatIntervalMs
        self.clock = clock
    }

    /// Whether the timer is currently scheduled.
    public var isRunning: Bool { task != nil }

    /// Starts the timer. Fires `action` once immediately, then
    /// — after ``initialDelayMs`` of *observed* time — keeps
    /// calling it every ``repeatIntervalMs`` until ``stop()``
    /// is called (or another `start` cancels this one).
    ///
    /// `action` runs on the main actor.
    ///
    /// - Parameter action: The closure to invoke on each tick.
    public func start(action: @escaping @MainActor () -> Void) {
        stop()
        let clock = clock
        let initialDelay = Duration.milliseconds(initialDelayMs)
        let repeatInterval = Duration.milliseconds(repeatIntervalMs)
        task = Task { @MainActor in
            await Self.run(on: clock, initialDelay: initialDelay, repeatInterval: repeatInterval, action: action)
        }
    }

    /// What the task runs: the press's action, the initial delay, and the
    /// repeats, on `clock`.
    private static func run<C: Clock<Duration>>(
        on clock: C, initialDelay: Duration, repeatInterval: Duration, action: @MainActor () -> Void
    ) async {
        // Fire once immediately so a normal click still
        // gets one action — same as the previous
        // non-auto-repeating behaviour.
        action()

        // Wait the initial delay before kicking off the
        // repeat loop. If the user released the press
        // during this window the task has already been
        // cancelled and the sleep throws; we swallow it
        // because cancellation is the expected path.
        //
        // A loop around that sleep, not a bare sleep, and it is the whole
        // tap-versus-hold decision: the delay only counts while the app was
        // awake to see a release. The release that ends a click reaches
        // stdin within a few tens of milliseconds, but the run loop can
        // only read stdin between frames — so a frame that takes longer
        // than the delay (a debug build reconverting an image, say) leaves
        // the click's own release sitting unread while this task wakes and
        // fires a repeat. One click, two steps.
        //
        // A sleep that returns late IS that state: the main actor was busy,
        // so nothing was reading stdin, so silence is not evidence that the
        // button is still down. Wait again rather than guess. A release
        // cancels this task, so waiting again costs at most a late first
        // repeat on a genuine hold — never an extra step on a click, which
        // is the one the user cannot take back.
        let latest = initialDelay + Duration.milliseconds(latenessToleranceMs)
        while true {
            let startedAt = clock.now
            do {
                try await clock.sleep(for: initialDelay)
            } catch {
                return
            }
            if startedAt.duration(to: clock.now) <= latest { break }
        }

        // Past that decision the cadence is deliberately NOT gated the same
        // way: a late repeat is still a repeat the user asked for by
        // holding, and an app whose frames outlast the 80 ms interval would
        // otherwise never repeat at all.
        while !Task.isCancelled {
            // A held press is a continuous action: these repeats are the
            // sequence it produces (the first, a plain click's, is not).
            withTransaction(\.isContinuous, true) { action() }
            do {
                try await clock.sleep(for: repeatInterval)
            } catch {
                return
            }
        }
    }

    /// Stops the timer. Idempotent — calling on an already-
    /// stopped timer is a no-op.
    public func stop() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}

// MARK: - The clock a control's timer waits on

/// What the auto-repeat timers of the controls beneath wait on.
private struct AutoRepeatClockKey: EnvironmentKey, _RenderNeutralEnvironmentKey {
    static let defaultValue: any Clock<Duration> = SuspendingClock()
}

extension EnvironmentValues {
    /// The clock the auto-repeat of a `Button`, `Stepper`, `Slider` or date
    /// picker made beneath waits its delays on (``AutoRepeatTimer``): the
    /// machine's, unless a test hands in one it steps (`TestClock`).
    ///
    /// Package, not API: SwiftUI has no such value, and an app has no reason to
    /// change the clock its controls keep. Read once a control, when its timer
    /// is made, so it costs a frame nothing.
    package var autoRepeatClock: any Clock<Duration> {
        get { self[AutoRepeatClockKey.self] }
        set { self[AutoRepeatClockKey.self] = newValue }
    }
}
