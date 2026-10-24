// Review-fix probe (W1, 2026-10-18): SwiftUI's descriptions of the arcs the
// review fixes pin (PathTests).
import CoreGraphics
import Foundation
import SwiftUI

func show(_ label: String, _ build: (inout SwiftUI.Path) -> Void) {
    var p = SwiftUI.Path()
    build(&p)
    let d = p.description
    let curves = d.split(separator: " ").filter { $0 == "c" }.count
    let tail = d.split(separator: " ").suffix(3).joined(separator: " ")
    print("\(label): curves=\(curves) tail=[\(tail)] full=\(d.count < 400 ? d : "…")")
}
show("rel 135") { $0.addRelativeArc(center: .zero, radius: 1, startAngle: .zero, delta: .degrees(135)) }
show("rel -200") { $0.addRelativeArc(center: .zero, radius: 1, startAngle: .degrees(30), delta: .degrees(-200)) }
show("rel nan") { $0.addRelativeArc(center: .zero, radius: 1, startAngle: .zero, delta: .radians(.nan)) }
show("rel inf") { $0.addRelativeArc(center: .zero, radius: 1, startAngle: .zero, delta: .radians(.infinity)) }
show("rel start nan") { $0.addRelativeArc(center: .zero, radius: 1, startAngle: .radians(.nan), delta: .radians(1)) }
show("rel 1e10") { $0.addRelativeArc(center: .zero, radius: 1, startAngle: .zero, delta: .radians(1e10)) }
show("rel -1e4") { $0.addRelativeArc(center: .zero, radius: 1, startAngle: .zero, delta: .radians(-1e4)) }
show("rel 1607") { $0.addRelativeArc(center: .zero, radius: 1, startAngle: .zero, delta: .radians(1607)) }
show("line then rel nan") { $0.move(to: CGPoint(x: 5, y: 5)); $0.addRelativeArc(center: .zero, radius: 1, startAngle: .zero, delta: .radians(.nan)) }
show("arc end nan") { $0.addArc(center: .zero, radius: 1, startAngle: .zero, endAngle: .radians(.nan), clockwise: false) }
show("arc start nan") { $0.addArc(center: .zero, radius: 1, startAngle: .radians(.nan), endAngle: .zero, clockwise: false) }
show("arc end inf") { $0.addArc(center: .zero, radius: 1, startAngle: .zero, endAngle: .radians(.infinity), clockwise: false) }
show("arc 0->3pi") { $0.addArc(center: .zero, radius: 1, startAngle: .zero, endAngle: .radians(3 * .pi), clockwise: false) }
show("arc 0->3pi cw") { $0.addArc(center: .zero, radius: 1, startAngle: .zero, endAngle: .radians(3 * .pi), clockwise: true) }
show("arc 0->-1 ccw") { $0.addArc(center: .zero, radius: 1, startAngle: .zero, endAngle: .radians(-1), clockwise: false) }
show("arc 0->1 cw") { $0.addArc(center: .zero, radius: 1, startAngle: .zero, endAngle: .radians(1), clockwise: true) }
show("arc 0->-3pi cw") { $0.addArc(center: .zero, radius: 1, startAngle: .zero, endAngle: .radians(-3 * .pi), clockwise: true) }
show("arc 0->0") { $0.addArc(center: .zero, radius: 1, startAngle: .zero, endAngle: .zero, clockwise: false) }
show("arc 0->2pi") { $0.addArc(center: .zero, radius: 1, startAngle: .zero, endAngle: .radians(2 * .pi), clockwise: false) }
show("arc 0->2pi cw") { $0.addArc(center: .zero, radius: 1, startAngle: .zero, endAngle: .radians(2 * .pi), clockwise: true) }
show("arc 0->1e10") { $0.addArc(center: .zero, radius: 1, startAngle: .zero, endAngle: .radians(1e10), clockwise: false) }
show("arc 0->1e10 cw") { $0.addArc(center: .zero, radius: 1, startAngle: .zero, endAngle: .radians(1e10), clockwise: true) }
show("rel 0") { $0.addRelativeArc(center: .zero, radius: 1, startAngle: .zero, delta: .zero) }
show("rel 2pi") { $0.addRelativeArc(center: .zero, radius: 1, startAngle: .zero, delta: .radians(2 * .pi)) }
