// Probe 3: smooth colours in the perceptual space, one row at a time.
// Build: xcrun swiftc -parse-as-library -O mesh3.swift -o mesh3 && ./mesh3 out
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

@MainActor
func dump<V: View>(_ name: String, _ view: V, width: Int = 201, height: Int = 201, to dir: String) {
    let bytes = render(view, width: width, height: height)
    FileManager.default.createFile(atPath: "\(dir)/\(name).rgba", contents: Data(bytes))
    try! "\(width) \(height)\n".write(toFile: "\(dir)/\(name).txt", atomically: true, encoding: .utf8)
    print("wrote \(name) \(width)x\(height)")
}

func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }

func regular(_ w: Int, _ h: Int) -> [SIMD2<Float>] {
    var out: [SIMD2<Float>] = []
    for row in 0..<h { for col in 0..<w { out.append([Float(col) / Float(w - 1), Float(row) / Float(h - 1)]) } }
    return out
}

@main
struct Probe {
    @MainActor
    static func main() {
        let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "out"
        // Greys: only OKLab L moves.
        let greys = [0.2, 0.25, 0.8, 0.8, 0.3].map { c($0, $0, $0) }
        dump("p_grey", MeshGradient(width: 5, height: 2, points: regular(5, 2), colors: greys + greys, colorSpace: .perceptual), width: 401, height: 11, to: dir)
        dump("p_grey_device", MeshGradient(width: 5, height: 2, points: regular(5, 2), colors: greys + greys), width: 401, height: 11, to: dir)
        // Monotone greys, evenly spaced in L would be linear: check no overshoot.
        let greys2 = [0.1, 0.3, 0.5, 0.7, 0.9].map { c($0, $0, $0) }
        dump("p_grey2", MeshGradient(width: 5, height: 2, points: regular(5, 2), colors: greys2 + greys2, colorSpace: .perceptual), width: 401, height: 11, to: dir)
        // Three hues at one lightness-ish.
        let hues = [c(0.8, 0.2, 0.2), c(0.2, 0.7, 0.2), c(0.2, 0.3, 0.9)]
        dump("p_hue", MeshGradient(width: 3, height: 2, points: regular(3, 2), colors: hues + hues, colorSpace: .perceptual), width: 401, height: 11, to: dir)
        dump("p_hue_device", MeshGradient(width: 3, height: 2, points: regular(3, 2), colors: hues + hues), width: 401, height: 11, to: dir)
        // The random 4x4 row 1 alone as a 4x2 mesh.
        let r1 = [c(0.34934932, 0.0, 0.60560566), c(0.46846843, 0.34334335, 0.7677678),
                  c(0.23623621, 0.8058058, 0.9309309), c(0.9169169, 0.6116116, 0.34734735)]
        dump("p_r1", MeshGradient(width: 4, height: 2, points: regular(4, 2), colors: r1 + r1, colorSpace: .perceptual), width: 401, height: 11, to: dir)
        dump("p_r1_device", MeshGradient(width: 4, height: 2, points: regular(4, 2), colors: r1 + r1), width: 401, height: 11, to: dir)
    }
}
