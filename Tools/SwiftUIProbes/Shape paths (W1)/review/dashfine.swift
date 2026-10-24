// Review-fix probe (W1, 2026-10-18): where CoreGraphics stops drawing a dash
// pattern as dashes and draws the line whole, and how a very long dashed line
// costs. A 4-wide horizontal line 40 px long; row 10's coverage shown.
import CoreGraphics
import Foundation
setvbuf(stdout, nil, _IONBF, 0)

func dashRow(_ pattern: [CGFloat], length: CGFloat = 40, scale: CGFloat = 1) -> (String, TimeInterval) {
    let width = 40, height = 20
    var pixels = [UInt8](repeating: 0, count: width * height)
    let start = Date()
    pixels.withUnsafeMutableBytes { raw in
        let ctx = CGContext(
            data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        ctx.setStrokeColor(gray: 1, alpha: 1)
        ctx.setLineWidth(4 / scale)
        ctx.setLineDash(phase: 0, lengths: pattern)
        ctx.move(to: CGPoint(x: 0, y: 10 / scale))
        ctx.addLine(to: CGPoint(x: length, y: 10 / scale))
        ctx.strokePath()
    }
    let t = Date().timeIntervalSince(start)
    let row = (0..<width).map { x -> String in
        let v = pixels[10 * width + x]
        return v == 0 ? "." : v == 255 ? "#" : String(Int(v) * 9 / 255)
    }.joined()
    return (row, t)
}
for pattern in [[CGFloat(2)], [1], [0.75], [0.5], [0.4], [0.3], [0.25], [0.2], [0.15], [0.1], [1, 3], [0.5, 1.5], [0.25, 0.75], [0.1, 0.3], [3, 0.1], [3, 0.01], [0.01, 3]] {
    let (row, t) = dashRow(pattern)
    print("dash \(pattern): \(row)  (\(String(format: "%.5f", t))s)")
}
// The same patterns at 4× scale: is the threshold in user space or device pixels?
for pattern in [[CGFloat(0.25)], [0.1], [0.05], [0.025]] {
    let (row, t) = dashRow(pattern, length: 10, scale: 4)
    print("4x dash \(pattern): \(row)  (\(String(format: "%.5f", t))s)")
}
for length in [CGFloat(1e5), 1e6, 1e7] {
    let (row, t) = dashRow([2, 2], length: length)
    print("[2,2] over \(length): \(row)  (\(String(format: "%.5f", t))s)")
}
