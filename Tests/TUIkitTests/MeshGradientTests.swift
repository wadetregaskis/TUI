//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MeshGradientTests.swift
//
//  `MeshGradient`'s values, and its colours at points SwiftUI drew. Every
//  expected colour here is a pixel SwiftUI rendered on macOS 15.8 for the same
//  mesh over the same grid of samples (an `ImageRenderer` at scale 1, read
//  back as sRGB bytes); the probes are in the session notes, not the
//  repository. SwiftUI tessellates its patches and TUIkit evaluates them at
//  each sample, so the two can differ by a level or two where a colour curves.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitStyling
@testable import TUIkitView

// MARK: - Helpers

/// An sRGB colour from components, as the probes spelled theirs.
private func srgb(_ red: Double, _ green: Double, _ blue: Double, _ opacity: Double = 1) -> Color {
    Color(red: red, green: green, blue: blue, opacity: opacity)
}

/// The vertices of a `width` × `height` grid spread evenly over the unit square.
private func regular(_ width: Int, _ height: Int) -> [SIMD2<Float>] {
    (0..<height).flatMap { (row: Int) -> [SIMD2<Float>] in
        (0..<width).map { (column: Int) -> SIMD2<Float> in
            SIMD2(Float(column) / Float(width - 1), Float(row) / Float(height - 1))
        }
    }
}

/// Colours that encode a vertex's place in the mesh: red its column, green
/// its row, each as a fraction of the last. Under bilinear blending a sample's
/// red and green ARE its place in the mesh, which is how the probes read
/// SwiftUI's geometry.
private func placeColours(_ width: Int, _ height: Int) -> [Color] {
    (0..<height).flatMap { row in
        (0..<width).map { column in srgb(Double(column) / Double(width - 1), Double(row) / Double(height - 1), 0) }
    }
}

private func meshPaint(_ mesh: MeshGradient) -> MeshPaint? {
    guard case .mesh(let paint) = mesh.paint(in: EnvironmentValues()) else { return nil }
    return paint
}

/// The colour `mesh` gives sample `(x, y)` of a `width` × `height` grid —
/// pixel `(x, y)` of the probe's picture.
private func sample(_ mesh: MeshGradient, _ width: Int, _ height: Int, at x: Int, _ y: Int) -> Color? {
    guard let paint = meshPaint(mesh) else { return nil }
    return MeshRaster(paint: paint, offset: .zero, extent: SIMD2(Double(width), Double(height)))
        .colours(columns: x..<(x + 1), rows: y..<(y + 1)).first
}

/// Whether `colour`'s components are each within `tolerance` of SwiftUI's.
private func near(_ colour: Color?, _ expected: (Int, Int, Int), tolerance: Int = 3) -> Bool {
    guard let rgb = colour?.rgbComponents else { return false }
    return abs(Int(rgb.red) - expected.0) <= tolerance && abs(Int(rgb.green) - expected.1) <= tolerance
        && abs(Int(rgb.blue) - expected.2) <= tolerance
}

private func describe(_ colour: Color?) -> String {
    guard let colour, let rgb = colour.rgbComponents else { return "no RGB" }
    return "(\(rgb.red), \(rgb.green), \(rgb.blue)) α\(colour.alpha)"
}

// MARK: - The value

@Suite("MeshGradient values")
struct MeshGradientValueTests {

    @Test("SwiftUI's defaults: a clear background, smooth colours, the device space")
    func defaults() {
        let mesh = MeshGradient(width: 2, height: 2, points: regular(2, 2), colors: [.red, .green, .blue, .white])
        #expect(mesh.background == .clear)
        #expect(mesh.smoothsColors)
        #expect(mesh.colorSpace == .device)
        #expect(mesh.width == 2 && mesh.height == 2)
    }

    @Test("locations and colors give back the form they were given in, and setting one form clears the other")
    func formsRoundTrip() {
        let point = MeshGradient.BezierPoint(
            position: [0, 0], leadingControlPoint: [0, 0], topControlPoint: [0, 0],
            trailingControlPoint: [0.3, 0], bottomControlPoint: [0, 0.3])
        let resolved = Color.Resolved(red: 1, green: 0, blue: 0)
        var mesh = MeshGradient(
            width: 1, height: 1, bezierPoints: [point], resolvedColors: [resolved])
        #expect(mesh.locations == .bezierPoints([point]))
        #expect(mesh.colors == .resolvedColors([resolved]))

        mesh.locations = .points([[0.5, 0.5]])
        mesh.colors = .colors([.blue])
        #expect(mesh.locations == .points([[0.5, 0.5]]))
        #expect(mesh.colors == .colors([.blue]))
        // Equal to a mesh built that way from the start: the other form's
        // storage was cleared, not left behind to make two equal meshes unequal.
        #expect(mesh == MeshGradient(width: 1, height: 1, points: [[0.5, 0.5]], colors: [.blue]))
    }

    /// SwiftUI's `locations` and `colors` are payload enums, which the per-pass
    /// memos' value hash cannot read: a view holding one is measured every time
    /// and kept nowhere. A mesh stores them as arrays and flags instead, so a
    /// mesh view — or a background holding one — is read whole.
    @MainActor
    @Test("The value hash reads a mesh whole, as a view and as a background")
    func memoReadsAMesh() {
        let plans = ValueHashPlans()
        #expect(plans.plan(for: MeshGradient.self).pointee.shape == .dense)
        #expect(plans.plan(for: BackgroundModifier<MeshGradient>.self).pointee.shape == .dense)
    }

    @Test("Resolved colours paint as the colours they resolve to")
    func resolvedColoursPaint() throws {
        let mesh = MeshGradient(
            width: 2, height: 2, points: regular(2, 2),
            resolvedColors: [Color.Resolved(red: 1, green: 0, blue: 0), .init(red: 0, green: 1, blue: 0),
                             .init(red: 0, green: 0, blue: 1), .init(red: 1, green: 1, blue: 1)])
        let paint = try #require(meshPaint(mesh))
        let painted: [Color] = [.rgb(255, 0, 0), .rgb(0, 255, 0), .rgb(0, 0, 255), .rgb(255, 255, 255)]
        #expect(paint.colors == painted)
    }
}

// MARK: - Colours, measured

@Suite("MeshGradient colours against SwiftUI")
struct MeshGradientColourTests {

    /// Black, red, green, yellow at the corners: red is the sample's `u`,
    /// green its `v`.
    private let corners = [srgb(0, 0, 0), srgb(1, 0, 0), srgb(0, 1, 0), srgb(1, 1, 0)]

    @Test("Without smoothing a patch blends its corners bilinearly")
    func bilinear() {
        let mesh = MeshGradient(width: 2, height: 2, points: regular(2, 2), colors: corners, smoothsColors: false)
        let left = sample(mesh, 201, 201, at: 20, 100)
        let top = sample(mesh, 201, 201, at: 180, 40)
        #expect(near(left, (26, 128, 0), tolerance: 1), "\(describe(left))")
        #expect(near(top, (229, 52, 0), tolerance: 1), "\(describe(top))")
    }

    @Test("Smoothed, one patch eases out of each corner: an edge vertex's slope is zero")
    func smoothOnePatch() {
        let mesh = MeshGradient(width: 2, height: 2, points: regular(2, 2), colors: corners)
        for (x, red) in [(20, 8), (60, 56), (140, 199)] {
            let colour = sample(mesh, 201, 201, at: x, 100)
            #expect(near(colour, (red, 128, 0), tolerance: 2), "x \(x): \(describe(colour))")
        }
    }

    /// One row of five vertices, red 0, 0.2, 1, 0.6, 0: an inner vertex's slope
    /// is half the difference of its neighbours (Catmull–Rom), the ends' zero,
    /// and the peak's zero. Bilinear would be 26 and 153 at the first two.
    @Test("Smoothed, a row follows Catmull-Rom slopes, flat at its ends and at a peak")
    func smoothRow() {
        let reds = [0.0, 0.2, 1, 0.6, 0].map { srgb($0, 0, 0) }
        let mesh = MeshGradient(width: 5, height: 2, points: regular(5, 2), colors: reds + reds)
        for (x, red) in [(50, 10), (100, 51), (150, 169), (250, 220), (350, 61)] {
            let colour = sample(mesh, 401, 21, at: x, 10)
            #expect(near(colour, (red, 0, 0)), "x \(x): \(describe(colour))")
        }
    }

    /// Red 0.5, 0.52, 0.9, 0.9, 0.5: the second vertex's Catmull-Rom slope
    /// would dip below 0.5 before it (125 at x 74) and is limited to three times
    /// its shallow side; the plateau's slopes are zero, where Catmull-Rom would
    /// bulge it to 242 at x 250.
    @Test("Smoothed, a slope is limited so a monotone run never overshoots")
    func monotoneLimits() {
        let r = [0.5, 0.52, 0.9, 0.9, 0.5]
        let g = [0.0, 0.5, 1, 0.5, 0]
        let b = [0.0, 0.1, 0.2, 0.6, 1.0]
        let row = (0..<5).map { srgb(r[$0], g[$0], b[$0]) }
        let mesh = MeshGradient(width: 5, height: 2, points: regular(5, 2), colors: row + row)
        let dip = sample(mesh, 401, 11, at: 74, 5)
        let plateau = sample(mesh, 401, 11, at: 250, 5)
        #expect(near(dip, (130, 89, 18)), "\(describe(dip))")
        #expect(near(plateau, (229, 208, 97)), "\(describe(plateau))")
    }

    @Test("Perceptual blends in OKLab: halfway from red to blue is a lighter purple than the device space's")
    func perceptualBilinear() {
        let colours = [srgb(1, 0, 0), srgb(0, 0, 1), srgb(1, 0, 0), srgb(0, 0, 1)]
        let perceptual = MeshGradient(
            width: 2, height: 2, points: regular(2, 2), colors: colours, smoothsColors: false, colorSpace: .perceptual)
        let device = MeshGradient(
            width: 2, height: 2, points: regular(2, 2), colors: colours, smoothsColors: false)
        #expect(near(sample(perceptual, 401, 21, at: 200, 10), (140, 83, 162)))
        #expect(near(sample(perceptual, 401, 21, at: 100, 10), (197, 73, 109)))
        #expect(near(sample(device, 401, 21, at: 200, 10), (127, 0, 127)))
    }

    /// Three colours along a row, smoothed in the perceptual space. Deciding
    /// the slopes in OKLab gives (187, 92, 52) at x 60; SwiftUI decides them in
    /// OKLab's cube-root cone space, the stage before its last matrix.
    @Test("Perceptual and smoothed, the slopes are decided per cone channel")
    func perceptualSmooth() {
        let hues = [srgb(0.8, 0.2, 0.2), srgb(0.2, 0.7, 0.2), srgb(0.2, 0.3, 0.9)]
        let perceptual = MeshGradient(
            width: 3, height: 2, points: regular(3, 2), colors: hues + hues, colorSpace: .perceptual)
        let device = MeshGradient(width: 3, height: 2, points: regular(3, 2), colors: hues + hues)
        let early = sample(perceptual, 401, 11, at: 60, 5)
        let late = sample(perceptual, 401, 11, at: 340, 5)
        #expect(near(early, (189, 92, 41)), "\(describe(early))")
        #expect(near(late, (33, 108, 205)), "\(describe(late))")
        #expect(near(sample(device, 401, 11, at: 60, 5), (170, 79, 51)))
        let onePatch = MeshGradient(
            width: 2, height: 2, points: regular(2, 2), colors: [srgb(1, 0, 0), srgb(0, 0, 1), srgb(1, 0, 0), srgb(0, 0, 1)],
            colorSpace: .perceptual)
        #expect(near(sample(onePatch, 401, 21, at: 100, 10), (219, 61, 84)))
    }

    @Test("Translucent colours blend premultiplied")
    func premultiplied() throws {
        let mesh = MeshGradient(
            width: 2, height: 2, points: regular(2, 2),
            colors: [srgb(1, 0, 0), srgb(0, 1, 0, 0.5), srgb(1, 0, 0), srgb(0, 1, 0, 0.5)], smoothsColors: false)
        let middle = try #require(sample(mesh, 101, 5, at: 50, 2))
        #expect(near(middle, (170, 85, 0), tolerance: 1), "\(describe(middle))")
        #expect(abs(Int(middle.alpha) - 191) <= 1, "\(describe(middle))")
        // Toward `.clear`, red stays red and fades: not a darker red.
        let fading = MeshGradient(
            width: 2, height: 2, points: regular(2, 2), colors: [srgb(1, 0, 0), .clear, srgb(1, 0, 0), .clear],
            smoothsColors: false)
        let half = try #require(sample(fading, 101, 5, at: 50, 2))
        #expect(near(half, (255, 0, 0), tolerance: 1) && abs(Int(half.alpha) - 128) <= 1, "\(describe(half))")
    }

    @Test("The background fills what the patches do not cover; by default it is clear")
    func background() throws {
        let inset: [SIMD2<Float>] = [[0.25, 0.25], [0.75, 0.25], [0.25, 0.75], [0.75, 0.75]]
        let blue = MeshGradient(width: 2, height: 2, points: inset, colors: corners, background: srgb(0, 0, 1))
        #expect(near(sample(blue, 201, 201, at: 10, 10), (0, 0, 255), tolerance: 0))
        #expect(near(sample(blue, 201, 201, at: 190, 100), (0, 0, 255), tolerance: 0))
        #expect(near(sample(blue, 201, 201, at: 100, 100), (128, 128, 0), tolerance: 1))
        let clear = MeshGradient(width: 2, height: 2, points: inset, colors: corners)
        #expect(try #require(sample(clear, 201, 201, at: 10, 10)).alpha == 0)
    }

    @Test("A mesh with the wrong number of points, or one vertex across, draws only its background")
    func malformed() {
        let short = MeshGradient(
            width: 3, height: 3, points: regular(2, 2), colors: corners, background: srgb(0, 0, 1))
        let thin = MeshGradient(
            width: 1, height: 2, points: [[0, 0], [0, 1]], colors: [srgb(1, 0, 0), srgb(0, 1, 0)],
            background: srgb(0, 0, 1))
        for mesh in [short, thin] {
            #expect(near(sample(mesh, 21, 21, at: 10, 10), (0, 0, 255), tolerance: 0))
        }
    }

    @Test("Too few colours: the vertices without one are clear")
    func missingColours() throws {
        let mesh = MeshGradient(width: 2, height: 2, points: regular(2, 2), colors: [srgb(1, 0, 0)])
        let middle = try #require(sample(mesh, 21, 21, at: 10, 10))
        #expect(near(middle, (255, 0, 0), tolerance: 1) && abs(Int(middle.alpha) - 64) <= 2, "\(describe(middle))")
    }
}

// MARK: - Geometry, measured

@Suite("MeshGradient geometry against SwiftUI")
struct MeshGradientGeometryTests {

    /// The middle vertex of a 3×3 mesh moved to (0.7, 0.3). Its control points
    /// lie on the line bisecting its two edges in each direction, a third of
    /// the way to each neighbour. Fitted to SwiftUI's picture, its leading
    /// control point is (0.457, 0.264); straight thirds would put it at
    /// (0.467, 0.367), and Catmull-Rom at (0.533, 0.3).
    @Test("An implied control point lies on the bisector, a third of the way to its neighbour")
    func impliedControlPoints() throws {
        var points = regular(3, 3)
        points[4] = [0.7, 0.3]
        let paint = try #require(meshPaint(MeshGradient(width: 3, height: 3, points: points, colors: placeColours(3, 3))))
        let vertices = try #require(MeshVertices(paint))
        let moved = vertices[1, 1]
        #expect(abs(moved.leading.x - 0.460) < 0.005 && abs(moved.leading.y - 0.263) < 0.005, "\(moved.leading)")
        // Down the column too: SwiftUI's fitted top control point is
        // (0.679, 0.186).
        #expect(abs(moved.top.x - 0.681) < 0.005 && abs(moved.top.y - 0.181) < 0.005, "\(moved.top)")
        // An edge vertex aims straight at its one neighbour.
        let edge = vertices[0, 1]
        #expect(abs(edge.trailing.x - 0.7 / 3) < 1e-6 && abs(edge.trailing.y - (0.5 - 0.2 / 3)) < 1e-6)
    }

    /// The same mesh, read the way the probe read SwiftUI's: with colours that
    /// encode each sample's place in the mesh, the colour IS the place.
    @Test("A warped mesh puts each sample where SwiftUI's does")
    func warpedSamples() {
        var points = regular(3, 3)
        points[4] = [0.7, 0.3]
        let mesh = MeshGradient(width: 3, height: 3, points: points, colors: placeColours(3, 3), smoothsColors: false)
        for (x, y, expected) in [
            (100, 60, (92, 123, 0)), (150, 40, (164, 78, 0)), (60, 150, (64, 204, 0)), (130, 100, (121, 163, 0)),
        ] {
            let colour = sample(mesh, 201, 201, at: x, y)
            #expect(near(colour, expected, tolerance: 4), "(\(x), \(y)): \(describe(colour))")
        }
    }

    /// One patch whose top edge bows down to y 0.375 at its middle: above the
    /// bow is outside the mesh.
    @Test("Explicit control points bend an edge, and what is outside it takes the background")
    func explicitBezierPoints() throws {
        func vertex(
            _ position: SIMD2<Float>, leading: SIMD2<Float>, top: SIMD2<Float>, trailing: SIMD2<Float>,
            bottom: SIMD2<Float>
        ) -> MeshGradient.BezierPoint {
            .init(
                position: position, leadingControlPoint: leading, topControlPoint: top,
                trailingControlPoint: trailing, bottomControlPoint: bottom)
        }
        let bow = [
            vertex([0, 0], leading: [0, 0], top: [0, 0], trailing: [0.33, 0.5], bottom: [0, 0.33]),
            vertex([1, 0], leading: [0.67, 0.5], top: [1, 0], trailing: [1, 0], bottom: [1, 0.33]),
            vertex([0, 1], leading: [0, 1], top: [0, 0.67], trailing: [0.33, 1], bottom: [0, 1]),
            vertex([1, 1], leading: [0.67, 1], top: [1, 0.67], trailing: [1, 1], bottom: [1, 1]),
        ]
        let mesh = MeshGradient(width: 2, height: 2, bezierPoints: bow, colors: placeColours(2, 2), smoothsColors: false)
        #expect(try #require(sample(mesh, 201, 201, at: 100, 30)).alpha == 0)
        #expect(try #require(sample(mesh, 201, 201, at: 100, 50)).alpha == 0)
        let inside = sample(mesh, 201, 201, at: 100, 100)
        #expect(near(inside, (128, 51, 0), tolerance: 3), "\(describe(inside))")
    }
}
