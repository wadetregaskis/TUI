// Probe: stacked and translucent ShapeStyle.shadow(_:), read back as pixels (macOS 15.8, SDK 26.2).
// Build: xcrun swiftc -parse-as-library -O stacked.swift -o stacked && ./stacked
import AppKit
import SwiftUI
@MainActor
func render<V: View>(_ view: V, width: Int, height: Int) -> [UInt8] {
    let renderer = ImageRenderer(content: view.frame(width: CGFloat(width), height: CGFloat(height)))
    renderer.scale = 1
    renderer.isOpaque = false
    guard let image = renderer.cgImage else { fatalError("no image") }
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return bytes
}
@MainActor
func px<V: View>(_ name: String, _ view: V, w: Int = 100, h: Int = 100, at points: [(Int, Int)]) {
    let b = render(view, width: w, height: h)
    var out = "\(name):"
    for (x, y) in points { let i = (y * w + x) * 4; out += " (\(x),\(y))=\(b[i]),\(b[i+1]),\(b[i+2]),\(b[i+3])" }
    print(out)
}
@main struct Probe { @MainActor static func main() {
    let p = [(50, 50), (80, 50), (50, 80), (80, 80)]
    px("Q6 red.shadow(A black x30).shadow(B blue y30)", Rectangle().fill(.red.shadow(.drop(color: .black, radius: 0, x: 30, y: 0)).shadow(.drop(color: .blue, radius: 0, x: 0, y: 30))).frame(width: 40, height: 40), at: p)
    px("Q6b inner then drop", Rectangle().fill(.red.shadow(.inner(color: .black, radius: 0, x: 5, y: 5)).shadow(.drop(color: .blue, radius: 0, x: 0, y: 30))).frame(width: 40, height: 40), at: [(32, 50), (50, 50), (32, 80), (50, 80)])
    px("Q6c drop then inner", Rectangle().fill(.red.shadow(.drop(color: .blue, radius: 0, x: 0, y: 30)).shadow(.inner(color: .black, radius: 0, x: 5, y: 5))).frame(width: 40, height: 40), at: [(32, 50), (50, 50), (32, 80), (50, 80)])
    // translucent drop colour: alpha of shadow
    px("Q14 drop color 0.5 black", Rectangle().fill(.red.shadow(.drop(color: .black.opacity(0.5), radius: 0, x: 0, y: 30))).frame(width: 40, height: 40), at: [(50, 80)])
    px("Q15 gradient half-transparent end shadow", Rectangle().fill(LinearGradient(colors: [.red, .red.opacity(0)], startPoint: .leading, endPoint: .trailing).shadow(.drop(color: .black, radius: 0, x: 0, y: 30))).frame(width: 40, height: 40), at: [(31, 80), (50, 80), (69, 80)])
} }
