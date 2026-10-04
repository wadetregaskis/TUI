//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KeyframeTimelineTests.swift
//
//  Every expected value was printed by SwiftUI's own KeyframeTimeline (macOS
//  26.2 SDK, `w12/probe/p6.swift` and `p7.swift`) to six places.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

private struct Values {
    var a = 0.0
    var b = 10.0
}

private let times: [Double] = [0, 0.1, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

/// Whether `timeline` passes through SwiftUI's values at `times`.
@MainActor
private func follows(_ timeline: KeyframeTimeline<Double>, _ expected: [Double]) -> Bool {
    let actual = times.map(timeline.value(time:))
    let matches = zip(actual, expected).allSatisfy { abs($0 - $1) <= 2e-6 }
    if !matches { Issue.record("\(actual) is not \(expected)") }
    return matches
}

@MainActor
@Suite("Keyframe timelines")
struct KeyframeTimelineTests {

    @Test("Linear keyframes, with and without a timing curve")
    func linear() {
        let timeline = KeyframeTimeline(initialValue: 0.0) {
            LinearKeyframe(1.0, duration: 1)
            LinearKeyframe(0.5, duration: 1)
        }
        #expect(timeline.duration == 2)
        #expect(follows(timeline, [0.0, 0.1, 0.25, 0.5, 0.75, 1.0, 0.875, 0.75, 0.625, 0.5, 0.5, 0.5]))
        #expect(timeline.value(time: -0.5) == 0, "before the start is the start")
        #expect(timeline.value(progress: 0.5) == 1)
        let eased = KeyframeTimeline(initialValue: 0.0) {
            LinearKeyframe(1.0, duration: 1, timingCurve: .easeIn)
        }
        #expect(follows(eased, [0.0, 0.017027, 0.093465, 0.315357, 0.621861, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]))
    }

    @Test("Adjacent cubic keyframes form a Catmull-Rom spline, at rest at both ends")
    func cubicSpline() {
        #expect(follows(KeyframeTimeline(initialValue: 0.0) {
            CubicKeyframe(1.0, duration: 1)
            CubicKeyframe(0.5, duration: 1)
        }, [0.0, 0.02575, 0.144531, 0.46875, 0.808594, 1.0, 0.957031, 0.78125, 0.589844, 0.5, 0.5, 0.5]))
        #expect(follows(KeyframeTimeline(initialValue: 0.0) {
            CubicKeyframe(1.0, duration: 0.5)
            CubicKeyframe(0.0, duration: 1)
            CubicKeyframe(2.0, duration: 0.5)
        }, [0.0, 0.104, 0.5, 1.0, 0.8125, 0.416667, 0.0625, 0.0, 1.041667, 2.0, 2.0, 2.0]))
        #expect(follows(KeyframeTimeline(initialValue: 0.0) {
            CubicKeyframe(1.0, duration: 1, startVelocity: 2, endVelocity: -1)
        }, [0.0, 0.199, 0.484375, 0.875, 1.078125, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]))
    }

    @Test("A cubic keyframe meets its neighbours' velocities, and a named one wins only on its own side")
    func cubicNeighbours() {
        #expect(follows(KeyframeTimeline(initialValue: 0.0) {
            LinearKeyframe(1.0, duration: 1)
            CubicKeyframe(0.0, duration: 1)
            LinearKeyframe(1.0, duration: 1)
        }, [0.0, 0.1, 0.25, 0.5, 0.75, 1.0, 0.9375, 0.5, 0.0625, 0.0, 0.5, 1.0]))
        let namedStart = KeyframeTimeline(initialValue: 0.0) {
            CubicKeyframe(1.0, duration: 1)
            CubicKeyframe(0.0, duration: 1, startVelocity: 3)
        }
        #expect([0.25, 0.5, 0.75, 1.25, 1.5].map(namedStart.value(time:)).enumerated().allSatisfy {
            abs($0.element - [0.015625, 0.125, 0.421875, 1.265625, 0.875][$0.offset]) < 2e-6
        })
        let namedEnd = KeyframeTimeline(initialValue: 0.0) {
            CubicKeyframe(1.0, duration: 1, endVelocity: -2)
            CubicKeyframe(0.0, duration: 1)
        }
        #expect([0.25, 0.5, 0.75, 1.25, 1.5].map(namedEnd.value(time:)).enumerated().allSatisfy {
            abs($0.element - [0.25, 0.75, 1.125, 0.84375, 0.5][$0.offset]) < 2e-6
        })
        let afterEaseIn = KeyframeTimeline(initialValue: 0.0) {
            LinearKeyframe(1.0, duration: 1, timingCurve: .easeIn)
            CubicKeyframe(0.0, duration: 1)
        }
        #expect(abs(afterEaseIn.value(time: 1.25) - 0.84375) < 2e-6)
    }

    @Test("A move jumps, and the next keyframe starts from where it landed, at rest")
    func move() {
        #expect(follows(KeyframeTimeline(initialValue: 0.0) {
            LinearKeyframe(1.0, duration: 1)
            MoveKeyframe(5.0)
            LinearKeyframe(0.0, duration: 1)
        }, [0.0, 0.1, 0.25, 0.5, 0.75, 1.0, 3.75, 2.5, 1.25, 0.0, 0.0, 0.0]))
        let cubics = KeyframeTimeline(initialValue: 0.0) {
            CubicKeyframe(1.0, duration: 1)
            MoveKeyframe(3.0)
            CubicKeyframe(0.0, duration: 1)
        }
        #expect(abs(cubics.value(time: 1.25) - 2.53125) < 2e-6)
    }

    @Test("Spring keyframes hand on the value and velocity they reached, and settle to 0.0001 without a duration")
    func springs() {
        #expect(follows(KeyframeTimeline(initialValue: 0.0) {
            SpringKeyframe(1.0, duration: 1, spring: Spring(duration: 0.5, bounce: 0.3))
            SpringKeyframe(0.0, spring: .smooth)
        }, [0.0, 0.423302, 0.984087, 1.014498, 0.998192, 1.000072, 0.179, 0.013603, 0.000841, 0.000047, 0.000047, 0.000047]))
        #expect(abs(KeyframeTimeline(initialValue: 0.0) { SpringKeyframe(1.0) }.duration - 1) < 1e-9)
        #expect(abs(KeyframeTimeline(initialValue: 0.0) { SpringKeyframe(0.01) }.duration - 0.6) < 1e-9)
        #expect(abs(KeyframeTimeline(initialValue: 0.0) { SpringKeyframe(100.0) }.duration - 1.4) < 1e-9)
        #expect(abs(KeyframeTimeline(initialValue: 0.0) { SpringKeyframe(1.0, spring: .bouncy) }.duration - 1.306476) < 2e-6)
        #expect(abs(KeyframeTimeline(initialValue: 0.0) { SpringKeyframe(1.0, startVelocity: 5.0) }.duration - 0.9) < 1e-9)
        let cutShort = KeyframeTimeline(initialValue: 0.0) {
            SpringKeyframe(1.0, duration: 0.2)
            LinearKeyframe(0.0, duration: 1)
        }
        #expect(abs(cutShort.value(time: 0.25) - 0.679645) < 2e-6)
        let afterLinear = KeyframeTimeline(initialValue: 0.0) {
            LinearKeyframe(1.0, duration: 1)
            SpringKeyframe(0.0, duration: 1, spring: .bouncy)
        }
        #expect(abs(afterLinear.value(time: 1.25) - 0.025578) < 2e-6)
        let cubicAfter = KeyframeTimeline(initialValue: 0.0) {
            SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
            CubicKeyframe(0.0, duration: 1)
        }
        #expect([0.4, 0.5, 0.8, 1.0, 1.2].map(cubicAfter.value(time:)).enumerated().allSatisfy {
            abs($0.element - [1.049208, 0.996292, 0.585218, 0.257728, 0.033864][$0.offset]) < 2e-6
        })
    }

    @Test("Tracks run together from the initial value, and the last one written wins")
    func tracks() {
        let timeline = KeyframeTimeline(initialValue: Values()) {
            KeyframeTrack(\.a) { LinearKeyframe(1.0, duration: 1) }
            KeyframeTrack(\.b) { LinearKeyframe(20.0, duration: 2) }
            KeyframeTrack(\.a) { LinearKeyframe(-1.0, duration: 0.5) }
        }
        #expect(timeline.duration == 2)
        let samples = [0, 0.25, 0.5, 1, 2].map { timeline.value(time: $0) }
        #expect(samples.map(\.a) == [0, -0.5, -1, -1, -1])
        #expect(samples.map(\.b) == [10, 11.25, 12.5, 15, 20])
    }

    @Test("Conditionals, loops and an empty block build as SwiftUI's do")
    func builders() {
        let condition = true
        let timeline = KeyframeTimeline(initialValue: 0.0) {
            if condition {
                LinearKeyframe(1.0, duration: 1)
            } else {
                LinearKeyframe(2.0, duration: 2)
            }
            for value in 0..<2 {
                LinearKeyframe(Double(value), duration: 0.5)
            }
        }
        #expect(timeline.duration == 2)
        #expect([0.5, 1.0, 1.25, 1.5, 2.0].map(timeline.value(time:)) == [0.5, 1.0, 0.5, 0.0, 1.0])
        let empty = KeyframeTimeline(initialValue: 3.0) {}
        #expect(empty.duration == 0 && empty.value(time: 1) == 3)
    }

    @Test("Keyframes of the app's own are their body")
    func customKeyframes() {
        struct Bounce: Keyframes {
            var body: some Keyframes<Double> {
                KeyframeTrack {
                    LinearKeyframe(2.0, duration: 1)
                    MoveKeyframe(0.0)
                }
            }
        }
        let timeline = KeyframeTimeline(initialValue: 0.0) { Bounce() }
        #expect(timeline.value(time: 0.5) == 1)
        #expect(timeline.value(time: 2) == 0)
    }
}
