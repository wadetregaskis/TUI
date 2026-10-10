//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SpringTests.swift
//
//  Every expected number here was printed by SwiftUI's own `Spring` (macOS 26.2
//  SDK, `w12/probe/p4.swift` and `p5.swift`), to six places.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// Whether `value` is SwiftUI's printed `expected`, to its six places.
private func near(_ value: Double, _ expected: Double, within tolerance: Double = 2e-6) -> Bool {
    abs(value - expected) <= tolerance
}

private let times: [Double] = [0, 0.05, 0.1, 0.25, 0.5, 1.0]

@MainActor
@Suite("Spring")
struct SpringTests {

    @Test("Duration and bounce convert to mass, stiffness and damping as SwiftUI's do")
    func parameters() {
        let bouncy = Spring(duration: 0.5, bounce: 0.3)
        #expect(bouncy.mass == 1)
        #expect(near(bouncy.stiffness, 157.91367))
        #expect(near(bouncy.damping, 17.592919))
        #expect(near(bouncy.dampingRatio, 0.7))
        #expect(bouncy.response == 0.5 && bouncy.duration == 0.5)
        #expect(near(bouncy.bounce, 0.3))

        let physical = Spring(mass: 1, stiffness: 100, damping: 10)
        #expect(near(physical.response, 0.628319))
        #expect(near(physical.bounce, 0.5))
        #expect(near(physical.dampingRatio, 0.5))

        let clamped = Spring(mass: 2, stiffness: 100, damping: 40)
        #expect(near(clamped.dampingRatio, 1), "overdamping is not allowed by default")
        #expect(near(clamped.damping, 28.284271))

        let overdamped = Spring(mass: 2, stiffness: 100, damping: 40, allowOverDamping: true)
        #expect(near(overdamped.dampingRatio, 1.414214))
        #expect(near(overdamped.bounce, -0.292893))
        #expect(near(overdamped.stiffness, 300), "SwiftUI reports (2ζ² − 1)× the stiffness it moves with")

        #expect(near(Spring(duration: 1, bounce: -0.5).stiffness, 276.348923))
        #expect(Spring(duration: 0.5, bounce: 1.5).dampingRatio == 0, "bounce is clamped at 1")
    }

    @Test("The presets are SwiftUI's")
    func presets() {
        #expect(Spring.smooth == Spring(duration: 0.5, bounce: 0))
        #expect(Spring.snappy == Spring(duration: 0.5, bounce: 0.15))
        #expect(Spring.bouncy == Spring(duration: 0.5, bounce: 0.3))
        #expect(near(Spring.bouncy(duration: 1, extraBounce: 0.1).bounce, 0.4))
        #expect(near(Spring.snappy(duration: 1, extraBounce: 0.1).bounce, 0.25))
        #expect(near(Spring.smooth(duration: 1, extraBounce: 0.1).bounce, 0.1))
    }

    @Test("Value and velocity over time, in all three regimes, with and without a starting velocity")
    func motion() {
        let cases: [(Spring, [Double], [Double], [Double])] = [
            (Spring(),  // critically damped
             [0.0, 0.131311, 0.35774, 0.821026, 0.986399, 0.999953],
             [0.0, 0.18466, 0.414661, 0.842633, 0.988267, 0.99996],
             [0.0, 4.212253, 4.494374, 1.706017, 0.147447, 0.000551]),
            (Spring(duration: 0.5, bounce: 0.3),  // underdamped
             [0.0, 0.145715, 0.423302, 0.984087, 1.014498, 1.000072],
             [0.0, 0.20799, 0.495589, 1.003418, 1.011827, 1.000086],
             [0.0, 4.917049, 5.707558, 1.526265, -0.210951, 0.001159]),
            (Spring(duration: 1, bounce: -0.5),  // overdamped
             [0.0, 0.033576, 0.096998, 0.292983, 0.535728, 0.799926],
             [0.0, 0.089596, 0.16584, 0.353042, 0.575325, 0.816991],
             [1.0, 2.105805, 2.358892, 2.185527, 1.781623, 1.336839]),
        ]
        for (spring, values, pushed, velocities) in cases {
            for (index, time) in times.enumerated() {
                #expect(near(spring.value(target: 1.0, time: time), values[index]), "\(spring) at \(time)")
                #expect(near(spring.value(target: 1.0, initialVelocity: 2.0, time: time), pushed[index]))
                // SwiftUI's overdamped velocity reads exactly one more than
                // the derivative of its own value — 1 at rest at t = 0 —
                // where this answers the derivative.
                let offset = spring.dampingRatio > 1 ? 1.0 : 0.0
                #expect(near(spring.velocity(target: 1.0, time: time), velocities[index] - offset, within: 1e-5))
            }
        }
        let pair = Spring(duration: 0.5, bounce: 0.3).value(
            target: AnimatablePair(1.0, 2.0), initialVelocity: AnimatablePair(0.5, -1.0), time: 0.1)
        #expect(near(pair.first, 0.441374) && near(pair.second, 0.810461))
    }

    @Test("Force, update and the from-to forms")
    func forceAndUpdate() {
        let spring = Spring()
        #expect(near(spring.force(target: 1.0, position: 0.25, velocity: 0.5), 105.868882))
        #expect(near(Spring(mass: 2, stiffness: 100, damping: 40, allowOverDamping: true)
            .force(target: 1.0, position: 0.25, velocity: 0.5), 205))
        var value = 0.0
        var velocity = 0.0
        spring.update(value: &value, velocity: &velocity, target: 1.0, deltaTime: 0.1)
        #expect(near(value, 0.35774) && near(velocity, 4.494374))
        spring.update(value: &value, velocity: &velocity, target: 1.0, deltaTime: 0.1)
        #expect(near(value, 0.715416) && near(velocity, 2.558283))
        #expect(near(spring.value(fromValue: 2.0, toValue: 5.0, initialVelocity: 0.0, time: 0.1), 3.073219))
        let bouncy = Spring(duration: 0.5, bounce: 0.3)
        #expect(near(bouncy.force(fromValue: 1.0, toValue: 3.0, position: 1.5, velocity: 0.5), 70.160376))
        #expect(near(bouncy.velocity(fromValue: 1.0, toValue: 3.0, initialVelocity: 0.5, time: 0.1), 11.38553))
    }

    @Test("Settling durations: a bound for an underdamped spring, tenths of a second for the rest")
    func settling() {
        #expect(near(Spring().settlingDuration, 0.8))
        #expect(near(Spring(duration: 0.5, bounce: 0.3).settlingDuration, 1.044713))
        let bouncy = Spring(duration: 0.5, bounce: 0.3)
        #expect(near(bouncy.settlingDuration(target: 1.0, epsilon: 0.01), 0.78295))
        #expect(near(bouncy.settlingDuration(target: 1.0, initialVelocity: 5.0, epsilon: 0.001), 0.963528))
        #expect(near(bouncy.settlingDuration(target: 1.0, initialVelocity: 20.0, epsilon: 0.001), 1.06969))
        #expect(near(bouncy.settlingDuration(target: AnimatablePair(3.0, 4.0), epsilon: 0.001), 1.227677))
        #expect(near(Spring().settlingDuration(target: 5.0, epsilon: 0.001), 0.9))
        #expect(near(Spring().settlingDuration(target: 1.0, initialVelocity: 5.0, epsilon: 0.001), 0.7))
        #expect(near(Spring(duration: 1, bounce: -0.5).settlingDuration, 4.2))
        #expect(Spring().settlingDuration(target: 0.0, epsilon: 0.001) == 0)
        #expect(Spring(mass: 1, stiffness: 100, damping: 0).settlingDuration == .infinity)
        #expect(near(bouncy.settlingDuration(fromValue: 1.0, toValue: 3.0, initialVelocity: 0.5, epsilon: 0.001), 1.120573))
    }

    @Test("A spring made from a settling duration is solved as SwiftUI solves it")
    func fromSettlingDuration() {
        #expect(near(Spring(settlingDuration: 1, dampingRatio: 0.8).response, 0.698574))
        #expect(near(Spring(settlingDuration: 1, dampingRatio: 0.8, epsilon: 0.01).response, 1.027325))
        #expect(near(Spring(settlingDuration: 1, dampingRatio: 0.1).response, 0.136289))
        #expect(near(Spring(settlingDuration: 0.5, dampingRatio: 1).response, 0.340242))
        let capped = Spring(settlingDuration: 2, dampingRatio: 2)
        #expect(near(capped.response, 1.360967) && capped.dampingRatio == 1, "a ratio above 1 is treated as 1")
    }

    // MARK: - As an animation

    @Test("A spring animation moves as its Spring does")
    func animationFollowsTheSpring() {
        let spring = Spring(duration: 0.5, bounce: 0.3)
        let animation = Animation.spring(spring)
        #expect(animation == .spring(duration: 0.5, bounce: 0.3))
        #expect(animation == .bouncy)
        for time in [0.05, 0.1, 0.25, 0.5] {
            #expect(abs(animation.fraction(at: time) - spring.value(target: 1.0, time: time)) < 1e-12)
        }
        #expect(Animation.spring(response: 0.3, dampingFraction: 0.6) == .spring(Spring(response: 0.3, dampingRatio: 0.6)))
        #expect(Animation.spring() == .spring(duration: 0.5, bounce: 0), "the response form is disfavoured")
    }

    @Test("An interpolating spring starts at its initial velocity and settles later for it")
    func interpolatingSpring() {
        let spring = Spring(duration: 0.5, bounce: 0.3)
        let pushed = Animation.interpolatingSpring(spring, initialVelocity: 2)
        for time in [0.05, 0.1, 0.25] {
            #expect(abs(pushed.fraction(at: time) - spring.value(target: 1.0, initialVelocity: 2.0, time: time)) < 1e-12)
        }
        #expect(pushed.description == "interpolatingSpring(duration: 0.5, bounce: 0.3, initialVelocity: 2.0)")
        #expect(Animation.interpolatingSpring == .interpolatingSpring(Spring()))
        #expect(Animation.interpolatingSpring(mass: 1, stiffness: 100, damping: 10) == .interpolatingSpring(
            Spring(mass: 1, stiffness: 100, damping: 10)))
        #expect(Animation.interactiveSpring == .spring(duration: 0.15, bounce: 0.15))
        #expect(Animation.interactiveSpring(response: 0.2, dampingFraction: 0.8) == .spring(
            Spring(response: 0.2, dampingRatio: 0.8)))
        // Pushed hard past the target, it settles later than from rest, and it
        // does settle: the envelope includes the velocity.
        let rest = Animation.interpolatingSpring(Spring(duration: 0.5, bounce: 0), initialVelocity: 0)
        let hard = Animation.interpolatingSpring(Spring(duration: 0.5, bounce: 0), initialVelocity: 30)
        #expect(hard.effectivePassDuration > rest.effectivePassDuration)
        #expect(abs(hard.fraction(at: hard.effectivePassDuration * 0.999) - 1) < 0.005)
    }
}
