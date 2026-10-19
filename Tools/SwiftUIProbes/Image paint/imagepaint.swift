// Probe: SwiftUI ImagePaint tiling, read back as pixels (macOS 15.8, SDK 26.2).
// Build: xcrun swiftc -parse-as-library -O imagepaint.swift -o imagepaint && ./imagepaint
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

/// A 4×4 image: top-left red, top-right green, bottom-left blue, bottom-right white (2×2 each).
func quadrants() -> CGImage {
    var px = [UInt8](repeating: 0, count: 4 * 4 * 4)
    for y in 0..<4 { for x in 0..<4 {
        let i = (y * 4 + x) * 4
        let (r, g, b): (UInt8, UInt8, UInt8) = y < 2 ? (x < 2 ? (255, 0, 0) : (0, 255, 0)) : (x < 2 ? (0, 0, 255) : (255, 255, 255))
        px[i] = r; px[i + 1] = g; px[i + 2] = b; px[i + 3] = 255
    } }
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: &px, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return ctx.makeImage()!
}

func name(_ b: [UInt8], _ w: Int, _ x: Int, _ y: Int) -> String {
    let i = (y * w + x) * 4
    switch (b[i], b[i + 1], b[i + 2], b[i + 3]) {
    case (255, 0, 0, 255): return "R"
    case (0, 255, 0, 255): return "G"
    case (0, 0, 255, 255): return "B"
    case (255, 255, 255, 255): return "W"
    case (_, _, _, 0): return "."
    default: return "(\(b[i]),\(b[i+1]),\(b[i+2]),\(b[i+3]))"
    }
}

@MainActor
func row(_ label: String, _ view: some View, w: Int = 24, h: Int = 24, y: Int, xs: Range<Int>) {
    let b = render(view, width: w, height: h)
    print(label, "y=\(y):", xs.map { name(b, w, $0, y) }.joined())
}

@main struct Probe { @MainActor static func main() {
    let img = Image(decorative: quadrants(), scale: 1)
    let img2 = Image(decorative: quadrants(), scale: 2)
    row("scale1", Rectangle().fill(ImagePaint(image: img)).frame(width: 16, height: 16), y: 4, xs: 0..<24)
    row("scale1", Rectangle().fill(ImagePaint(image: img)).frame(width: 16, height: 16), y: 6, xs: 0..<24)
    row("scale2", Rectangle().fill(ImagePaint(image: img, scale: 2)).frame(width: 16, height: 16), y: 4, xs: 0..<24)
    row("scale0.5", Rectangle().fill(ImagePaint(image: img, scale: 0.5)).frame(width: 16, height: 16), y: 4, xs: 0..<24)
    row("imgscale2", Rectangle().fill(ImagePaint(image: img2)).frame(width: 16, height: 16), y: 4, xs: 0..<24)
    row("srcTR", Rectangle().fill(ImagePaint(image: img, sourceRect: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))).frame(width: 16, height: 16), y: 4, xs: 0..<24)
    row("srcLeftHalf", Rectangle().fill(ImagePaint(image: img, sourceRect: CGRect(x: 0, y: 0, width: 0.5, height: 1))).frame(width: 16, height: 16), y: 4, xs: 0..<24)
    row("srcLeftHalf", Rectangle().fill(ImagePaint(image: img, sourceRect: CGRect(x: 0, y: 0, width: 0.5, height: 1))).frame(width: 16, height: 16), y: 6, xs: 0..<24)
    // Where does the tile start: a shape offset within its frame (frame 24 at origin, shape 13x13 centred)
    row("centred13", Rectangle().fill(ImagePaint(image: img)).frame(width: 13, height: 13), y: 6, xs: 0..<24)
    row("circle", Circle().fill(ImagePaint(image: img)).frame(width: 16, height: 16), y: 12, xs: 0..<24)
    row("fgstyle", Text("████").font(.system(size: 20)).foregroundStyle(ImagePaint(image: img)), w: 80, h: 24, y: 12, xs: 0..<40)
    row("background", Color.clear.frame(width: 16, height: 16).background(ImagePaint(image: img)), y: 4, xs: 0..<24)
    // `ShapeStyle.in(_:)`: the rectangle's origin moves where the tiles start; its size changes nothing.
    let anchored = ImagePaint(image: img).in(CGRect(x: 2, y: 3, width: 8, height: 8))
    row("in(2,3,8x8)", Rectangle().fill(anchored).frame(width: 16, height: 16), y: 4, xs: 0..<24)
    row("in(2,3,8x8)", Rectangle().fill(anchored).frame(width: 16, height: 16), y: 7, xs: 0..<24)
    let wide = ImagePaint(image: img).in(CGRect(x: 2, y: 3, width: 40, height: 2))
    row("in(2,3,40x2)", Rectangle().fill(wide).frame(width: 16, height: 16), y: 7, xs: 0..<24)
    row("background in(2,3,8x8)", Color.clear.frame(width: 16, height: 16).background(anchored), y: 7, xs: 0..<24)
} }
