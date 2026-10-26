// Probe 2: SwiftUI MeshGradient's smooth colour rule, measured on macOS 15.8.
// Build: xcrun swiftc -parse-as-library -O mesh2.swift -o mesh2 && ./mesh2 out
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

func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color {
    Color(.sRGB, red: r, green: g, blue: b, opacity: a)
}

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
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Monotonicity: R has a steep-after-shallow vertex and a plateau; G an
        // extremum; B a monotone ramp with uneven steps.
        let r: [Double] = [0.5, 0.52, 0.9, 0.9, 0.5]
        let g: [Double] = [0, 0.5, 1, 0.5, 0]
        let b: [Double] = [0, 0.1, 0.2, 0.6, 1.0]
        let row = (0..<5).map { c(r[$0], g[$0], b[$0]) }
        dump("t_ext", MeshGradient(width: 5, height: 2, points: regular(5, 2), colors: row + row), width: 401, height: 11, to: dir)

        // Per channel or per colour: R has an extremum at the middle, G does not.
        let pc = [c(0, 0, 0), c(1, 0.5, 0), c(0, 1, 0)]
        dump("t_perchan", MeshGradient(width: 3, height: 2, points: regular(3, 2), colors: pc + pc), width: 401, height: 11, to: dir)

        // Twist: R = U·V at the vertices; G a non-separable pattern; B = 0.
        var tw: [Color] = []
        let gv: [[Double]] = [[0.2, 0.6, 0.3], [0.7, 0.4, 0.9], [0.1, 0.8, 0.5]]
        for row in 0..<3 { for col in 0..<3 {
            tw.append(c(Double(col) / 2 * Double(row) / 2, gv[row][col], 0))
        } }
        dump("t_twist", MeshGradient(width: 3, height: 3, points: regular(3, 3), colors: tw), to: dir)
        dump("t_twist_linear", MeshGradient(width: 3, height: 3, points: regular(3, 3), colors: tw, smoothsColors: false), to: dir)

        // A 4×4 smooth mesh of pseudo-random colours, for a whole-picture check.
        var rnd: [Color] = []
        var seed: UInt64 = 12345
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) % 1000) / 999
        }
        for _ in 0..<16 { rnd.append(c(next(), next(), next())) }
        dump("t_rand4", MeshGradient(width: 4, height: 4, points: regular(4, 4), colors: rnd), to: dir)
        dump("t_rand4_linear", MeshGradient(width: 4, height: 4, points: regular(4, 4), colors: rnd, smoothsColors: false), to: dir)
        dump("t_rand4_perceptual", MeshGradient(width: 4, height: 4, points: regular(4, 4), colors: rnd, colorSpace: .perceptual), to: dir)
        dump("t_rand4_perceptual_linear", MeshGradient(width: 4, height: 4, points: regular(4, 4), colors: rnd, smoothsColors: false, colorSpace: .perceptual), to: dir)
        print(rnd.map { col -> String in
            let res = col.resolve(in: EnvironmentValues())
            return "(\(res.red),\(res.green),\(res.blue))"
        }.joined(separator: " "))

        // Alpha: red to clear (Color.clear) vs red to transparent red.
        dump("t_alpha", MeshGradient(width: 2, height: 2, points: regular(2, 2),
            colors: [c(1, 0, 0), .clear, c(1, 0, 0), .clear], smoothsColors: false), width: 101, height: 5, to: dir)
        dump("t_alpha_red", MeshGradient(width: 2, height: 2, points: regular(2, 2),
            colors: [c(1, 0, 0), c(1, 0, 0, 0), c(1, 0, 0), c(1, 0, 0, 0)], smoothsColors: false), width: 101, height: 5, to: dir)
        dump("t_alpha_green", MeshGradient(width: 2, height: 2, points: regular(2, 2),
            colors: [c(1, 0, 0), c(0, 1, 0, 0.5), c(1, 0, 0), c(0, 1, 0, 0.5)], smoothsColors: false), width: 101, height: 5, to: dir)

        // Uneven positions with smooth colours: do colour tangents see distance?
        let xs: [Float] = [0, 0.1, 0.5, 0.6, 1]
        var pts: [SIMD2<Float>] = []
        for y: Float in [0, 1] { for x in xs { pts.append([x, y]) } }
        let ramp = [0.0, 0.25, 0.5, 0.75, 1.0].map { c($0, 0, 0) }
        dump("t_uneven", MeshGradient(width: 5, height: 2, points: pts, colors: ramp + ramp), width: 401, height: 11, to: dir)
        dump("t_uneven_linear", MeshGradient(width: 5, height: 2, points: pts, colors: ramp + ramp, smoothsColors: false), width: 401, height: 11, to: dir)

        // The doc example at a TUI-like size, for test pins: 40×10 "cells".
        dump("doc_small", MeshGradient(width: 3, height: 3, points: regular(3, 3), colors: [
            .red, .purple, .indigo, .orange, .white, .blue, .yellow, .green, .mint,
        ]), width: 400, height: 200, to: dir)
        let named: [Color] = [.red, .purple, .indigo, .orange, .white, .blue, .yellow, .green, .mint]
        print(named.map { col -> String in
            let res = col.resolve(in: EnvironmentValues())
            return "(\(res.red),\(res.green),\(res.blue))"
        }.joined(separator: " "))
    }
}
