//  🖥️ TUI — A Terminal UI framework for Swift
//  CustomAnimationTests.swift
//
//  `CustomAnimation` (decisions O3): integrated on the frame grid as it is
//  asked for, kept, and composed with delays, speeds and repeats once it ends.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUICore

/// Linear over `duration` seconds, then finished. `name` makes a value no other
/// test uses: equal custom animations share one integration, for the life of
/// the process.
private struct Linear: CustomAnimation {
    var duration: TimeInterval
    var name = ""

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        guard time < duration else { return nil }
        return value.scaled(by: time / duration)
    }
}

/// Counts its own calls in its state, and moves a tenth of the remaining way
/// each frame — a curve only an integrated, stateful animation can draw.
private struct Halving: CustomAnimation {
    enum Steps: AnimationStateKey {
        static let defaultValue = 0
    }

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        let steps = context.state[Steps.self]
        context.state[Steps.self] = steps + 1
        if steps == 3 { context.isLogicallyComplete = true }
        guard steps < 30 else { return nil }
        return value.scaled(by: 1 - pow(0.9, Double(steps)))
    }
}

/// `Animation(_:)` of an existential, opened: `Animation.base` is one.
private func animation(running base: any CustomAnimation) -> Animation {
    func make<A: CustomAnimation>(_ base: A) -> Animation { Animation(base) }
    return _openExistential(base, do: make)
}

@Suite("CustomAnimation")
struct CustomAnimationTests {
    private let frame = 1.0 / 60

    @Test("A custom animation is sampled on the frame grid, and finishes at the target")
    func sampledOnTheFrameGrid() {
        let animation = Animation(Linear(duration: 1, name: "sampled"))
        #expect(abs(animation.fraction(at: 0.5) - 0.5) < 1e-9)
        // Between frames, the frame it falls in.
        #expect(abs(animation.fraction(at: 0.5 + frame / 2) - 0.5) < 1e-9)
        #expect(animation.totalDuration == nil, "unknown until integrated that far")
        #expect(!animation.isFinished(at: 0.9))
        #expect(animation.isFinished(at: 1.0))
        #expect(animation.totalDuration.map { abs($0 - 1) < 1e-9 } == true, "\(String(describing: animation.totalDuration))")
        #expect(animation.fraction(at: 2) == 1)
    }

    @Test("Its state is kept from one frame to the next, and a frame asked again reads the same value")
    func statefulAndKept() {
        let animation = Animation(Halving())
        let third = animation.fraction(at: 3 * frame)
        #expect(abs(third - (1 - pow(0.9, 3))) < 1e-9, "\(third)")
        // Asked out of order and again: the kept values, not a fresh integration.
        _ = animation.fraction(at: 10 * frame)
        #expect(animation.fraction(at: 3 * frame) == third)
        #expect(animation.isFinished(at: 30 * frame) && !animation.isFinished(at: 29 * frame))
        // Logically complete when the animation said so: at frame 3.
        #expect(animation.logicalCompletionDuration.map { abs($0 - 3 * frame) < 1e-9 } == true)
    }

    @Test("Once it has ended, delay, speed and repeat apply as to any curve")
    func composes() {
        let delayed = Animation(Linear(duration: 1)).delay(0.5)
        #expect(delayed.fraction(at: 0.25) == 0)
        #expect(abs(delayed.fraction(at: 1.0) - 0.5) < 1e-9)
        let fast = Animation(Linear(duration: 1)).speed(2)
        #expect(abs(fast.fraction(at: 0.25) - 0.5) < 1e-9)
        let twice = Animation(Linear(duration: 1)).repeatCount(2, autoreverses: true)
        #expect(abs(twice.fraction(at: 0.5) - 0.5) < 1e-9)
        // The second pass runs back once the first has ended.
        #expect(abs(twice.fraction(at: 1.25) - 0.75) < 1e-9, "\(twice.fraction(at: 1.25))")
        #expect(twice.isFinished(at: 2.0))
        #expect(twice.fraction(at: 2.5) == 0, "two autoreversing passes end where they began")
        let forever = Animation(Linear(duration: 1)).repeatForever(autoreverses: false)
        _ = forever.fraction(at: 1.5)
        #expect(forever.cyclePeriod.map { abs($0 - 1) < 1e-9 } == true)
    }

    @Test("Equal custom animations make equal animations, and base hands the animation back")
    func equalityAndBase() {
        // Two animations made apart — two integration tables — compare equal.
        let one = Animation(Linear(duration: 1))
        let another = Animation(Linear(duration: 1))
        #expect(one == another)
        #expect(Animation(Linear(duration: 1)) != Animation(Linear(duration: 2)))
        let easeIn = animation(running: Animation.easeIn.base)
        let delayedSpring = animation(running: Animation.spring.delay(1).base)
        #expect(easeIn == .easeIn)
        #expect(delayedSpring == Animation.spring.delay(1))
        #expect(Animation(Linear(duration: 1)).base is Linear)
        #expect("\(Animation(Linear(duration: 1)))".hasPrefix("Animation(Linear("))
    }

    @Test("Equal custom animations share one integration; a different one has its own")
    func sharedIntegration() {
        let first = Animation(Linear(duration: 1, name: "shared"))
        _ = first.isFinished(at: 1.5)
        let again = Animation(Linear(duration: 1, name: "shared"))
        #expect(again.totalDuration != nil, "made again, it is the integration already done")
        #expect(Animation(Linear(duration: 1, name: "other")).totalDuration == nil)
    }

    @Test("Animation.animate answers for a custom animation and for TUI's own curves")
    func animateAndVelocity() {
        var context = AnimationContext<Double>()
        #expect(Animation(Linear(duration: 1)).animate(value: 10.0, time: 0.25, context: &context) == 2.5)
        #expect(Animation(Linear(duration: 1)).animate(value: 10.0, time: 1, context: &context) == nil)
        let linear = Animation.linear(duration: 1)
        #expect(linear.animate(value: 10.0, time: 0.5, context: &context).map { abs($0 - 5) < 1e-9 } == true)
        #expect(linear.animate(value: 10.0, time: 1.5, context: &context) == nil)
        #expect(linear.velocity(value: 10.0, time: 0.5, context: context).map { abs($0 - 10) < 1e-6 } == true)
        #expect(Animation.spring.shouldMerge(previous: .spring, value: 1.0, time: 0, context: &context))
        #expect(!linear.shouldMerge(previous: .spring, value: 1.0, time: 0, context: &context))
    }
}
