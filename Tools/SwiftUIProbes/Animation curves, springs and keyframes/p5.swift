import SwiftUI

func r(_ x: Double) -> Double { (x * 1e6).rounded() / 1e6 }

@main
struct Probe {
    static func main() {
        for zeta in [0.1, 0.3, 0.5, 0.8, 0.95, 1.0, 1.5, 2.0] {
            for t in [0.5, 1.0, 2.0] {
                let s = Spring(settlingDuration: t, dampingRatio: zeta)
                print("settle", t, "zeta", zeta, "-> response", r(s.response), "zeta", r(s.dampingRatio), "settling", r(s.settlingDuration))
            }
        }
        // bounce extremes
        for b in [-1.0, -0.99, -0.5, 0.0, 0.5, 0.99, 1.0, 1.5, -1.5] {
            let s = Spring(duration: 0.5, bounce: b)
            print("bounce", b, "-> zeta", r(s.dampingRatio), "bounce", r(s.bounce), "stiffness", r(s.stiffness))
        }
        // vector targets
        let s = Spring(duration: 0.5, bounce: 0.3)
        let v = s.value(target: AnimatablePair(1.0, 2.0), initialVelocity: AnimatablePair(0.5, -1.0), time: 0.1)
        print("pair", r(v.first), r(v.second))
        print("pair settle", r(s.settlingDuration(target: AnimatablePair(3.0, 4.0), initialVelocity: AnimatablePair(0.0, 0.0), epsilon: 0.001)))
        print("scaled settle", r(s.settlingDuration(target: 5.0, epsilon: 0.001)))
        let crit = Spring(duration: 0.5, bounce: 0)
        print("crit scaled settle", r(crit.settlingDuration(target: 5.0, epsilon: 0.001)))
        print("crit neg target", r(crit.settlingDuration(target: -5.0, epsilon: 0.001)))
        print("zero target", r(s.settlingDuration(target: 0.0, epsilon: 0.001)), r(crit.settlingDuration(target: 0.0, epsilon: 0.001)))
        print("force fromValue", r(s.force(fromValue: 1.0, toValue: 3.0, position: 1.5, velocity: 0.5)))
        print("velocity fromValue", r(s.velocity(fromValue: 1.0, toValue: 3.0, initialVelocity: 0.5, time: 0.1)))
        print("settle fromValue", r(s.settlingDuration(fromValue: 1.0, toValue: 3.0, initialVelocity: 0.5, epsilon: 0.001)))
        // underdamped with large v0 opposite
        print("v0 big", r(s.settlingDuration(target: 1.0, initialVelocity: 20.0, epsilon: 0.001)))
        print("msd zeta0", Spring(mass: 1, stiffness: 100, damping: 0).settlingDuration, Spring(mass: 1, stiffness: 100, damping: 0).dampingRatio)
        print("dur0", Spring(duration: 0, bounce: 0).stiffness)
        // interpolatingSpring: is it the same curve? sample via spring value
        print(Spring(response: 0.5, dampingRatio: 0.825) == Spring(duration: 0.5, bounce: 0.175))
        print(Spring(mass: 1, stiffness: 157.91367041742973, damping: 25.132741228718345) == Spring())
    }
}
