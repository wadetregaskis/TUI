//  🖥️ TUI — A Terminal UI framework for Swift
//  MeshColourField.swift
//
//  The colour at a place in a mesh gradient's patch: bilinear, or bicubic
//  through limited tangents, in device or perceptual space, premultiplied.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIStyling

/// The colour of a mesh at any point of any patch, given as the patch and the
/// point's `(u, v)` in it.
///
/// Built once per drawing from a ``MeshPaint`` — every vertex's colour turned
/// into the space it blends in, and for a smooth mesh its tangents — and then
/// asked per sample, which is a weighted sum of four corners.
///
/// ## The rules, as SwiftUI draws them
///
/// Measured on macOS 15.8 against meshes of chosen and pseudo-random colours,
/// each a single row or a whole grid, reading back every pixel:
///
/// - **`smoothsColors: false`** blends the four corners bilinearly in `(u, v)`,
///   to the byte.
/// - **`smoothsColors: true`** is a bicubic Hermite patch per channel, with no
///   twist. A vertex's slope along a row is Catmull–Rom's — half the
///   difference between its neighbours — and is zero at an edge of the mesh
///   (not one-sided), zero where the vertex is above or below BOTH neighbours,
///   and otherwise limited to three times the smaller of its two differences,
///   which is what keeps a monotone run from overshooting. Down a column the
///   same. The slopes are in the patch's own parameter, blind to how far apart
///   the vertices are placed. Residual against SwiftUI: 1 level in 255,
///   which is the size of its own tessellation.
/// - **Perceptual** blends in OKLab — but a smooth blend's slopes and limits
///   are decided per channel of OKLab's cube-root cone space (`Color.cubeRootLMS`),
///   the stage before its final matrix. Decided in OKLab itself, a smooth
///   perceptual grid missed SwiftUI by 12 levels; in that space, by 1.4. (For a
///   straight blend the two spaces are the same blend.)
/// - **Alpha** blends premultiplied: halfway from opaque red to half-transparent
///   green is `(170, 85, 0)` at 75 %, as SwiftUI drew it.
///
/// A vertex whose colour the terminal decides — ``Color/default``, or a slot it
/// has not reported — has nothing to blend, which is the rule `Color.lerp`
/// keeps for a gradient: the patch takes whichever of its corners weighs most
/// at the point, whole, and a smooth slope beside it is flat.
struct MeshColourField {
    /// A colour in its blending space, premultiplied, alpha last.
    ///
    /// Four named `Double`s rather than a `SIMD4`, for the reason
    /// `MeshPatchNet.swift` gives: SIMD's arithmetic is generic, and an
    /// unoptimised build pays a protocol call per lane — this is asked once per
    /// sample, and a picture is a quarter of a million samples.
    struct Channels {
        var first = 0.0
        var second = 0.0
        var third = 0.0
        var alpha = 0.0

        static func + (lhs: Self, rhs: Self) -> Self {
            Self(
                first: lhs.first + rhs.first, second: lhs.second + rhs.second, third: lhs.third + rhs.third,
                alpha: lhs.alpha + rhs.alpha)
        }

        static func * (lhs: Self, rhs: Double) -> Self {
            Self(first: lhs.first * rhs, second: lhs.second * rhs, third: lhs.third * rhs, alpha: lhs.alpha * rhs)
        }
    }

    private let width: Int
    private let smooth: Bool
    private let perceptual: Bool
    /// Per vertex: the colour in its blending space.
    private let values: [Channels]
    /// Per vertex, a smooth mesh's slopes along its row and down its column.
    private let alongRow: [Channels]
    private let downColumn: [Channels]
    /// Per vertex: whether its colour has components to blend.
    private let mixable: [Bool]
    /// Per vertex: its colour as spelled, for a patch that cannot be blended.
    private let spelled: [Color]

    /// The field of `paint`'s colours. A short colour list is filled out with
    /// `.clear`, as SwiftUI's is; a long one is cut to the vertices.
    init(_ paint: MeshPaint) {
        // A field is read only where the mesh draws patches, so one that does
        // not has none: `width × height` taken from the app's numbers before
        // they are checked against its locations could overflow, or ask for
        // 10^18 colours (a `MeshGradient(width: .max, …)`).
        let (width, height) = MeshVertices.drawsPatches(paint) ? (paint.width, paint.height) : (0, 0)
        let count = width * height
        let colours =
            Array(paint.colors.prefix(count))
            + Array(repeating: Color.clear, count: max(0, count - paint.colors.count))
        let perceptual = paint.colorSpace == .perceptual
        let mixable = colours.map { $0.rgbComponents != nil }
        let values = colours.map { Self.channels(of: $0, perceptual: perceptual) }
        self.width = width
        self.smooth = paint.smoothsColors
        self.perceptual = perceptual
        self.spelled = colours
        self.mixable = mixable
        self.values = values
        guard paint.smoothsColors else {
            alongRow = []
            downColumn = []
            return
        }
        var alongRow = [Channels](repeating: Channels(), count: count)
        var downColumn = [Channels](repeating: Channels(), count: count)
        for row in 0..<height {
            for column in 0..<width {
                let here = row * width + column
                alongRow[here] = Self.slope(
                    of: values, mixable: mixable, before: column > 0 ? here - 1 : nil, at: here,
                    after: column < width - 1 ? here + 1 : nil)
                downColumn[here] = Self.slope(
                    of: values, mixable: mixable, before: row > 0 ? here - width : nil, at: here,
                    after: row < height - 1 ? here + width : nil)
            }
        }
        self.alongRow = alongRow
        self.downColumn = downColumn
    }

    /// A colour in its blending space: encoded sRGB, or OKLab's cube-root cone
    /// responses; premultiplied. Zero for a colour with no components, which
    /// is never blended.
    private static func channels(of colour: Color, perceptual: Bool) -> Channels {
        guard let rgb = colour.rgbComponents else { return Channels() }
        let alpha = Double(colour.alpha) / 255
        if perceptual {
            let cone = Color.cubeRootLMS(red: rgb.red, green: rgb.green, blue: rgb.blue)
            return Channels(first: cone.long * alpha, second: cone.medium * alpha, third: cone.short * alpha, alpha: alpha)
        }
        let scale = alpha / 255
        return Channels(
            first: Double(rgb.red) * scale, second: Double(rgb.green) * scale, third: Double(rgb.blue) * scale,
            alpha: alpha)
    }

    /// A vertex's slope along one direction, per channel, by the rule above.
    private static func slope(
        of values: [Channels], mixable: [Bool], before: Int?, at here: Int, after: Int?
    ) -> Channels {
        guard let before, let after, mixable[before], mixable[here], mixable[after] else { return Channels() }
        let (previous, current, next) = (values[before], values[here], values[after])
        func slope(_ previous: Double, _ current: Double, _ next: Double) -> Double {
            let rise = current - previous
            let fall = next - current
            guard rise * fall > 0 else { return 0 }
            let cap = 3 * min(abs(rise), abs(fall))
            return min(cap, max(-cap, (next - previous) / 2))
        }
        return Channels(
            first: slope(previous.first, current.first, next.first),
            second: slope(previous.second, current.second, next.second),
            third: slope(previous.third, current.third, next.third),
            alpha: slope(previous.alpha, current.alpha, next.alpha))
    }

    /// The colour at a point of the patch whose top-leading vertex is
    /// `(column, row)`: `across` it (its `u`, 0 at the leading edge) and `down`
    /// it (its `v`, 0 at the top).
    func colour(column: Int, row: Int, across: Double, down: Double) -> Color {
        let corners = (
            row * width + column, row * width + column + 1, (row + 1) * width + column, (row + 1) * width + column + 1
        )
        guard mixable[corners.0], mixable[corners.1], mixable[corners.2], mixable[corners.3] else {
            return heaviest(corners, across: across, down: down)
        }
        // Each corner's weight for its value (`h`) and, smooth, for its slopes
        // (`g`): the Hermite basis, or the bilinear one with no slope terms.
        let (hu0, hu1, gu0, gu1) = Self.basis(across, smooth: smooth)
        let (hv0, hv1, gv0, gv1) = Self.basis(down, smooth: smooth)
        var sum = values[corners.0] * (hu0 * hv0) + values[corners.1] * (hu1 * hv0)
        sum = sum + values[corners.2] * (hu0 * hv1) + values[corners.3] * (hu1 * hv1)
        if smooth {
            sum = sum + alongRow[corners.0] * (gu0 * hv0) + alongRow[corners.1] * (gu1 * hv0)
            sum = sum + alongRow[corners.2] * (gu0 * hv1) + alongRow[corners.3] * (gu1 * hv1)
            sum = sum + downColumn[corners.0] * (hu0 * gv0) + downColumn[corners.1] * (hu1 * gv0)
            sum = sum + downColumn[corners.2] * (hu0 * gv1) + downColumn[corners.3] * (hu1 * gv1)
        }
        return colour(from: sum)
    }

    /// The weights at `t`: the two ends' values and, smooth, their slopes.
    private static func basis(_ t: Double, smooth: Bool) -> (Double, Double, Double, Double) {
        guard smooth else { return (1 - t, t, 0, 0) }
        let square = t * t
        let cube = square * t
        return (1 - 3 * square + 2 * cube, 3 * square - 2 * cube, t - 2 * square + cube, cube - square)
    }

    /// A blended value back to a colour: unpremultiplied, out of its space,
    /// clamped to the gamut.
    private func colour(from value: Channels) -> Color {
        let alpha = min(1, max(0, value.alpha))
        guard alpha > 0 else { return .clear }
        let (first, second, third) = (value.first / alpha, value.second / alpha, value.third / alpha)
        var result: Color
        if perceptual {
            let rgb = Color.fromCubeRootLMS(long: first, medium: second, short: third)
            // The blend's own result: content, not a framework's ink.
            result = .rgb(rgb.red, rgb.green, rgb.blue)  // swiftlint:disable:this framework_colour_literal
        } else {
            func byte(_ component: Double) -> UInt8 { UInt8((min(1, max(0, component)) * 255).rounded()) }
            result = .rgb(byte(first), byte(second), byte(third))  // swiftlint:disable:this framework_colour_literal
        }
        result.alpha = UInt8((alpha * 255).rounded())
        return result
    }

    /// The corner that weighs most at the point, as spelled — the first of
    /// equals, in reading order.
    private func heaviest(_ corners: (Int, Int, Int, Int), across: Double, down: Double) -> Color {
        var best = (corners.0, (1 - across) * (1 - down))
        for candidate in [
            (corners.1, across * (1 - down)), (corners.2, (1 - across) * down), (corners.3, across * down),
        ]
        where candidate.1 > best.1 {
            best = candidate
        }
        return spelled[best.0]
    }
}
