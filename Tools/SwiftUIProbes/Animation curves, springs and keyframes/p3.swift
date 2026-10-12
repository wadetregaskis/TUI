import SwiftUI

@main
struct Probe {
    static func main() {
        let curves: [(String, UnitCurve)] = [
            ("linear", .linear), ("easeIn", .easeIn), ("easeOut", .easeOut), ("easeInOut", .easeInOut),
            ("circularEaseIn", .circularEaseIn), ("circularEaseOut", .circularEaseOut),
            ("circularEaseInOut", .circularEaseInOut),
            ("bezier", .bezier(startControlPoint: UnitPoint(x: 0.1, y: 0.75), endControlPoint: UnitPoint(x: 0.85, y: 0.35))),
            ("bezierClamp", .bezier(startControlPoint: UnitPoint(x: -0.5, y: 0.2), endControlPoint: UnitPoint(x: 1.5, y: 0.8))),
        ]
        let xs: [Double] = [-0.5, 0, 0.1, 0.25, 0.5, 0.75, 0.9, 1, 1.5]
        for (name, curve) in curves {
            print(name, "value", xs.map { (curve.value(at: $0) * 1e6).rounded() / 1e6 })
            print(name, "velocity", xs.map { (curve.velocity(at: $0) * 1e6).rounded() / 1e6 })
            print(name, "inverse", xs.map { (curve.inverse.value(at: $0) * 1e6).rounded() / 1e6 })
            print(name, "inverse.inverse==", curve.inverse.inverse == curve)
        }
        print("easeInEaseOut == easeInOut", UnitCurve.easeInEaseOut == UnitCurve.easeInOut)
        print("circularEaseIn.inverse == circularEaseOut", UnitCurve.circularEaseIn.inverse == UnitCurve.circularEaseOut)
        print("linear.inverse == linear", UnitCurve.linear.inverse == UnitCurve.linear)
        print("bezier(0.42,0,1,1) == easeIn", UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.42, y: 0), endControlPoint: UnitPoint(x: 1, y: 1)) == UnitCurve.easeIn)
        print("bezier linear == linear", UnitCurve.bezier(startControlPoint: UnitPoint(x: 0, y: 0), endControlPoint: UnitPoint(x: 1, y: 1)) == UnitCurve.linear)
        print(Animation.timingCurve(.easeIn, duration: 1).description)
        print(Animation.timingCurve(.circularEaseIn, duration: 1).description)
        print(String(describing: UnitCurve.easeIn))
    }
}
