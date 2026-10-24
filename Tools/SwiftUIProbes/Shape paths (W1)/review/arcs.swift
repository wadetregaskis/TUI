// Review-fix probe (W1, 2026-10-18): how CoreGraphics and SwiftUI build arcs
// of non-finite or huge angles, and how CG dashes an odd-length pattern or a
// very fine one.
import CoreGraphics
import Foundation
import SwiftUI

func count(_ path: CGPath) -> (Int, String) {
    var n = 0
    var last = ""
    path.applyWithBlock { element in
        n += 1
        let e = element.pointee
        switch e.type {
        case .moveToPoint: last = "move \(e.points[0])"
        case .addLineToPoint: last = "line \(e.points[0])"
        case .addCurveToPoint: last = "curve \(e.points[2])"
        case .addQuadCurveToPoint: last = "quad \(e.points[1])"
        case .closeSubpath: last = "close"
        @unknown default: last = "?"
        }
    }
    return (n, last)
}

for delta in [Double.nan, .infinity, -.infinity, 1e20, 1e10, 1e4, 100, 2 * .pi * 3 + 1] {
    let cg = CGMutablePath()
    let start = Date()
    cg.addRelativeArc(center: .zero, radius: 10, startAngle: 0, delta: delta)
    let t = Date().timeIntervalSince(start)
    print("CG relativeArc delta \(delta): \(count(cg)) in \(t)s")
    var sp = SwiftUI.Path()
    let s2 = Date()
    sp.addRelativeArc(center: .zero, radius: 10, startAngle: .zero, delta: .radians(delta))
    print("  SwiftUI relativeArc: \(count(sp.cgPath)) in \(Date().timeIntervalSince(s2))s")
    var sp2 = SwiftUI.Path()
    sp2.addArc(center: .zero, radius: 10, startAngle: .zero, endAngle: .radians(delta), clockwise: false)
    print("  SwiftUI addArc end=\(delta): \(count(sp2.cgPath))")
}
var nanStart = SwiftUI.Path()
nanStart.addArc(center: .zero, radius: 10, startAngle: .radians(.nan), endAngle: .radians(1), clockwise: false)
print("SwiftUI addArc start=nan: \(count(nanStart.cgPath))")

// Dashes: a horizontal line 40 long, 4 wide, at y 10 in a 40×20 bitmap;
// alpha along row 10 shows the pattern.
func dashRow(_ pattern: [CGFloat], phase: CGFloat = 0) -> (String, TimeInterval) {
    let width = 40, height = 20
    var pixels = [UInt8](repeating: 0, count: width * height)
    let start = Date()
    pixels.withUnsafeMutableBytes { raw in
        let ctx = CGContext(
            data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.setShouldAntialias(true)
        ctx.setStrokeColor(gray: 1, alpha: 1)
        ctx.setLineWidth(4)
        ctx.setLineDash(phase: phase, lengths: pattern)
        ctx.move(to: CGPoint(x: 0, y: 10))
        ctx.addLine(to: CGPoint(x: 40, y: 10))
        ctx.strokePath()
    }
    let t = Date().timeIntervalSince(start)
    let row = (0..<width).map { x -> String in
        let v = pixels[10 * width + x]
        return v == 0 ? "." : v == 255 ? "#" : "+"
    }.joined()
    return (row, t)
}
for pattern in [[CGFloat(4)], [4, 2], [4, 2, 6], [1e-6], [1e-6, 1e-5], [0.1], [0.05, 0.15]] {
    let (row, t) = dashRow(pattern)
    print("dash \(pattern): \(row)  (\(t)s)")
}
