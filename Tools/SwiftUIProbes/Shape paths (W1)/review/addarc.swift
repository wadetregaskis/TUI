// Review-fix probe (W1, 2026-10-18): SwiftUI's addArc past a turn, and its
// relative arc's segmentation near the cap.
import CoreGraphics
import Foundation
import SwiftUI

func describe(_ path: CGPath) -> String {
    var n = 0
    var last = CGPoint.zero
    path.applyWithBlock { element in
        n += 1
        let e = element.pointee
        switch e.type {
        case .moveToPoint, .addLineToPoint: last = e.points[0]
        case .addCurveToPoint: last = e.points[2]
        default: break
        }
    }
    return "\(n) elements, ends (\(String(format: "%.4f", last.x)), \(String(format: "%.4f", last.y)))"
}
let cases: [(Double, Double, Bool)] = [
    (0, 1, false), (0, -1, false), (0, 2 * .pi, false), (0, 2 * .pi + 0.5, false), (0, 3 * .pi, false),
    (0, 100, false), (0, 100, true), (0, -100, true), (1, 0, true), (0, 1, true), (0, 4 * .pi, false),
    (0, .infinity, false), (0, .nan, true), (.infinity, 1, false),
]
for (s, e, cw) in cases {
    var p = SwiftUI.Path()
    p.addArc(center: .zero, radius: 10, startAngle: .radians(s), endAngle: .radians(e), clockwise: cw)
    let cg = CGMutablePath()
    cg.addArc(center: .zero, radius: 10, startAngle: s, endAngle: e, clockwise: cw)
    print("addArc \(s)→\(e) cw \(cw): SwiftUI \(describe(p.cgPath)) | CG \(describe(cg))")
}
for d in [1600.0, 1606.0, 1607.0, 1608.0, -1e4, 1e300] {
    var p = SwiftUI.Path()
    p.addRelativeArc(center: .zero, radius: 10, startAngle: .zero, delta: .radians(d))
    print("relative \(d): \(describe(p.cgPath))")
}
