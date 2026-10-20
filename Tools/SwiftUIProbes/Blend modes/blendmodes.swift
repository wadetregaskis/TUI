// Probe: SwiftUI's View.blendMode(_:) on macOS 15.8 (SDK 26.2), read back as pixels.
// Which space each mode works in (the encoded sRGB values, or linear light), what a
// translucent source does, and what the Porter-Duff modes leave where the source is
// and where it is not.
// Build: xcrun swiftc -parse-as-library -O blendmodes.swift -o blendmodes && ./blendmodes
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
    let ctx = CGContext(
        data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return bytes
}

/// The pixel at (x, y) of `view` drawn 40×20: the source covers the left half only.
@MainActor
func pixels<V: View>(_ view: V) -> (inside: [UInt8], outside: [UInt8]) {
    let b = render(view, width: 40, height: 20)
    func at(_ x: Int, _ y: Int) -> [UInt8] { let i = (y * 40 + x) * 4; return Array(b[i..<i + 4]) }
    return (at(10, 10), at(30, 10))
}

let backdrop = Color(.sRGB, red: 0.2, green: 0.6, blue: 0.9)
let source = Color(.sRGB, red: 0.8, green: 0.4, blue: 0.3)

let modes: [(String, BlendMode)] = [
    ("normal", .normal), ("multiply", .multiply), ("screen", .screen), ("overlay", .overlay),
    ("darken", .darken), ("lighten", .lighten), ("colorDodge", .colorDodge), ("colorBurn", .colorBurn),
    ("softLight", .softLight), ("hardLight", .hardLight), ("difference", .difference),
    ("exclusion", .exclusion), ("hue", .hue), ("saturation", .saturation), ("color", .color),
    ("luminosity", .luminosity), ("sourceAtop", .sourceAtop), ("destinationOver", .destinationOver),
    ("destinationOut", .destinationOut), ("plusDarker", .plusDarker), ("plusLighter", .plusLighter),
]

@main
struct Probe {
    @MainActor
    static func main() {
        print("backdrop 51,153,230 (0.2 0.6 0.9); source 204,102,77 (0.8 0.4 0.3); pixels r,g,b,a")
        for (name, mode) in modes {
            // Opaque source over an opaque backdrop, the source over the left half.
            let opaque = pixels(ZStack(alignment: .leading) {
                backdrop
                source.frame(width: 20).blendMode(mode)
            })
            // The same source at half opacity.
            let half = pixels(ZStack(alignment: .leading) {
                backdrop
                source.opacity(0.5).frame(width: 20).blendMode(mode)
            })
            // Over nothing: the backdrop covers the left half only, the source the whole.
            let bare = pixels(ZStack(alignment: .leading) {
                backdrop.frame(width: 20)
                source.blendMode(mode)
            })
            print("\(name): over \(opaque.inside) beside \(opaque.outside) | half \(half.inside)"
                + " | over-backdrop \(bare.inside) over-nothing \(bare.outside)")
        }
    }
}
