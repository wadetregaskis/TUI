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
            TimelineView(.periodic(from: anchor, by: value)) { context in Text("\(context.date)") }
        }
        let start = Date(timeIntervalSinceReferenceDate: value.isFinite ? value : 0)
        drawHostile(nows: Self.frameNows) { _ in
            TimelineView(.periodic(from: start, by: 1)) { context in Text("\(context.date)") }
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
}
