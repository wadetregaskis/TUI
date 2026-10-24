// Probe: SwiftUI MeshGradient on macOS 15.8 (SDK 26.2), read back as pixels.
// Build: xcrun swiftc -parse-as-library -O mesh.swift -o mesh && ./mesh OUTDIR
//
// Each case renders one MeshGradient at W×H points, scale 1, through
// ImageRenderer, and writes the RGBA8 (sRGB, unpremultiplied) bytes to
// OUTDIR/<name>.rgba with a one-line header file <name>.txt "W H".
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

let unit3x3: [SIMD2<Float>] = [
    [0, 0], [0.5, 0], [1, 0],
    [0, 0.5], [0.5, 0.5], [1, 0.5],
    [0, 1], [0.5, 1], [1, 1],
]

/// Colours that encode the mesh's own parameters: red = column / (w-1),
/// green = row / (h-1). Under bilinear colour, a pixel's (r, g) IS (U, V).
func coordColours(_ w: Int, _ h: Int) -> [Color] {
    var out: [Color] = []
    for row in 0..<h {
        for col in 0..<w {
            out.append(c(Double(col) / Double(w - 1), Double(row) / Double(h - 1), 0))
        }
    }
    return out
}

@main
struct Probe {
    @MainActor
    static func main() {
        let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "out"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // 1. One patch, bilinear vs smooth. TL black, TR red, BL green, BR yellow:
        //    red channel is u, green is v under bilinear.
        let corners: [SIMD2<Float>] = [[0, 0], [1, 0], [0, 1], [1, 1]]
        let quad = [c(0, 0, 0), c(1, 0, 0), c(0, 1, 0), c(1, 1, 0)]
        dump("p2x2_linear", MeshGradient(width: 2, height: 2, points: corners, colors: quad, smoothsColors: false), to: dir)
        dump("p2x2_smooth", MeshGradient(width: 2, height: 2, points: corners, colors: quad, smoothsColors: true), to: dir)

        // 2. One row of patches along x, red channel 0, 0.2, 1, 0.6, 0 (uneven, to
        //    identify the colour tangent rule). Height 2, both rows equal.
        let xs: [Float] = [0, 0.25, 0.5, 0.75, 1]
        var rowPts: [SIMD2<Float>] = []
        for y: Float in [0, 1] { for x in xs { rowPts.append([x, y]) } }
        let reds: [Double] = [0, 0.2, 1, 0.6, 0]
        let rowCols = (0..<2).flatMap { _ in reds.map { c($0, 0, 0) } }
        dump("row5_linear", MeshGradient(width: 5, height: 2, points: rowPts, colors: rowCols, smoothsColors: false), width: 401, height: 21, to: dir)
        dump("row5_smooth", MeshGradient(width: 5, height: 2, points: rowPts, colors: rowCols, smoothsColors: true), width: 401, height: 21, to: dir)
        // Same, uneven x spacing, to see whether tangents account for distance.
        let xs2: [Float] = [0, 0.1, 0.5, 0.6, 1]
        var rowPts2: [SIMD2<Float>] = []
        for y: Float in [0, 1] { for x in xs2 { rowPts2.append([x, y]) } }
        dump("row5u_linear", MeshGradient(width: 5, height: 2, points: rowPts2, colors: rowCols, smoothsColors: false), width: 401, height: 21, to: dir)
        dump("row5u_smooth", MeshGradient(width: 5, height: 2, points: rowPts2, colors: rowCols, smoothsColors: true), width: 401, height: 21, to: dir)

        // 3. Geometry: a 3×3 mesh, colours encoding (U, V), bilinear colour.
        dump("g3_regular", MeshGradient(width: 3, height: 3, points: unit3x3, colors: coordColours(3, 3), smoothsColors: false), to: dir)
        var moved = unit3x3
        moved[4] = [0.7, 0.5]
        dump("g3_movedx", MeshGradient(width: 3, height: 3, points: moved, colors: coordColours(3, 3), smoothsColors: false), to: dir)
        var moved2 = unit3x3
        moved2[4] = [0.7, 0.3]
        dump("g3_movedxy", MeshGradient(width: 3, height: 3, points: moved2, colors: coordColours(3, 3), smoothsColors: false), to: dir)
        var moved3 = unit3x3
        moved3[1] = [0.7, 0]
        dump("g3_movededge", MeshGradient(width: 3, height: 3, points: moved3, colors: coordColours(3, 3), smoothsColors: false), to: dir)
        // A 4×4 with an interior point moved: does the tangent at a vertex use
        // both neighbours (Catmull-Rom) or each edge on its own (straight)?
        var pts4: [SIMD2<Float>] = []
        for row in 0..<4 { for col in 0..<4 { pts4.append([Float(col) / 3, Float(row) / 3]) } }
        var pts4m = pts4
        pts4m[5] = [0.5, 0.2]
        dump("g4_moved", MeshGradient(width: 4, height: 4, points: pts4m, colors: coordColours(4, 4), smoothsColors: false), to: dir)

        // 4. Explicit Bézier points: one patch whose top edge bows down.
        func bp(_ p: SIMD2<Float>, l: SIMD2<Float>, t: SIMD2<Float>, r: SIMD2<Float>, b: SIMD2<Float>) -> MeshGradient.BezierPoint {
            .init(position: p, leadingControlPoint: l, topControlPoint: t, trailingControlPoint: r, bottomControlPoint: b)
        }
        let bow: [MeshGradient.BezierPoint] = [
            bp([0, 0], l: [0, 0], t: [0, 0], r: [0.33, 0.5], b: [0, 0.33]),
            bp([1, 0], l: [0.67, 0.5], t: [1, 0], r: [1, 0], b: [1, 0.33]),
            bp([0, 1], l: [0, 1], t: [0, 0.67], r: [0.33, 1], b: [0, 1]),
            bp([1, 1], l: [0.67, 1], t: [1, 0.67], r: [1, 1], b: [1, 1]),
        ]
        dump("b2_bow", MeshGradient(width: 2, height: 2, bezierPoints: bow, colors: quad, smoothsColors: false), to: dir)
        // Straight explicit control points at thirds, to compare with points:.
        let straight: [MeshGradient.BezierPoint] = [
            bp([0, 0], l: [0, 0], t: [0, 0], r: [0.33, 0], b: [0, 0.33]),
            bp([1, 0], l: [0.67, 0], t: [1, 0], r: [1, 0], b: [1, 0.33]),
            bp([0, 1], l: [0, 1], t: [0, 0.67], r: [0.33, 1], b: [0, 1]),
            bp([1, 1], l: [0.67, 1], t: [1, 0.67], r: [1, 1], b: [1, 1]),
        ]
        dump("b2_straight", MeshGradient(width: 2, height: 2, bezierPoints: straight, colors: quad, smoothsColors: false), to: dir)
        // Control points bunched toward the left: does parameter speed follow?
        let bunched: [MeshGradient.BezierPoint] = [
            bp([0, 0], l: [0, 0], t: [0, 0], r: [0.05, 0], b: [0, 0.33]),
            bp([1, 0], l: [0.1, 0], t: [1, 0], r: [1, 0], b: [1, 0.33]),
            bp([0, 1], l: [0, 1], t: [0, 0.67], r: [0.05, 1], b: [0, 1]),
            bp([1, 1], l: [0.1, 1], t: [1, 0.67], r: [1, 1], b: [1, 1]),
        ]
        dump("b2_bunched", MeshGradient(width: 2, height: 2, bezierPoints: bunched, colors: quad, smoothsColors: false), to: dir)

        // 5. Background: a mesh covering only the middle; default and a colour.
        let inner: [SIMD2<Float>] = [[0.25, 0.25], [0.75, 0.25], [0.25, 0.75], [0.75, 0.75]]
        dump("bg_default", MeshGradient(width: 2, height: 2, points: inner, colors: quad), to: dir)
        dump("bg_blue", MeshGradient(width: 2, height: 2, points: inner, colors: quad, background: c(0, 0, 1)), to: dir)
        // Points outside the unit square.
        let outer: [SIMD2<Float>] = [[-0.5, -0.5], [1.5, -0.5], [-0.5, 1.5], [1.5, 1.5]]
        dump("outer", MeshGradient(width: 2, height: 2, points: outer, colors: quad, smoothsColors: false), to: dir)

        // 6. Colour space: red → blue across one patch, device vs perceptual.
        let rb = [c(1, 0, 0), c(0, 0, 1), c(1, 0, 0), c(0, 0, 1)]
        dump("cs_device", MeshGradient(width: 2, height: 2, points: corners, colors: rb, smoothsColors: false, colorSpace: .device), width: 401, height: 21, to: dir)
        dump("cs_perceptual", MeshGradient(width: 2, height: 2, points: corners, colors: rb, smoothsColors: false, colorSpace: .perceptual), width: 401, height: 21, to: dir)
        dump("cs_device_smooth", MeshGradient(width: 2, height: 2, points: corners, colors: rb, smoothsColors: true, colorSpace: .device), width: 401, height: 21, to: dir)
        dump("cs_perceptual_smooth", MeshGradient(width: 2, height: 2, points: corners, colors: rb, smoothsColors: true, colorSpace: .perceptual), width: 401, height: 21, to: dir)

        // 7. Malformed: too few points; width 1.
        dump("bad_count", MeshGradient(width: 3, height: 3, points: corners, colors: quad, background: c(0, 0, 1)), width: 21, height: 21, to: dir)
        dump("bad_width1", MeshGradient(width: 1, height: 2, points: [[0, 0], [0, 1]], colors: [c(1, 0, 0), c(0, 1, 0)], background: c(0, 0, 1)), width: 21, height: 21, to: dir)
        dump("bad_colours", MeshGradient(width: 2, height: 2, points: corners, colors: [c(1, 0, 0)], background: c(0, 0, 1)), width: 21, height: 21, to: dir)

        // 8. The doc comment's own example, for a picture to compare.
        dump("doc_example", MeshGradient(width: 3, height: 3, points: unit3x3, colors: [
            .red, .purple, .indigo, .orange, .white, .blue, .yellow, .green, .mint,
        ]), to: dir)

        // 9. Smooth colour in 2D: a 3×3 with one bright centre.
        var centre = [Color](repeating: c(0, 0, 0), count: 9)
        centre[4] = c(1, 1, 1)
        dump("s3_centre_smooth", MeshGradient(width: 3, height: 3, points: unit3x3, colors: centre, smoothsColors: true), to: dir)
        dump("s3_centre_linear", MeshGradient(width: 3, height: 3, points: unit3x3, colors: centre, smoothsColors: false), to: dir)
        // Smooth with coordinate colours: whether a linear field stays linear.
        dump("s3_coord_smooth", MeshGradient(width: 3, height: 3, points: unit3x3, colors: coordColours(3, 3), smoothsColors: true), to: dir)
        // 10. Translucent colours.
        let half = [c(1, 0, 0).opacity(0.5), c(1, 0, 0), c(1, 0, 0).opacity(0), c(1, 0, 0)]
        dump("alpha", MeshGradient(width: 2, height: 2, points: corners, colors: half, smoothsColors: false), width: 21, height: 21, to: dir)
    }
}
