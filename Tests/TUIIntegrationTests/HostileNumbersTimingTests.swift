//  🖥️ TUI — A Terminal UI framework for Swift
//  HostileNumbersTimingTests.swift
//
//  Animations, timelines and delays built from hostile durations, speeds,
//  counts and springs: each must be evaluated, and drawn mid-flight, without
//  trapping or hanging. See HostileNumbersSupport.swift.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIAppTestSupport
@testable import TUIChrome
@testable import TUICore
@testable import TUIFoundation
@testable import TUITerminalHost
@testable import TUITestSupport

@MainActor
@Suite("Hostile numbers: timing")
struct HostileNumbersTimingTests {

    /// Every way an animation is made from one number.
    private func animations(_ value: Double) -> [Animation] {
        [
            .linear(duration: value), .easeIn(duration: value), .easeOut(duration: value),
            .easeInOut(duration: value),
            .timingCurve(value, value, value, value), .timingCurve(0.2, value, 0.8, 1, duration: value),
            .spring(duration: value), .spring(duration: 0.5, bounce: value), .spring(response: value),
            .spring(response: 0.5, dampingFraction: value), .interactiveSpring(response: value),
            .interpolatingSpring(stiffness: value, damping: value), .interpolatingSpring(stiffness: 100, damping: value),
            .interpolatingSpring(mass: value, stiffness: 100, damping: 10),
            .interpolatingSpring(Spring(duration: 0.5), initialVelocity: value),
            .smooth(duration: value), .snappy(duration: value, extraBounce: value), .bouncy(extraBounce: value),
            .easeInOut.delay(value), .easeInOut.speed(value), .linear.speed(value).delay(1),
            .easeInOut.logicallyComplete(after: value), .easeInOut.delay(value).repeatCount(3),
            .linear(duration: value).repeatForever(), .linear.delay(value).repeatForever(),
            .linear.speed(value).repeatForever(autoreverses: false),
        ]
    }

    /// The instants each animation is asked about, in seconds.
    private static let instants: [Double] = [0, 0.016, 0.5, 1, 10, 1e6, 1e12, 1e18, .infinity, .nan, -1]

    @Test("An animation from any number evaluates at any instant", arguments: Hostile.doubles)
    func evaluate(value: Double) {
        for animation in animations(value) {
            _ = animation.description
            _ = animation.totalDuration
            _ = animation.logicalCompletionDuration
            _ = animation.cyclePeriod
            _ = animation.effectivePassDuration
            for instant in Self.instants {
                _ = animation.fraction(at: instant)
                _ = animation.isFinished(at: instant)
            }
        }
    }

    @Test("Any repeat count evaluates", arguments: Hostile.ints)
    func repeatCount(count: Int) {
        for animation in [Animation.linear.repeatCount(count), .easeInOut.repeatCount(count, autoreverses: false)] {
            _ = animation.totalDuration
            for instant in Self.instants {
                _ = animation.fraction(at: instant)
                _ = animation.isFinished(at: instant)
            }
        }
    }

    @Test("A spring from any number evaluates", arguments: Hostile.doubles)
    func springs(value: Double) {
        let springs = [
            Spring(duration: value), Spring(duration: 0.5, bounce: value), Spring(response: value, dampingRatio: 0.8),
            Spring(response: 0.5, dampingRatio: value), Spring(mass: value, stiffness: 100, damping: 10),
            Spring(mass: 1, stiffness: value, damping: value), Spring(settlingDuration: value, dampingRatio: value),
        ]
        for spring in springs {
            _ = spring.settlingDuration
            for instant in Self.instants {
                _ = spring.value(target: 1.0, initialVelocity: value, time: instant)
                _ = spring.velocity(target: 1.0, initialVelocity: 0, time: instant)
            }
        }
    }

    /// A view that changes between its first two frames, animated, and holds
    /// still after.
    private struct Changing: View {
        let flipped: Bool

        var body: some View {
            Text("move")
                .offset(x: flipped ? 10 : 0)
                .opacity(flipped ? 1 : 0.2)
                .foregroundStyle(flipped ? Color.red : .blue)
        }
    }

    /// The frame instants the animated draws are taken at, in nanoseconds.
    private static let frameNows: [Int64] = [0, 0, 16_666_667, 500_000_000, 10_000_000_000, 1 << 62]

    /// A root environment whose frames may animate.
    private static func animating(_ environment: inout EnvironmentValues) {
        environment.canAnimate = true
    }

    @Test("A change animated by any animation draws mid-flight", arguments: Hostile.doubles)
    func animatedDraw(value: Double) {
        for animation in animations(value) {
            let transaction = Transaction(animation: animation)
            drawHostile(configure: Self.animating, transaction: transaction, nows: Self.frameNows) { index in
                Changing(flipped: index > 0)
            }
            drawHostile(configure: Self.animating, nows: Self.frameNows) { index in
                Changing(flipped: index > 0).animation(animation, value: index > 0)
            }
        }
    }

    @Test("A timeline of any period draws", arguments: Hostile.doubles)
    func timeline(value: Double) {
        let anchor = Date(timeIntervalSinceReferenceDate: 0)
        drawHostile(nows: Self.frameNows) { _ in
            TimelineView(.periodic(from: anchor, by: value)) { context in Text("\(String(describing: context.date))") }
        }
        let start = Date(timeIntervalSinceReferenceDate: value.isFinite ? value : 0)
        drawHostile(nows: Self.frameNows) { _ in
            TimelineView(.periodic(from: start, by: 1)) { context in Text("\(String(describing: context.date))") }
        }
    }

    @Test("A notification of any duration posts, draws and expires", arguments: Hostile.doubles)
    func notification(duration: Double) {
        let service = NotificationService()
        service.post("toast", duration: duration)
        _ = service.activeEntries()
        let configure: (inout EnvironmentValues) -> Void = { $0.notificationService = service }
        drawHostile(configure: configure, nows: Self.frameNows) { _ in Text("page").notificationHost() }
        _ = service.activeEntries()
    }

    @Test("A tooltip delay of any length draws", arguments: Hostile.doubles)
    func tooltipDelay(value: Double) {
        drawHostile(Text("tip").help("help").tooltipDelay(value))
    }

    // MARK: Waits that become deadlines (hunt 11-20)
    //
    // Each of these trapped `Int(_:)` or `Int64(_:)` before its fix, which
    // ends the whole run; so each runs in a child process, where a trap is
    // this test's recorded failure. The checks are `TimingTraps`' (below), as
    // an exit test's body may capture nothing.

    #if !os(WASI)  // Exit tests need a child process, which WASI cannot start.
        @Test("A long press of any minimum duration presses, and one of forever never ends by time (FOCUS-1)")
        func longPress() async {
            await #expect(processExitsWith: .success) { await MainActor.run { TimingTraps.longPress() } }
        }

        @Test("A tooltip delay of any length makes a deadline; forever shows never and asks no wake (FOCUS-1)")
        func tooltipDeadlines() async {
            await #expect(processExitsWith: .success) { await MainActor.run { TimingTraps.tooltipDeadlines() } }
        }

        @Test("An animation of any length with a completion draws (VIEWS-3)")
        func animationCompletion() async {
            await #expect(processExitsWith: .success) { await MainActor.run { TimingTraps.animationCompletion() } }
        }

        @Test("A scroll glide under any animation draws, and one past an Int64 of nanoseconds never ends (CONC-4)")
        func glides() async {
            await #expect(processExitsWith: .success) { await MainActor.run { TimingTraps.glides() } }
        }

        @Test("A custom animation at any speed or instant evaluates (CORE2-9)")
        func customAnimation() async {
            await #expect(processExitsWith: .success) { TimingTraps.customAnimation() }
        }

        @Test("A timer text, a timer progress view and a clock-face format of any date draw (RICH-1, CONC-6, XPLAT-7)")
        func timerTexts() async {
            await #expect(processExitsWith: .success) { await MainActor.run { TimingTraps.timerTexts() } }
        }

        @Test("A symbol effect's speed and a spring-loading delay of any size convert (CONC-8, CORE2-16, DND-11)")
        func delays() async {
            await #expect(processExitsWith: .success) { TimingTraps.delays() }
        }
    #endif

    @Test(
        "An animation schedule's entries move on, however small its interval (FENV-3)",
        arguments: [1e-9, 1e-300, .leastNonzeroMagnitude, .ulpOfOne, 5.9e-8, 1.0 / 60])
    func animationScheduleEntriesMove(interval: Double) {
        // A date today, where a `Double`'s spacing is 2^-23 s: a step below
        // about 6e-8 s did not move it, and the entries never moved on.
        var entries = AnimationTimelineSchedule(minimumInterval: interval).entries(from: Date(), mode: .normal)
        let first = entries.next()
        let second = entries.next()
        #expect(first.flatMap { first in second.map { $0 > first } } == true, "\(String(describing: first)), \(String(describing: second))")
    }

    @Test("An animation timeline of any minimum interval draws (FENV-3)", arguments: Hostile.doubles)
    func animationTimeline(value: Double) {
        drawHostile(nows: Self.frameNows) { _ in
            TimelineView(.animation(minimumInterval: value)) { context in Text("\(String(describing: context.date))") }
        }
    }
}

/// The hostile-number checks the timing suite runs in child processes.
@MainActor
private enum TimingTraps {
    /// The frame instants drawn, in nanoseconds: the start, a frame on, half a
    /// second, ten seconds, and far past every finite wait a test states.
    static let nows: [Int64] = [0, 16_666_667, 500_000_000, 10_000_000_000, 1 << 62]

    /// What a gesture reported, in order.
    final class Log {
        var entries: [String] = []
    }

    static func longPress() {
        for value in Hostile.doubles + [.greatestFiniteMagnitude, -.greatestFiniteMagnitude, 9.3e9] {
            let log = Log()
            func view() -> some View {
                Text("XYZ").onLongPressGesture(minimumDuration: value) {
                    log.entries.append("perform")
                } onPressingChanged: { pressing in
                    log.entries.append("pressing \(pressing)")
                }
            }
            let harness = InputChainHarness()
            harness.frame(view())
            harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
            for now in nows {
                harness.now = now
                harness.frame(view())
            }
            harness.mouse(MouseEvent(button: .left, phase: .released, x: 1, y: 0))
            harness.frame(view())
            // A wait longer than 2^62 ns (146 years) has not run out by the last
            // frame: the press ends at the release, without the action. Before
            // the fix, 9.3e9 s wrapped to an expiry in the past and performed.
            if value >= 4.7e9 {
                precondition(log.entries == ["pressing true", "pressing false"], "\(value): \(log.entries)")
            }
        }
    }

    static func tooltipDeadlines() {
        for value in Hostile.doubles + [.greatestFiniteMagnitude, 9.3e9] {
            let state = TooltipState()
            state.hovering("tip", handlerID: nil, nowNanos: 1_000, delaySeconds: value)
            let pending = state.pendingDeadlineNanos(nowNanos: 1_000)
            let shown = state.resolved(nowNanos: .max - 1) != nil
            if value >= 9.3e9 {
                precondition(pending == nil && !shown, "\(value): never shows, and asks no wake")
            } else if !(value > 0) || value == 1e-300 {
                precondition(state.resolved(nowNanos: 1_000) != nil, "\(value): no wait")
            }
            let focusing = TooltipState()
            focusing.focusing(
                "tip", focusID: "f", handlerID: nil, nowNanos: 1_000, delaySeconds: value, revealsItself: true)
            _ = focusing.pendingDeadlineNanos(nowNanos: 1_000)
            // The focused route, through a whole frame: a focused control with
            // help publishes its text on every walk.
            drawHostile(Button("b") {}.help("help").tooltipDelay(value))
        }
    }

    /// A view that changes between its first two frames.
    struct Changing: View {
        let flipped: Bool

        var body: some View {
            Text("move").offset(x: flipped ? 10 : 0).opacity(flipped ? 1 : 0.2)
        }
    }

    /// A root environment whose frames may animate.
    static func animating(_ environment: inout EnvironmentValues) {
        environment.canAnimate = true
    }

    static func animationCompletion() {
        for value in Hostile.doubles + [1e10, 9.2e9] {
            for animation in [Animation.linear(duration: value), .easeInOut.speed(value), .linear.delay(value)] {
                var transaction = Transaction(animation: animation)
                transaction.addAnimationCompletion {}
                transaction.addAnimationCompletion(criteria: .removed) {}
                drawHostile(configure: animating, transaction: transaction, nows: nows) { index in
                    Changing(flipped: index > 0)
                }
            }
        }
    }

    static func glides() {
        for value in Hostile.doubles + [1e10, 9.2e9] {
            for animation in [Animation.linear(duration: value), .easeInOut.speed(value), .linear.delay(value)] {
                let glide = ScrollGlide(
                    distance: 20, animation: animation, startNanos: 0, landing: .top,
                    viewport: CellSize(width: 10, height: 5))
                for now in nows {
                    _ = glide.isFinished(atNanos: now)
                    _ = glide.place(atNanos: now)
                }
                if let total = animation.totalDuration, total >= 9.3e9 {
                    precondition(!glide.isFinished(atNanos: 1 << 62), "\(animation) is longer than the clock")
                }
                // Through a scroll view: a `ScrollPosition` request drawn under
                // the animation.
                var position = ScrollPosition()
                let binding = Binding(get: { position }, set: { position = $0 })
                let harness = InputChainHarness(width: 20, height: 5) { $0.canAnimate = true }
                func page() -> some View {
                    ScrollView { LazyVStack(spacing: 0) { ForEach(0..<40, id: \.self) { Text("row \($0)") } } }
                        .scrollPosition(binding)
                }
                harness.frame(page())
                position.scrollTo(id: 20, anchor: .top)
                harness.transaction = Transaction(animation: animation)
                for now in nows {
                    harness.now = now
                    harness.frame(page())
                }
            }
        }
    }

    /// A custom animation: the built-in linear curve, by hand.
    struct CustomLinear: CustomAnimation {
        var duration: TimeInterval

        func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
            guard time < duration else { return nil }
            return value.scaled(by: time / duration)
        }
    }

    nonisolated static func customAnimation() {
        for value in Hostile.doubles {
            for animation in [Animation(CustomLinear(duration: 1)).speed(value), Animation(CustomLinear(duration: 1))] {
                for instant in [0, 0.1, 1e6, 1e18, .infinity, .nan, -1] as [Double] {
                    _ = animation.fraction(at: instant)
                    _ = animation.isFinished(at: instant)
                }
            }
        }
        // "Arrive at once" arrives: every frame of an infinite speed is the end.
        precondition(Animation(CustomLinear(duration: 1)).speed(.infinity).fraction(at: 0.1) == 1)
    }

    static func timerTexts() {
        let now = Date()
        let instants: [Double] = [.infinity, -.infinity, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, 1e300, 0]
        for value in instants {
            let date = Date(timeIntervalSinceReferenceDate: value)
            let (low, high) = (min(now, date), max(now, date))
            drawHostile(Text(timerInterval: low...high))
            drawHostile(Text(timerInterval: low...high, countsDown: false))
            drawHostile(Text(timerInterval: low...high, pauseTime: high))
            drawHostile(ProgressView(timerInterval: low...high))
            drawHostile(ProgressView(timerInterval: low...high, countsDown: false))
            drawHostile(Text(date, style: .timer))
            drawHostile(Text(date, style: .relative))
            drawHostile(Text(date, style: .offset))
            if low < high {
                _ = SystemFormatStyle.Timer(countingDownIn: low..<high).format(now)
                _ = SystemFormatStyle.Timer(countingDownIn: low..<high, maxPrecision: .milliseconds(10)).format(now)
            }
            _ = SystemFormatStyle.Stopwatch(startingAt: date).format(now)
        }
        drawHostile(Text(Date(timeIntervalSinceReferenceDate: .nan), style: .timer))
    }

    nonisolated static func delays() {
        // CONC-8: the ticks a near-zero speed shows each frame for, held to
        // `Int32.max` as `AnimationClock.frameTicks(forSeconds:)` holds them.
        precondition(SymbolBreath.frameTicks(speed: 1e-300) == Int(Int32.max))
        precondition(SymbolBreath.frameTicks(speed: 3e-19) == Int(Int32.max))
        precondition(SymbolBreath.frameTicks(speed: 1) == AnimationClock.standardFrameTicks)
        // CORE2-16 and DND-11: a delay of 1e17 s is a delay, not a trap.
        for text in ["1e17", "1e300", "9.3e15"] {
            precondition(TerminalClient.springLoadingDelayRequested(environment: ["TUI_SPRING_LOADING_DELAY": text]) != nil)
            precondition(TerminalClient.springLoadingDelay(preferenceValue: text) != nil)
        }
        // DND-11: a duration past 584 years is never, not a second ago.
        precondition(Duration.seconds(Int64.max).clampedNanoseconds == .max)
        precondition(Duration.seconds(1).clampedNanoseconds == 1_000_000_000)
        precondition(Duration.deadline(5, plus: .max) == .max)
        precondition(Duration.deadline(5, plus: 10) == 15)
    }
}
