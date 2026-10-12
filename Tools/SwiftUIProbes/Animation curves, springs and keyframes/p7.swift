import SwiftUI

func r(_ x: Double) -> Double { (x * 1e6).rounded() / 1e6 }

@main
struct Probe {
    static func main() {
        for delta in [0.01, 1.0, 100.0] {
            let t = KeyframeTimeline(initialValue: 0.0) { SpringKeyframe(delta) }
            print("spring delta", delta, "duration", t.duration)
            let b = KeyframeTimeline(initialValue: 0.0) { SpringKeyframe(delta, spring: .bouncy) }
            print("bouncy delta", delta, "duration", r(b.duration))
        }
        let v = KeyframeTimeline(initialValue: 0.0) { SpringKeyframe(1.0, startVelocity: 5.0) }
        print("v0=5 duration", v.duration)
        // cubic followed by linear / spring / move, cubic after move
        let a = KeyframeTimeline(initialValue: 0.0) {
            CubicKeyframe(1.0, duration: 1)
            SpringKeyframe(0.0, duration: 1, spring: .smooth)
        }
        print("cubic-spring", [0.25, 0.5, 0.75, 1.0, 1.25].map { r(a.value(time: $0)) })
        let b2 = KeyframeTimeline(initialValue: 0.0) {
            CubicKeyframe(1.0, duration: 1)
            MoveKeyframe(3.0)
            CubicKeyframe(0.0, duration: 1)
        }
        print("cubic-move-cubic", b2.duration, [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75].map { r(b2.value(time: $0)) })
        let c = KeyframeTimeline(initialValue: 0.0) {
            CubicKeyframe(1.0, duration: 1)
            CubicKeyframe(0.0, duration: 1, startVelocity: 3)
        }
        print("cubic-cubic(sv)", [0.25, 0.5, 0.75, 1.25, 1.5].map { r(c.value(time: $0)) })
        let d = KeyframeTimeline(initialValue: 0.0) {
            CubicKeyframe(1.0, duration: 1, endVelocity: -2)
            CubicKeyframe(0.0, duration: 1)
        }
        print("cubic(ev)-cubic", [0.25, 0.5, 0.75, 1.25, 1.5].map { r(d.value(time: $0)) })
        let e = KeyframeTimeline(initialValue: 0.0) {
            LinearKeyframe(1.0, duration: 1, timingCurve: .easeIn)
            CubicKeyframe(0.0, duration: 1)
        }
        print("easeIn-cubic", [1.25, 1.5, 1.75].map { r(e.value(time: $0)) })
        let f = KeyframeTimeline(initialValue: 0.0) {
            CubicKeyframe(1.0, duration: 0)
            LinearKeyframe(0.0, duration: 1)
        }
        print("zero-dur", f.duration, [0.0, 0.5, 1.0].map { r(f.value(time: $0)) })
        let cs = KeyframeTimeline(initialValue: 0.0) {
            SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
            CubicKeyframe(0.0, duration: 1)
        }
        print("cubic-after-spring", [0.4, 0.5, 0.8, 1.0, 1.2].map { r(cs.value(time: $0)) })
        print("spring vel at 0.3", r(Spring.bouncy.velocity(target: 1.0, time: 0.3)), r(Spring.bouncy.value(target: 1.0, time: 0.3)))
    }
}
