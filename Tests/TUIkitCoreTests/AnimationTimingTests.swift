//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationTimingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitCore

@Suite("Animation timing")
struct AnimationTimingTests {

    @Test("A delay holds the value at its start, then runs the full curve")
    func delayShiftsWithoutShortening() {
        let animation = Animation.linear(duration: 1).delay(0.5)
        #expect(animation.fraction(at: 0) == 0)
        #expect(animation.fraction(at: 0.4) == 0)
        #expect(abs(animation.fraction(at: 1.0) - 0.5) < 1e-6)
        #expect(animation.fraction(at: 1.5) == 1)
        #expect(animation.totalDuration == 1.5)
    }

    @Test("Speed scales the delay too")
    func speedScalesEverything() {
        // SwiftUI's `speed(_:)` is a rate multiplier on the whole animation,
        // delay included — otherwise `.speed(2)` on a delayed animation would
        // change the gap between the trigger and the movement.
        let animation = Animation.linear(duration: 1).delay(1).speed(2)
        #expect(animation.effectiveDelay == 0.5)
        #expect(animation.effectivePassDuration == 0.5)
        #expect(animation.totalDuration == 1.0)
        #expect(abs(animation.fraction(at: 0.75) - 0.5) < 1e-6)
    }

    @Test("A delay written after a speed is not scaled by it, as SwiftUI's is not (p10)")
    func delayAfterSpeed() {
        let animation = Animation.linear(duration: 0.4).speed(2).delay(0.6)
        #expect(abs(animation.effectiveDelay - 0.6) < 1e-12)
        #expect(abs(animation.totalDuration! - 0.8) < 1e-12)
        // And a later speed scales everything inside it, that delay too.
        #expect(abs(animation.speed(2).effectiveDelay - 0.3) < 1e-12)
    }

    /// The value at every 0.05 s from 0 to `end`, to two decimals: the shape
    /// the SwiftUI probe p11 prints.
    private func series(_ animation: Animation, until end: Double) -> [Double] {
        stride(from: 0.0, through: end + 1e-9, by: 0.05).map { (animation.fraction(at: $0) * 100).rounded() / 100 }
    }

    @Test("A delay written before a repeat comes before every pass, reversed ones too (p11)")
    func delayRepeatsWithThePass() {
        let animation = Animation.linear(duration: 0.4).delay(0.3).repeatForever(autoreverses: true)
        let values = series(animation, until: 1.5)
        // Waits 0.3 s at 0, rises over 0.4 s, waits 0.3 s at 1, falls over
        // 0.4 s, and waits again at 0: a 1.4 s cycle.
        #expect(values[0...6].allSatisfy { $0 == 0 }, "\(values)")
        #expect(values[10] == 0.5)
        #expect(values[14...20].allSatisfy { $0 == 1 }, "\(values)")
        #expect(values[24] == 0.5)
        #expect(values[28...30].allSatisfy { $0 == 0 }, "\(values)")
        #expect(abs(animation.cyclePeriod! - 1.4) < 1e-6)
        // A count ends after its last pass's wait and curve.
        #expect(abs(Animation.linear(duration: 0.4).delay(0.3).repeatCount(2).totalDuration! - 1.4) < 1e-6)
    }

    @Test("A delay written after a repeat comes once (p11)")
    func delayAfterRepeatLeads() {
        let animation = Animation.linear(duration: 0.4).repeatCount(2, autoreverses: false).delay(0.3)
        #expect(animation.effectiveDelay == 0.3)
        #expect(abs(animation.totalDuration! - 1.1) < 1e-6)
        #expect(abs(animation.fraction(at: 0.8) - 0.25) < 1e-6, "the second pass follows the first at once")
        // Both: the inner wait repeats, the outer one leads.
        let both = Animation.linear(duration: 0.4).delay(0.2).repeatCount(2, autoreverses: false).delay(0.3)
        #expect(abs(both.totalDuration! - 1.5) < 1e-6)
        #expect(both.fraction(at: 0.45) == 0)
        #expect(abs(both.fraction(at: 0.6) - 0.25) < 1e-6)
        #expect(both.fraction(at: 1.0) == 0, "the second pass's wait")
    }

    @Test("A speed scales a delay inside it, and a delay outside it repeats unscaled (p11)")
    func speedAndPassDelay() {
        // delay, then speed, then repeat: a 0.15 s wait and a 0.2 s pass.
        let inside = Animation.linear(duration: 0.4).delay(0.3).speed(2).repeatCount(2, autoreverses: false)
        #expect(abs(inside.totalDuration! - 0.7) < 1e-6)
        #expect(abs(inside.fraction(at: 0.25) - 0.5) < 1e-6)
        #expect(inside.fraction(at: 0.4) == 0)
        // speed, then delay, then repeat: a 0.3 s wait and a 0.2 s pass.
        let outside = Animation.linear(duration: 0.4).speed(2).delay(0.3).repeatCount(2, autoreverses: false)
        #expect(abs(outside.totalDuration! - 1.0) < 1e-6)
        #expect(abs(outside.fraction(at: 0.4) - 0.5) < 1e-6)
        #expect(outside.fraction(at: 0.75) == 0)
        #expect(abs(outside.fraction(at: 0.9) - 0.5) < 1e-6)
    }

    @Test("One pass keeps its delay leading, and moves as the animation unrepeated")
    func singlePassKeepsLead() {
        let delayed = Animation.linear(duration: 0.4).delay(0.3)
        let once = delayed.repeatCount(1)
        #expect(once.effectiveDelay == 0.3)
        for time in [0.2, 0.4, 0.6, 0.8] {
            #expect(once.fraction(at: time) == delayed.fraction(at: time))
        }
    }

    @Test("Speeds compose by multiplying")
    func speedsCompose() {
        #expect(Animation.linear(duration: 1).speed(2).speed(3).effectivePassDuration == 1.0 / 6)
    }

    @Test("An autoreversing repeat counts one-way passes")
    func repeatCountsPasses() {
        let animation = Animation.linear(duration: 1).repeatCount(2, autoreverses: true)
        #expect(animation.totalDuration == 2)
        #expect(abs(animation.fraction(at: 0.5) - 0.5) < 1e-6)  // out
        #expect(abs(animation.fraction(at: 1.0) - 1.0) < 1e-6)  // turn
        #expect(abs(animation.fraction(at: 1.5) - 0.5) < 1e-6)  // back
        // Two passes out-and-back land back at the start, and STAY there.
        #expect(animation.fraction(at: 2.0) == 0)
        #expect(animation.fraction(at: 99) == 0)
    }

    @Test("An odd autoreversing repeat ends on the target")
    func oddRepeatEndsAtTheTarget() {
        let animation = Animation.linear(duration: 1).repeatCount(3, autoreverses: true)
        #expect(animation.fraction(at: 3) == 1)
        #expect(animation.fraction(at: 99) == 1)
    }

    @Test("Without autoreverse a repeat snaps back and runs again")
    func repeatWithoutAutoreverse() {
        let animation = Animation.linear(duration: 1).repeatCount(3, autoreverses: false)
        #expect(abs(animation.fraction(at: 0.5) - 0.5) < 1e-6)
        #expect(abs(animation.fraction(at: 1.5) - 0.5) < 1e-6)
        #expect(animation.fraction(at: 3) == 1)
    }

    @Test("A reversed pass runs the curve backwards in time")
    func reversalIsInTime() {
        // Not a mirror of the output: `curve(1 − t)`, not `1 − curve(t)`. For an
        // asymmetric curve those differ, and time reversal is what "plays in
        // reverse" means.
        let easeOut = Animation.easeOut(duration: 1)
        let repeated = easeOut.repeatCount(2, autoreverses: true)
        for step in 1...9 {
            let t = Double(step) / 10
            #expect(abs(repeated.fraction(at: 1 + t) - easeOut.fraction(at: 1 - t)) < 1e-6)
        }
    }

    @Test("A forever animation never finishes and has a cycle")
    func foreverHasAPeriod() {
        let out = Animation.linear(duration: 0.4).repeatForever(autoreverses: false)
        #expect(out.repeatsForever)
        #expect(out.totalDuration == nil)
        #expect(out.cyclePeriod == 0.4)
        #expect(!out.isFinished(at: 1_000_000))

        let there = Animation.linear(duration: 0.4).repeatForever(autoreverses: true)
        #expect(there.cyclePeriod == 0.8)
        // And it really is periodic — the whole basis for pre-rendering it.
        for step in 0...16 {
            let t = Double(step) / 20
            #expect(abs(there.fraction(at: t) - there.fraction(at: t + 0.8)) < 1e-9, "at \(t)")
        }
    }

    @Test("A finishing animation has no cycle to pre-render")
    func finiteAnimationsHaveNoPeriod() {
        #expect(Animation.easeInOut.cyclePeriod == nil)
        #expect(Animation.linear(duration: 1).repeatCount(9).cyclePeriod == nil)
        #expect(Animation.easeInOut.isFinished(at: Animation.defaultDuration))
        #expect(!Animation.easeInOut.isFinished(at: Animation.defaultDuration - 0.001))
    }

    @Test("A zero-duration animation is instant, not divided by zero")
    func zeroDurationIsInstant() {
        let animation = Animation.linear(duration: 0)
        #expect(animation.fraction(at: 0) == 0)
        #expect(animation.fraction(at: 0.001) == 1)
        #expect(animation.totalDuration == 0)
    }

    @Test("Nonsense arguments are clamped rather than trapped")
    func degenerateArgumentsAreClamped() {
        // An animation is decoration: taking the app down because a duration
        // came out of a calculation as -1 is never the right answer.
        #expect(Animation.linear(duration: -1).totalDuration == 0)
        #expect(Animation.linear(duration: 1).speed(0).effectivePassDuration == 1)
        #expect(Animation.linear(duration: 1).speed(-2).effectivePassDuration == 1)
        #expect(Animation.linear(duration: 1).delay(-5).effectiveDelay == 0)
        #expect(Animation.linear(duration: 1).repeatCount(0).totalDuration == 1)
        #expect(Animation.spring(duration: 0.5, bounce: 9).totalDuration != nil)
        #expect(Animation.spring(duration: 0, bounce: 0).fraction(at: 1) == 1)
    }

    @Test("Animations compare and hash by what they describe")
    func equatableAndHashable() {
        #expect(Animation.easeInOut == Animation.easeInOut(duration: Animation.defaultDuration))
        #expect(Animation.easeInOut != Animation.easeIn)
        #expect(Animation.linear(duration: 1) != Animation.linear(duration: 2))
        #expect(Animation.linear.delay(1) != Animation.linear)
        #expect(
            Set([Animation.easeInOut, .easeInOut, .linear]).count == 2,
            "equal animations must hash together")
    }
}
