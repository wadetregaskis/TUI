// Review-fix probe (W1, 2026-10-18): where SwiftUI's relative arc stops adding quarter turns.
import CoreGraphics
import Foundation
import SwiftUI

func describe(_ path: CGPath) -> String {
    var n = 0
    var last = CGPoint.zero
    var curves: [(CGPoint, CGPoint)] = []
    var previous = CGPoint.zero
    path.applyWithBlock { element in
        n += 1
        let e = element.pointee
        switch e.type {
        case .moveToPoint, .addLineToPoint: last = e.points[0]; previous = last
        case .addCurveToPoint: curves.append((previous, e.points[2])); last = e.points[2]; previous = last
        default: break
        }
    }
    let a = curves.first.map { atan2($0.1.y, $0.1.x) } ?? 0
    let z = curves.last.map { (atan2($0.0.y, $0.0.x), atan2($0.1.y, $0.1.x)) } ?? (0, 0)
    return "\(n) elements, ends at angle \(String(format: "%.4f", atan2(last.y, last.x))), first curve to \(String(format: "%.4f", a)), last \(String(format: "%.4f", z.0))→\(String(format: "%.4f", z.1))"
}
for d in [1608.0, 1608.4, 1608.6, 1609, 1610, 1700, 1e4, 3, -3, 0.0] {
    var p = SwiftUI.Path()
    p.addRelativeArc(center: .zero, radius: 10, startAngle: .zero, delta: .radians(d))
    print("relative \(d) [mod 2π \(String(format: "%.4f", remainder(d, 2 * .pi)))]: \(describe(p.cgPath))")
}
