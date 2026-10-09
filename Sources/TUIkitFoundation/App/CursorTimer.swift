//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CursorTimer.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

/// The app's one animation TIMER, and the two clocks it serves: the
/// focus-relative one the cursor's blink and every focus indicator's breath
/// read, and the monotonic one a spinner's or an indeterminate bar's run replays
/// on. A view draws its own frame from the frame clock, `frameNowNanos`, which
/// every render shows this timer before anything reads it, so the frame a view
/// draws and the frame a replay splices are one instant (§74 of
/// `Opacity as composition.md`).
///
/// **Both clocks are measured, not counted.** ``AnimationClock/content`` is
/// ``MonotonicClock`` itself, with no origin of its own, and
/// ``AnimationClock/cursor`` is the same reading less the moment the focus last
/// moved, floored to a 50 ms step: 3 ticks of 1/60 s, a whole number of nanoseconds,
/// so a cursor run's steps begin on the same tick instants as a content run's. The
/// timer keeps one snapshot of
/// that clock, taken whenever a frame renders (``observe(nowNanos:)``) or the
/// timer wakes (``creditWake(atNanos:)``), so every read inside one frame agrees.
///
/// It used to count instead: each wake added the sleep it had ASKED for. A wake
/// is late — a `Task.sleep` resumed on the main actor overshoots by a median of
/// 6–13 ms, whatever its length — and the lateness was never credited, so the
/// clock ran slow by `1 + N·L` for `N` wakes a simulated second. The Spinners
/// page wakes about 52 times a simulated second, and every spinner on it ran at
/// about two thirds of its speed, all by the same factor.
///
/// `CursorTimer` maintains two phase values for different animation styles:
/// - `blinkVisible`: Boolean for sharp on/off blinking
/// - `pulsePhase`: Smooth 0-1 cosine wave for pulsing, starting bright
///
/// There used to be a second clock — a `PulseTimer` for focus indicators — and
/// having two was a bug rather than a feature: they ran at different rates from
/// different formulas, so the same focus pulse breathed at 2 s on a section's
/// border and 0.8 s on the controls inside it, depending only on which route
/// the view took. One clock and one formula now serve both, with the animation
/// chosen per element by ``View/selectionIndicatorStyle(_:)`` and its speed by
/// ``View/indicatorAnimationSpeed(_:for:)``.
///
/// The timer is a single `@MainActor` `Task` that sleeps between ticks (the
/// same pattern as ``AutoRepeatTimer``). Staying on the main actor means the
/// snapshot is never mutated off-thread, so the phases read during render
/// are race-free.
///
/// ## Animation Speeds
///
/// A blink is two frames, visible then hidden, each shown for half the cycle. A
/// pulse is a cosine sampled once per 50 ms step. See ``cycleLayout(of:speed:)``.
///
/// The caret and the focus emphasis each run at an ``IndicatorAnimationSpeed``,
/// the one set for ``IndicatorAnimations/textCursor`` or
/// ``IndicatorAnimations/focusEmphasis``: a 700 ms blink (``standardBlinkCycle``)
/// and an 800 ms pulse (``standardPulseCycle``) at the standard rate, each divided
/// by the rate.
///
/// ## Usage
///
/// ```swift
/// let cursor = CursorTimer(renderNotifier: appState)
/// cursor.start()
/// // In render code:
/// if cursor.blinkVisible(for: .automatic) {
///     // show cursor
/// }
/// let phase = cursor.pulsePhase(for: .automatic)
/// ```
@MainActor
package final class CursorTimer {
    /// How often a view that reads the phase AS IT RENDERS is re-rendered.
    /// Taken from ``AnimationClock/standardFrameTicks`` rather than written here so
    /// there is one number, not two that can disagree.
    package nonisolated static let standardFrameSeconds = AnimationClock.seconds(forTicks: AnimationClock.standardFrameTicks)

    /// The same, in whole nanoseconds, from the instant its tick begins — the lattice the
    /// focus epoch is floored to. Internal rather than private so the spec for the
    /// framework's standard durations can check it.
    nonisolated static let standardFrameNanos = UInt64(AnimationClock.nanoseconds(atTick: Int64(AnimationClock.standardFrameTicks)))

    /// Where a wake reads the time. The clock `FrameClock` reads too, which is
    /// what makes a wake's reading and a frame's comparable at all; injectable
    /// so a test can step it, as `MouseEventDispatcher.nowNanos` is.
    package var nowNanos: () -> UInt64 { get { _nowNanos } set { _nowNanos = newValue } }

    /// ``nowNanos``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _nowNanos: () -> UInt64 = { MonotonicClock.nowNanoseconds }

    /// The latest instant this timer has been shown, in nanoseconds on
    /// ``MonotonicClock``: the source of truth for both clocks.
    ///
    /// Only ever raised, so a reading older than one already seen (a wake queued
    /// behind a render that stamped a later frame) cannot run the phases back.
    private(set) var snapshotNanos: UInt64 = 0

    /// Where ``AnimationClock/cursor``'s zero sits, on the 3-tick, 50 ms lattice, or `nil`
    /// until the next ``observe(nowNanos:)`` sets it.
    ///
    /// Cleared whenever the focus moves, which is how the blink and the focus
    /// breath restart at their bright end without disturbing anything else. The
    /// clear used to zero the one elapsed time every animation in the app read:
    /// pressing Tab restarted every indeterminate progress bar, every spinner and
    /// every breathing label along with the cursor.
    ///
    /// Set lazily, at the frame after the change, not at the change. See
    /// ``restartFocusPhase()`` for what setting it early did. Floored to the
    /// lattice so a caret's and a breath's changes land on the same 1/60 s tick
    /// instants as every run on the content clock, and the wakes coalesce — at the
    /// price of a first half that can be up to one step short: 300–350 ms of a 350 ms
    /// blink.
    ///
    /// Three ticks, not one, because three ticks are the fewest that are a whole number
    /// of nanoseconds. An epoch on tick `E`'s instant, 50,000,000·m ns, plus tick `j`'s
    /// instant is exactly tick `E + j`'s instant. An epoch floored to single ticks would
    /// put many of those sums 1 ns past their tick (16,666,667 + 33,333,334 is
    /// 50,000,001), and a cursor run would change a nanosecond after the content runs
    /// beside it.
    package var focusEpochNanos: UInt64? { get { _focusEpochNanos } set { _focusEpochNanos = newValue } }

    /// ``focusEpochNanos``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _focusEpochNanos: UInt64?

    /// Shows the timer the time: a frame's `frameNow`, before anything in that
    /// frame reads a phase, or a wake's own reading.
    ///
    /// **One instant per frame, by convention rather than by construction.** A
    /// render observes the time it stamps on the frame, so a same-width spinner
    /// reading ``elapsed(for:)`` and a declined one reading `frameNowNanos` draw
    /// the same step. That holds because every reading comes from
    /// ``MonotonicClock`` — `FrameClock.nowNanos` and ``nowNanos`` both read it —
    /// and because the snapshot only rises: a caller that passes a frame time
    /// EARLIER than one the timer has already seen (a test, stamping its own
    /// frames) keeps the later snapshot, and the two then differ.
    package func observe(nowNanos now: UInt64) {
        snapshotNanos = max(snapshotNanos, now)
        if focusEpochNanos == nil {
            focusEpochNanos = snapshotNanos - snapshotNanos % Self.standardFrameNanos
        }
    }

    /// How far `clock` has run, at the last snapshot.
    ///
    /// The two clocks share one snapshot and differ only in where their zero is —
    /// see ``AnimationClock``. `.content` has no zero of its own: it is the
    /// monotonic reading, so every run on it is in phase with every other, and a
    /// spinner that appears starts where the shared clock is rather than at its
    /// first frame.
    ///
    /// In seconds, from whole nanoseconds. Converting back to whole nanoseconds, as
    /// every step boundary does, gives the same count below 2^51 ns, about 26 days of
    /// uptime. Past that, a wake landing exactly on a tick's instant can read the tick
    /// before and draw its change a tick late (real wakes are milliseconds late, so it
    /// is rare), but a render and a replay index the same `Double` and agree.
    package func elapsed(for clock: AnimationClock) -> Double {
        switch clock {
        case .content: Double(snapshotNanos) / 1_000_000_000
        case .cursor: focusEpochNanos.map { Double(snapshotNanos - $0) / 1_000_000_000 } ?? 0
        }
    }

    /// Elapsed standard steps, for the phase formulas that are still defined on a
    /// grid: whole ``AnimationClock/standardFrameTicks``-tick frames, 50 ms each.
    ///
    /// Derived rather than counted, so a variable sleep keeps every phase's
    /// wall-clock meaning: a breath is a breath whether the loop woke six times
    /// or sixty on the way through it.
    ///
    /// Focus-relative: every formula that reads this is a
    /// ``AnimationClock/cursor`` one.
    var elapsedSteps: Int { steps(for: .cursor) }

    /// ``elapsed(for:)`` on the 50 ms step grid the phase formulas are written in.
    /// Steps, not ticks: a tick is 1/60 s, and a step is three of them.
    package func steps(for clock: AnimationClock) -> Int {
        // Through the one conversion every step boundary shares, so the phase formulas
        // and the pre-rendered runs agree on which step an instant is in — a floor in
        // seconds put a summed 0.35 s in step 6, when this clock was a sum. Clamped
        // rather than narrowed: `Int` is 32 bits on wasm32.
        Int(clamping: AnimationClock.step(atElapsed: elapsed(for: clock), frameTicks: AnimationClock.standardFrameTicks))
    }

    /// Whether the cursor clock was read during the current render frame.
    ///
    /// Reset by ``beginFrameReadTracking()`` before each render; set when
    /// ``blinkVisible(for:)`` or ``pulsePhase(for:)`` is consulted. The run loop
    /// reads it after the frame to decide whether the cursor is still animating
    /// (a text field is focused) and the timer should keep ticking.
    package var didReadThisFrame: Bool { _didReadThisFrame }

    /// ``didReadThisFrame``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _didReadThisFrame = false

    /// Clears the per-frame read flag. Call before each render pass.
    package func beginFrameReadTracking() {
        _didReadThisFrame = false
    }

    /// The running animation task, or `nil` if stopped.
    package var task: Task<Void, Never>? { get { _task } set { _task = newValue } }

    /// ``task``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _task: Task<Void, Never>?

    /// How long the next wake-up is away.
    ///
    /// The clock's own interval by default — what a view that builds its
    /// appearance from the phase as it renders needs, because only that view
    /// knows what it would draw next. A frame whose animation is all
    /// pre-rendered runs can say exactly when the picture next changes
    /// (`RenderLoop.timeUntilNextChange(elapsed:)`), and the clock then sleeps
    /// precisely that long instead of waking to compare identical pictures —
    /// or, for a run asking for a rate finer than the interval, sooner than the
    /// interval. Never shorter than the time to the next 1/60 s tick instant after the
    /// snapshot it was planned at (see ``advance(by:)``).
    /// Readable so a test can assert that a served animation replay re-based the
    /// sleep — the value never leaves this class otherwise. Settable within the
    /// module only because the timer control in CursorTimer+Timer.swift resets it
    /// to ``standardFrameSeconds`` (`stop()`, `restartFocusPhase()`); the run loop
    /// only ever writes it through ``advance(by:)``.
    package var sleepSeconds: Double { get { _sleepSeconds } set { _sleepSeconds = newValue } }

    /// ``sleepSeconds``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _sleepSeconds = CursorTimer.standardFrameSeconds

    /// Sets how far the next wake-up is. Takes effect after the current sleep.
    ///
    /// For a RENDER, which has just replaced the runs and may be about to start the
    /// timer: `start()` reads this for its first sleep. A running timer replans at
    /// every wake through ``planner`` and does not depend on it.
    ///
    /// Never shorter than ``secondsToNextTick``, whatever it is asked for.
    package func advance(by seconds: Double) {
        sleepSeconds = max(secondsToNextTick, seconds)
    }

    /// The shortest sleep ``advance(by:)`` plans: from the snapshot to the instant the
    /// next 1/60 s tick begins, at most a tick.
    ///
    /// A safety floor rather than a policy, so a plan of nothing cannot spin a core.
    /// Every change a plan can be for — a run's step, the reader's boundary, a
    /// stand-in's wake — begins on a tick instant strictly after the snapshot, so this
    /// binds only on a plan that is already due, and it ends that plan on the lattice
    /// every run changes on. It used to be 10 ms: a wake is late by a few
    /// milliseconds, so the change after a late wake could be due sooner than that,
    /// and was drawn late, off the lattice — a 1-tick run woken 12 ms after its
    /// boundary slept 10 ms for a change 4,666,667 ns away. Not "one tick from now"
    /// either, which is off the lattice whenever the wake is.
    private var secondsToNextTick: Double {
        let snapshot = Int64(clamping: snapshotNanos)
        let next = AnimationClock.nanoseconds(ofNextTickMultiple: 1, after: snapshot)
        return Double(next - snapshot) / 1_000_000_000
    }

    /// How the NEXT sleep is chosen, asked at the moment the timer wakes.
    ///
    /// The run loop installs it once, as `RenderLoop.timeUntilNextChange(elapsed:)`.
    /// The plan used to arrive through ``advance(by:)``, called by the loop AFTER it had
    /// served the tick — but this task keeps the main actor straight from posting that
    /// tick back to the top of its loop, so by the time the loop ran the timer had
    /// already begun its next sleep, with the value planned one wake EARLIER. While every
    /// plan was the same length the lag could not be seen. Wherever plans vary — two runs
    /// at different rates on one page, a quantised pulse holding a shade — each sleep was
    /// the previous wake's: a change was slept through, and the next landed on top of it.
    /// It was half of the owner's "complex period" blink (the other half being the step
    /// floor fixed beside `AnimationClock.step(atElapsed:frameTicks:)`, which is what
    /// made a blink's plans vary at all).
    ///
    /// Asked here, after taking the time of the wake, the plan and the sleep are the
    /// same wake's, and no ordering between the task and the loop can come between them.
    /// `nil` leaves the sleep where ``advance(by:)`` last put it.
    package var planner: (((AnimationClock) -> Double) -> Double)? { get { _planner } set { _planner = newValue } }

    /// ``planner``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _planner: (((AnimationClock) -> Double) -> Double)?

    /// The render notifier to trigger re-renders.
    package var renderNotifier: AppState? { get { _renderNotifier } set { _renderNotifier = newValue } }

    /// ``renderNotifier``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private weak var _renderNotifier: AppState?

    /// Creates a new cursor timer.
    ///
    /// - Parameter renderNotifier: The app state to notify when a re-render
    ///   is needed. Held weakly to avoid retain cycles.
    package init(renderNotifier: AppState) {
        self._renderNotifier = renderNotifier
    }

    deinit {
        _task?.cancel()
    }
}

// MARK: - Phase Computation

extension CursorTimer {
    /// Returns whether a blink is in its visible half now.
    ///
    /// - Parameter speed: The speed of the indicator that blinks.
    /// - Returns: `true` if the blink is visible, `false` if hidden.
    func blinkVisible(for speed: IndicatorAnimationSpeed) -> Bool {
        _didReadThisFrame = true
        return Self.blinkVisible(atFrame: Self.cycleLayout(of: .blink, speed: speed).timing.step(on: self))
    }

    /// A blink's cycle at the standard speed, visible then hidden: 700 ms, 350 ms
    /// each, 21 ticks of 1/60 s.
    ///
    /// Each half is one frame of the blink's run, so a replayed blink holds it
    /// exactly, whatever its length. A view that reads the blink as it renders is
    /// re-rendered on the 50 ms cursor steps, though, so for that view a half that
    /// is not a whole number of steps still flips up to a step late. The standard
    /// blink was once 660 ms, and its live blink wobbled between a 600 ms and a
    /// 700 ms period.
    nonisolated static let standardBlinkCycle: TimeInterval = 0.7

    /// A breath's cycle at the standard speed, bright to dim to bright: 800 ms.
    nonisolated static let standardPulseCycle: TimeInterval = 0.8

    /// How a cycle of `animation` at `speed` is laid out: how many frames it has,
    /// and how long each is shown, on which clock.
    ///
    /// Two kinds of cycle, laid out differently on purpose:
    /// - **A blink is discrete.** Visible, then hidden: two frames, each shown for
    ///   ``standardBlinkCycle``'s half, 21 ticks, at the standard rate, and for
    ///   `IndicatorAnimationSpeed.frameTicks(standard:)` of it at `speed`, the
    ///   nearest whole ticks. It used to be one frame per 50 ms step, seven visible
    ///   and seven hidden. That holds only while a half is a whole number of steps,
    ///   and it makes a slower blink more frames rather than longer ones.
    /// - **A pulse is continuous.** ``standardPulseCycle`` divided by the rate, in
    ///   frames of one cursor step (`AnimationClock.standardFrameTicks` ticks), as
    ///   many as come nearest, at least two and at most `RampLayout.maximumFrameCount`,
    ///   past which each frame is several steps
    ///   (`IndicatorAnimationSpeed.rampLayout(standardCycle:frameTicks:)`). A slowed
    ///   breath stays as smooth, a quickened one wakes the loop no more often, and
    ///   every frame changes on a cursor step. At the standard 800 ms it is 16 frames.
    /// - `.none` is one frame, a still picture.
    ///
    /// Both animate on the focus-relative clock. The whole cycle is built from this
    /// and from the two frame formulas below, and the live readers step through the
    /// same layout, so a replayed run and a render that reads the clock show the
    /// same frame at the same instant: one layout, not two that can drift apart.
    ///
    /// `nonisolated`: it is arithmetic on constants and reads no timer.
    nonisolated static func cycleLayout(
        of animation: TextCursorStyle.Animation, speed: IndicatorAnimationSpeed
    ) -> CycleLayout {
        switch animation {
        case .none:
            return CycleLayout(frameCount: 1, timing: .cursorTick)
        case .blink:
            return CycleLayout(
                frameCount: 2,
                timing: IndicatorCycleTiming(
                    frameTicks: speed.frameTicks(standard: standardBlinkCycle / 2), clock: .cursor))
        case .pulse:
            let ramp = speed.rampLayout(
                standardCycle: standardPulseCycle, frameTicks: AnimationClock.standardFrameTicks)
            return CycleLayout(
                frameCount: ramp.frameCount,
                timing: IndicatorCycleTiming(frameTicks: ramp.frameTicks, clock: .cursor))
        }
    }

    /// A cycle's frame count and the timing its frames step on. See
    /// ``cycleLayout(of:speed:)``.
    struct CycleLayout: Equatable, Sendable {
        let frameCount: Int
        let timing: IndicatorCycleTiming
    }

    /// Whether the caret is visible at `frame` of a blink: the first of its two
    /// frames, and every other one after it.
    ///
    /// Static, and the instance method above defers to it, so a producer that
    /// pre-renders its whole cycle (see ``AnimatedCellRun``) computes exactly what
    /// a live render would. Reading it does NOT mark the frame as having consulted
    /// the clock, which is what lets such a producer be replayed rather than
    /// re-rendered.
    nonisolated static func blinkVisible(atFrame frame: Int) -> Bool {
        frame.isMultiple(of: 2)
    }

    /// Returns the pulse phase (0-1) for smooth cursor animation.
    ///
    /// The phase follows a cosine curve for smooth breathing, and it starts at
    /// its BRIGHTEST:
    /// - 0.0: Dimmest
    /// - 1.0: Brightest
    ///
    /// Starting bright is what makes `restartFocusPhase()` mean "show me now".
    /// The clock is reset whenever the focus moves, and a breath that began at
    /// its dim end left the newly focused control looking unfocused for a third
    /// of a second — the moment it most needs to be visible.
    ///
    /// - Parameter speed: The speed of the indicator that pulses.
    /// - Returns: Phase value between 0 and 1.
    func pulsePhase(for speed: IndicatorAnimationSpeed) -> Double {
        _didReadThisFrame = true
        return pulsePhaseNow(speed: speed)
    }

    /// The breath phase right now, WITHOUT marking the clock as consumed.
    ///
    /// The phase seam `EnvironmentValues.pulsePhase` carries, so a view that
    /// reads the phase directly sees the same breath as one that resolves a
    /// ``SelectionEmphasis`` — there is one clock and one formula behind both.
    /// (Demand is tracked at the seam's own getter, which is why this one must
    /// not set `didReadThisFrame`.)
    ///
    /// At ``IndicatorAnimationSpeed/automatic``, the focus emphasis's speed where
    /// nothing sets one: the seam is one value for the whole frame, and cannot see
    /// a subtree's `indicatorAnimationSpeed(_:for:)`.
    package var breathPhase: Double {
        pulsePhaseNow(speed: .automatic)
    }

    /// The pulse phase at the last snapshot, read through the pulse's own layout.
    private func pulsePhaseNow(speed: IndicatorAnimationSpeed) -> Double {
        let layout = Self.cycleLayout(of: .pulse, speed: speed)
        return Self.pulsePhase(atFrame: layout.timing.step(on: self), of: layout.frameCount)
    }

    /// The pulse phase at `frame` of a pulse of `count` frames
    /// (``Color/breathPhase(atFrame:of:)``). See
    /// ``blinkVisible(atFrame:)`` for why this is static and why reading it is not a
    /// volatile read.
    nonisolated static func pulsePhase(atFrame frame: Int, of count: Int) -> Double {
        Color.breathPhase(atFrame: frame, of: count)
    }
}
