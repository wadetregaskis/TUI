//  🖥️ TUIkit — Terminal UI Kit for Swift
//  UnitCurveTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// Whether `values` match SwiftUI's, which the probe printed to six places.
/// Within 1e-5 rather than equal: both solve a Bézier's `x(t) = x` to a
/// tolerance, and the two tolerances differ in the sixth place.
private func matches(_ values: [Double], _ swiftUI: [Double]) -> Bool {
    values.count == swiftUI.count && zip(values, swiftUI).allSatisfy { abs($0 - $1) < 1e-5 }
}

private let inputs: [Double] = [0.1, 0.25, 0.5, 0.75, 0.9]

@Suite("Unit curves")
struct UnitCurveTests {

    // Values measured on SwiftUI (macOS 26.2 SDK),
    // `Tools/SwiftUIProbes/Animation curves, springs and keyframes/p3.swift`.

    @Test("The named Bézier curves give SwiftUI's values and velocities")
    func namedBeziers() {
        #expect(matches(inputs.map(UnitCurve.easeIn.value(at:)), [0.017027, 0.093465, 0.315357, 0.621861, 0.839428]))
        #expect(matches(inputs.map(UnitCurve.easeIn.velocity(at:)), [0.324183, 0.674598, 1.073978, 1.368289, 1.535074]))
        #expect(matches(inputs.map(UnitCurve.easeOut.value(at:)), [0.160572, 0.378139, 0.684643, 0.906535, 0.982973]))
        #expect(matches(inputs.map(UnitCurve.easeInOut.value(at:)), [0.019722, 0.129162, 0.5, 0.870838, 0.980278]))
        #expect(matches(inputs.map(UnitCurve.easeInOut.velocity(at:)), [0.402245, 1.059261, 1.724138, 1.059261, 0.402245]))
        #expect(UnitCurve.easeInEaseOut == UnitCurve.easeInOut)
    }

    @Test("Where a Bézier's tangent vanishes, the velocity is SwiftUI's: 1 at the start, 0 at the end")
    func vanishingTangents() {
        #expect(UnitCurve.easeOut.velocity(at: 0) == 1)
        #expect(UnitCurve.easeIn.velocity(at: 1) == 0)
        #expect(UnitCurve.easeIn.velocity(at: 0) == 0)
        #expect(UnitCurve.easeOut.velocity(at: 1) == 0)
    }

    @Test("A Bézier of the app's own, and its inverse")
    func customBezier() {
        let curve = UnitCurve.bezier(
            startControlPoint: UnitPoint(x: 0.1, y: 0.75), endControlPoint: UnitPoint(x: 0.85, y: 0.35))
        #expect(matches(inputs.map(curve.value(at:)), [0.291795, 0.435869, 0.5439, 0.646563, 0.775832]))
        #expect(matches(inputs.map(curve.velocity(at:)), [1.497718, 0.629474, 0.340261, 0.578615, 1.308986]))
        #expect(matches(inputs.map(curve.inverse.value(at:)), [0.018682, 0.074939, 0.378822, 0.878753, 0.969259]))
        #expect(curve.inverse.inverse == curve)
        #expect(UnitCurve.easeIn == .bezier(startControlPoint: UnitPoint(x: 0.42, y: 0), endControlPoint: UnitPoint(x: 1, y: 1)))
    }

    @Test("A control point's x is clamped to [0, 1] when the curve is evaluated")
    func controlPointsClamped() {
        let curve = UnitCurve.bezier(
            startControlPoint: UnitPoint(x: -0.5, y: 0.2), endControlPoint: UnitPoint(x: 1.5, y: 0.8))
        #expect(matches(inputs.map(curve.value(at:)), [0.15748, 0.295811, 0.5, 0.704189, 0.84252]))
    }

    @Test("The circular curves give SwiftUI's values and velocities, and are each other's inverses")
    func circular() {
        #expect(matches(inputs.map(UnitCurve.circularEaseIn.value(at:)), [0.005013, 0.031754, 0.133975, 0.338562, 0.56411]))
        #expect(matches(inputs.map(UnitCurve.circularEaseIn.velocity(at:)), [0.100504, 0.258199, 0.57735, 1.133893, 2.064742]))
        #expect(matches(inputs.map(UnitCurve.circularEaseOut.value(at:)), [0.43589, 0.661438, 0.866025, 0.968246, 0.994987]))
        #expect(matches(inputs.map(UnitCurve.circularEaseInOut.value(at:)), [0.010102, 0.066987, 0.5, 0.933013, 0.989898]))
        #expect(UnitCurve.circularEaseIn.velocity(at: 1) == .infinity)
        #expect(UnitCurve.circularEaseInOut.velocity(at: 0.5) == .infinity)
        #expect(UnitCurve.circularEaseIn.inverse == .circularEaseOut)
        #expect(UnitCurve.circularEaseInOut.inverse.inverse == .circularEaseInOut)
        // The inverse is the curve with its axes swapped, as documented —
        // where SwiftUI answers circularEaseInOut itself.
        let inverse = UnitCurve.circularEaseInOut.inverse
        for y in inputs {
            #expect(abs(UnitCurve.circularEaseInOut.value(at: inverse.value(at: y)) - y) < 1e-9)
        }
    }

    @Test("linear is the identity, and not a Bézier through the diagonal")
    func linear() {
        #expect(inputs.map(UnitCurve.linear.value(at:)) == inputs)
        #expect(inputs.map(UnitCurve.linear.velocity(at:)).allSatisfy { $0 == 1 })
        #expect(UnitCurve.linear.inverse == .linear)
        #expect(UnitCurve.linear != .bezier(startControlPoint: .zero, endControlPoint: UnitPoint(x: 1, y: 1)))
        #expect(UnitCurve.linear.value(at: 1.5) == 1, "clamped, as documented")
    }

    @Test("An animation timed by a curve moves as the curve does")
    func timingCurveAnimation() {
        #expect(Animation.timingCurve(.easeIn, duration: 2) == .easeIn(duration: 2))
        #expect(Animation.timingCurve(.linear, duration: 1) == .linear(duration: 1))
        let circular = Animation.timingCurve(.circularEaseIn, duration: 1)
        #expect(abs(circular.fraction(at: 0.5) - UnitCurve.circularEaseIn.value(at: 0.5)) < 1e-12)
        #expect(circular.description == "timingCurve(.circularEaseIn, duration: 1.0)")
        #expect(circular.isFinished(at: 1))
    }
}
