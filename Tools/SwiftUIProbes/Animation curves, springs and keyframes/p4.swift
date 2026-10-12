import SwiftUI

func r(_ x: Double) -> Double { (x * 1e6).rounded() / 1e6 }

func dump(_ name: String, _ s: Spring) {
    print(name, "mass", r(s.mass), "stiffness", r(s.stiffness), "damping", r(s.damping), "dampingRatio", r(s.dampingRatio),
          "response", r(s.response), "duration", r(s.duration), "bounce", r(s.bounce), "settling", r(s.settlingDuration))
    let ts: [Double] = [0, 0.05, 0.1, 0.25, 0.5, 1.0]
    print(name, "value", ts.map { r(s.value(target: 1.0, time: $0)) })
    print(name, "value v0=2", ts.map { r(s.value(target: 1.0, initialVelocity: 2.0, time: $0)) })
    print(name, "velocity", ts.map { r(s.velocity(target: 1.0, time: $0)) })
    print(name, "velocity v0=2", ts.map { r(s.velocity(target: 1.0, initialVelocity: 2.0, time: $0)) })
    print(name, "force", r(s.force(target: 1.0, position: 0.25, velocity: 0.5)))
    print(name, "settle eps 0.01", r(s.settlingDuration(target: 1.0, epsilon: 0.01)), "eps 0.001", r(s.settlingDuration(target: 1.0, epsilon: 0.001)),
          "v0=5", r(s.settlingDuration(target: 1.0, initialVelocity: 5.0, epsilon: 0.001)))
    var value = 0.0
    var velocity = 0.0
    s.update(value: &value, velocity: &velocity, target: 1.0, deltaTime: 0.1)
    print(name, "update 0.1", r(value), r(velocity))
    s.update(value: &value, velocity: &velocity, target: 1.0, deltaTime: 0.1)
    print(name, "update 0.2", r(value), r(velocity))
    print(name, "fromValue", r(s.value(fromValue: 2.0, toValue: 5.0, initialVelocity: 0.0, time: 0.1)))
}

@main
struct Probe {
    static func main() {
        dump("default", Spring())
        dump("d0.5b0.3", Spring(duration: 0.5, bounce: 0.3))
        dump("d1b-0.5", Spring(duration: 1, bounce: -0.5))
        dump("msd", Spring(mass: 1, stiffness: 100, damping: 10))
        dump("msd-over", Spring(mass: 2, stiffness: 100, damping: 40))
        dump("msd-over-allowed", Spring(mass: 2, stiffness: 100, damping: 40, allowOverDamping: true))
        dump("response", Spring(response: 0.3, dampingRatio: 0.5))
        dump("settling", Spring(settlingDuration: 1, dampingRatio: 0.8))
        dump("settling-eps", Spring(settlingDuration: 1, dampingRatio: 0.8, epsilon: 0.01))
        dump("bouncy", .bouncy)
        dump("smooth", .smooth)
        dump("snappy", .snappy)
        dump("bouncy(1,0.1)", .bouncy(duration: 1, extraBounce: 0.1))
        dump("snappy(1,0.1)", .snappy(duration: 1, extraBounce: 0.1))
        dump("smooth(1,0.1)", .smooth(duration: 1, extraBounce: 0.1))
        dump("critical", Spring(duration: 0.5, bounce: 0))
        print(Animation.spring(Spring(duration: 0.5, bounce: 0.3)).description)
        print(Animation.spring(Spring(duration: 0.5, bounce: 0.3), blendDuration: 0.2).description)
        print(Animation.interpolatingSpring.description)
        print(Animation.interpolatingSpring(Spring(duration: 0.5, bounce: 0.3), initialVelocity: 2).description)
        print(Animation.interpolatingSpring(mass: 1, stiffness: 100, damping: 10, initialVelocity: 0).description)
        print(Animation.interpolatingSpring(duration: 0.5, bounce: 0.2, initialVelocity: 0).description)
        print(Animation.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0).description)
        print(Animation.spring(duration: 0.4, bounce: 0.2, blendDuration: 0.1).description)
        print(Animation.interactiveSpring.description)
        print(Animation.interactiveSpring(response: 0.2, dampingFraction: 0.8, blendDuration: 0.1).description)
        print(Animation.interactiveSpring(duration: 0.2, extraBounce: 0.1, blendDuration: 0.1).description)
        print(Animation.spring.description)
        print(Animation.spring(response: 0.55).description)
    }
}
