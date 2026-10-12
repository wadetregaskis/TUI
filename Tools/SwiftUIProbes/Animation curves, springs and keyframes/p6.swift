import SwiftUI

func r(_ x: Double) -> Double { (x * 1e6).rounded() / 1e6 }

struct Values {
    var a = 0.0
    var b = 10.0
}

@main
struct Probe {
    static func main() {
        let times: [Double] = [-0.5, 0, 0.1, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]
        func show(_ name: String, _ t: KeyframeTimeline<Double>) {
            print(name, "duration", r(t.duration), times.map { r(t.value(time: $0)) })
            print(name, "progress", [-0.5, 0, 0.5, 1, 1.5].map { r(t.value(progress: $0)) })
        }
        show("linear", KeyframeTimeline(initialValue: 0.0) {
            LinearKeyframe(1.0, duration: 1)
            LinearKeyframe(0.5, duration: 1)
        })
        show("linear-easeIn", KeyframeTimeline(initialValue: 0.0) {
            LinearKeyframe(1.0, duration: 1, timingCurve: .easeIn)
        })
        show("cubic2", KeyframeTimeline(initialValue: 0.0) {
            CubicKeyframe(1.0, duration: 1)
            CubicKeyframe(0.5, duration: 1)
        })
        show("cubic3", KeyframeTimeline(initialValue: 0.0) {
            CubicKeyframe(1.0, duration: 0.5)
            CubicKeyframe(0.0, duration: 1)
            CubicKeyframe(2.0, duration: 0.5)
        })
        show("cubic1", KeyframeTimeline(initialValue: 0.0) {
            CubicKeyframe(1.0, duration: 1)
        })
        show("cubic-vel", KeyframeTimeline(initialValue: 0.0) {
            CubicKeyframe(1.0, duration: 1, startVelocity: 2, endVelocity: -1)
        })
        show("lin-cubic-lin", KeyframeTimeline(initialValue: 0.0) {
            LinearKeyframe(1.0, duration: 1)
            CubicKeyframe(0.0, duration: 1)
            LinearKeyframe(1.0, duration: 1)
        })
        show("move", KeyframeTimeline(initialValue: 0.0) {
            LinearKeyframe(1.0, duration: 1)
            MoveKeyframe(5.0)
            LinearKeyframe(0.0, duration: 1)
        })
        show("spring", KeyframeTimeline(initialValue: 0.0) {
            SpringKeyframe(1.0, duration: 1, spring: Spring(duration: 0.5, bounce: 0.3))
            SpringKeyframe(0.0, spring: .smooth)
        })
        show("spring-nil", KeyframeTimeline(initialValue: 0.0) {
            SpringKeyframe(1.0)
        })
        show("spring-short", KeyframeTimeline(initialValue: 0.0) {
            SpringKeyframe(1.0, duration: 0.2)
            LinearKeyframe(0.0, duration: 1)
        })
        show("spring-vel", KeyframeTimeline(initialValue: 0.0) {
            LinearKeyframe(1.0, duration: 1)
            SpringKeyframe(0.0, duration: 1, spring: .bouncy)
        })
        show("cubic-after-spring", KeyframeTimeline(initialValue: 0.0) {
            SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
            CubicKeyframe(0.0, duration: 1)
        })
        show("empty", KeyframeTimeline(initialValue: 3.0) {
        })
        let multi = KeyframeTimeline(initialValue: Values()) {
            KeyframeTrack(\.a) {
                LinearKeyframe(1.0, duration: 1)
            }
            KeyframeTrack(\.b) {
                LinearKeyframe(20.0, duration: 2)
            }
            KeyframeTrack(\.a) {
                LinearKeyframe(-1.0, duration: 0.5)
            }
        }
        print("multi duration", multi.duration, [0, 0.25, 0.5, 1, 2].map { (r(multi.value(time: $0).a), r(multi.value(time: $0).b)) })
        let point = KeyframeTimeline(initialValue: CGPoint(x: 0, y: 0)) {
            CubicKeyframe(CGPoint(x: 1, y: 2), duration: 1)
            CubicKeyframe(CGPoint(x: 0, y: 4), duration: 1)
        }
        print("pair", [0.5, 1.0, 1.5].map { (r(point.value(time: $0).x), r(point.value(time: $0).y)) })
        let cond = true
        let conditional = KeyframeTimeline(initialValue: 0.0) {
            if cond {
                LinearKeyframe(1.0, duration: 1)
            } else {
                LinearKeyframe(2.0, duration: 2)
            }
            for i in 0..<2 {
                LinearKeyframe(Double(i), duration: 0.5)
            }
        }
        print("cond", conditional.duration, [0.5, 1.0, 1.25, 1.5, 2.0].map { r(conditional.value(time: $0)) })
    }
}
