//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MeshGradientRenderingTests.swift
//
//  A `MeshGradient` reaching the screen: as a view, as a foreground, as a
//  background, and through the paint's own transformations.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

import TUIkit
@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitStyling
@testable import TUIkitTestSupport

@MainActor
@Suite("MeshGradient rendering")
struct MeshGradientRenderingTests {

    private func context(width: Int, height: Int) -> RenderContext {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.palette = SystemPalette.green
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        return RenderContext(
            availableWidth: width, availableHeight: height, environment: environment, tuiContext: tui)
    }

    /// Each visible cell's truecolor component from escapes introduced by
    /// `prefix` (`"48;2;"` the background, `"38;2;"` the foreground), `nil`
    /// where none is in force.
    private func cells(_ line: String, prefix: String) -> [(Int, Int, Int)?] {
        var out: [(Int, Int, Int)?] = []
        var current: (Int, Int, Int)?
        var rest = Substring(line)
        while let escape = rest.firstIndex(of: "\u{1B}") {
            for character in rest[rest.startIndex..<escape] {
                out.append(contentsOf: repeatElement(current, count: character.terminalWidth))
            }
            rest = rest[escape...]
            guard let end = rest.firstIndex(of: "m") else { break }
            let body = rest[rest.index(rest.startIndex, offsetBy: 2)..<end]
            if let range = body.range(of: prefix) {
                let parts = body[range.upperBound...].split(separator: ";").prefix(3).compactMap { Int($0) }
                if parts.count == 3 { current = (parts[0], parts[1], parts[2]) }
            } else if body == "0" {
                current = nil
            }
            rest = rest[rest.index(after: end)...]
        }
        for character in rest {
            out.append(contentsOf: repeatElement(current, count: character.terminalWidth))
        }
        return out
    }

    private func near(_ cell: (Int, Int, Int)?, _ expected: (Int, Int, Int), tolerance: Int = 3) -> Bool {
        guard let cell else { return false }
        return abs(cell.0 - expected.0) <= tolerance && abs(cell.1 - expected.1) <= tolerance
            && abs(cell.2 - expected.2) <= tolerance
    }

    private static let unit3x3: [SIMD2<Float>] = [
        [0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.5, 0.5], [1, 0.5], [0, 1], [0.5, 1], [1, 1],
    ]

    /// SwiftUI's own example from the type's documentation, in the colours its
    /// named colours resolved to on macOS 15.8 — TUIkit's `.red` is the
    /// terminal's red, not the system's.
    private static let documentationExample = MeshGradient(
        width: 3, height: 3, points: unit3x3,
        colors: [
            Color(red: 1, green: 0.231, blue: 0.188), Color(red: 0.686, green: 0.322, blue: 0.871),
            Color(red: 0.345, green: 0.337, blue: 0.839), Color(red: 1, green: 0.584, blue: 0),
            Color(red: 1, green: 1, blue: 1), Color(red: 0, green: 0.478, blue: 1),
            Color(red: 1, green: 0.8, blue: 0), Color(red: 0.157, green: 0.804, blue: 0.255),
            Color(red: 0, green: 0.780, blue: 0.745),
        ])

    /// SwiftUI drew the documentation's example at 400 × 200 points; each 20 ×
    /// 20 square is one cell of a 20 × 10 grid, and its centre pixel is what
    /// the cell's centre should be.
    @Test("A mesh used as a view fills each cell with the colour SwiftUI draws at its centre")
    func viewMatchesSwiftUI() {
        withColorDepth(.truecolor) {
            let lines = renderToBuffer(
                Self.documentationExample.frame(width: 20, height: 10), context: context(width: 20, height: 10)
            ).lines
            #expect(lines.count == 10)
            let grid = lines.map { cells($0, prefix: "48;2;") }
            for (column, row, expected) in [
                (0, 0, (254, 61, 48)), (9, 0, (181, 87, 223)), (10, 5, (245, 252, 249)), (19, 9, (0, 197, 191)),
                (5, 2, (238, 137, 149)),
            ] {
                let cell = grid[row].count > column ? grid[row][column] : nil
                #expect(near(cell, expected), "cell (\(column), \(row)): \(String(describing: cell))")
            }
        }
    }

    @Test("As a foreground, a mesh colours each character with the cell it sits in")
    func foreground() {
        withColorDepth(.truecolor) {
            let mesh = MeshGradient(
                width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]],
                colors: [.rgb(255, 0, 0), .rgb(0, 0, 255), .rgb(255, 0, 0), .rgb(0, 0, 255)],
                smoothsColors: false)
            let lines = renderToBuffer(
                Text(verbatim: "abcdefghij").foregroundStyle(mesh), context: context(width: 10, height: 1)
            ).lines
            let inks = cells(lines[0], prefix: "38;2;")
            #expect(inks.count == 10)
            // Bilinear across the row: cell i's centre is (i + ½) / 10 of the way.
            for (column, ink) in inks.enumerated() {
                let blue = Int((Double(column) + 0.5) / 10 * 255 + 0.5)
                #expect(near(ink, (255 - blue, 0, blue), tolerance: 1), "column \(column): \(String(describing: ink))")
            }
        }
    }

    @Test("Behind text, a mesh fills every cell of the block, the text's included")
    func background() {
        withColorDepth(.truecolor) {
            let mesh = MeshGradient(
                width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]],
                colors: [.rgb(0, 0, 0), .rgb(0, 0, 0), .rgb(0, 255, 0), .rgb(0, 255, 0)],
                smoothsColors: false)
            let lines = renderToBuffer(
                Text(verbatim: "ab\ncd").background(mesh), context: context(width: 2, height: 2)
            ).lines
            let top = cells(lines[0], prefix: "48;2;")
            let bottom = cells(lines[1], prefix: "48;2;")
            #expect(top.count == 2 && bottom.count == 2)
            #expect(top.allSatisfy { near($0, (0, 64, 0), tolerance: 1) }, "\(top)")
            #expect(bottom.allSatisfy { near($0, (0, 191, 0), tolerance: 1) }, "\(bottom)")
        }
    }

    @Test(".in(_:) resolves the mesh over a fixed rectangle, anchored at the view")
    func fixedExtent() throws {
        let mesh = MeshGradient(
            width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]],
            colors: [.rgb(255, 0, 0), .rgb(0, 0, 255), .rgb(255, 0, 0), .rgb(0, 0, 255)], smoothsColors: false)
        guard case .mesh(let paint) = mesh.in(CellRect(x: 0, y: 0, width: 4, height: 1)).paint(in: EnvironmentValues())
        else {
            Issue.record("not a mesh")
            return
        }
        #expect(paint.extent == CellSize(width: 4, height: 1))
        // Over ten cells, the mesh is done by the fourth: the rest is its edge.
        let sampler = try #require(
            RampSampler(
                paint: .mesh(paint), extent: GradientFrame(width: 10, height: 1), depth: .truecolor, cellAspect: 2))
        let term = sampler.rowTerm(0)
        let entries = (0..<10).map { sampler.entry(column: $0, rowTerm: term) }
        #expect(sampler.ramp[entries[3]].rgbComponents?.blue ?? 0 > 200)
        #expect(Set(entries[3...]).count == 1, "past its extent the mesh did not hold its edge: \(entries)")
    }

    @Test("Faded, every vertex and the background fade with it")
    func faded() throws {
        let mesh = MeshGradient(
            width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]],
            colors: [.rgb(255, 0, 0), .rgb(0, 0, 255), .rgb(255, 0, 0), .rgb(0, 0, 255)],
            background: .rgb(0, 255, 0))
        guard case .mesh(let paint) = mesh.opacity(0.5).paint(in: EnvironmentValues()) else {
            Issue.record("not a mesh")
            return
        }
        #expect(paint.colors.allSatisfy { $0.alpha == 128 }, "\(paint.colors.map(\.alpha))")
        #expect(paint.background.alpha == 128)
    }

    @Test("A mesh stands in as the colour at its middle, and is opaque only where it certainly covers its box")
    func representativeAndOpacity() throws {
        guard case .mesh(let paint) = Self.documentationExample.paint(in: EnvironmentValues()) else {
            Issue.record("not a mesh")
            return
        }
        #expect(Paint.mesh(paint).representative == Color.rgb(255, 255, 255), "the middle vertex is white")
        #expect(paint.isOpaqueThroughout, "a clear background behind a mesh that covers its box shows nowhere")

        var inset = paint
        inset.locations = .points([[0.25, 0.25], [0.75, 0.25], [0.25, 0.75], [0.75, 0.75]])
        inset.width = 2
        inset.height = 2
        inset.colors = Array(paint.colors.prefix(4))
        #expect(!inset.isOpaqueThroughout, "a clear background shows round an inset mesh")
        inset.background = .rgb(0, 0, 0)
        #expect(inset.isOpaqueThroughout)

        var translucent = paint
        translucent.colors[4] = translucent.colors[4].opacity(0.5)
        #expect(!translucent.isOpaqueThroughout)
    }

    /// A warped mesh goes through subdivision, not the grid's two divisions.
    /// Its pieces meet at slightly different chords of the same curves; every
    /// cell inside the mesh has to be claimed by one of them.
    @Test("A warped mesh leaves no cell inside it uncovered")
    func warpedMeshCoversEveryCell() throws {
        var points = Self.unit3x3
        points[4] = [0.7, 0.3]
        let mesh = MeshGradient(
            width: 3, height: 3, points: points,
            colors: Array(repeating: Color.rgb(200, 200, 200), count: 9), background: .rgb(0, 0, 255))
        guard case .mesh(let paint) = mesh.paint(in: EnvironmentValues()) else {
            Issue.record("not a mesh")
            return
        }
        for (width, height) in [(80, 24), (37, 11), (300, 150)] {
            let colours = MeshRaster(paint: paint, offset: .zero, extent: SIMD2(Double(width), Double(height)))
                .colours(columns: 0..<width, rows: 0..<height)
            let holes = colours.filter { $0 == Color.rgb(0, 0, 255) }.count
            #expect(holes == 0, "\(holes) of \(width) × \(height) samples fell through")
        }
    }

    /// The same rectangles reached both ways: a grid mesh takes two divisions
    /// a sample, and the same mesh nudged off the grid by a millionth goes
    /// through subdivision. They must agree.
    @Test("The grid's fast path and subdivision agree")
    func fastPathMatchesSubdivision() throws {
        let colours: [Color] = [
            .rgb(0, 255, 0), .rgb(28, 235, 70), .rgb(56, 215, 140), .rgb(84, 195, 210), .rgb(112, 175, 24),
            .rgb(140, 155, 94), .rgb(168, 135, 164), .rgb(196, 115, 234), .rgb(224, 95, 48),
        ]
        let grid = MeshGradient(width: 3, height: 3, points: Self.unit3x3, colors: colours)
        var nudged = Self.unit3x3
        nudged[4] = [0.500001, 0.5]
        let warped = MeshGradient(width: 3, height: 3, points: nudged, colors: colours)
        guard case .mesh(let gridPaint) = grid.paint(in: EnvironmentValues()),
            case .mesh(let warpedPaint) = warped.paint(in: EnvironmentValues())
        else {
            Issue.record("not a mesh")
            return
        }
        #expect(MeshVertices(gridPaint)?.rectilinear != nil)
        #expect(MeshVertices(warpedPaint)?.rectilinear == nil)
        let size = SIMD2(40.0, 12.0)
        let fast = MeshRaster(paint: gridPaint, offset: .zero, extent: size).colours(columns: 0..<40, rows: 0..<12)
        let slow = MeshRaster(paint: warpedPaint, offset: .zero, extent: size).colours(columns: 0..<40, rows: 0..<12)
        for (a, b) in zip(fast, slow) {
            let (x, y) = (try #require(a.rgbComponents), try #require(b.rgbComponents))
            #expect(abs(Int(x.red) - Int(y.red)) <= 1 && abs(Int(x.green) - Int(y.green)) <= 1
                && abs(Int(x.blue) - Int(y.blue)) <= 1, "\(x) vs \(y)")
        }
    }

    @Test("At 256 colours a mesh's cells are the palette's entries")
    func palette256() {
        withColorDepth(.palette256) {
            let lines = renderToBuffer(
                Self.documentationExample.frame(width: 20, height: 10), context: context(width: 20, height: 10)
            ).lines
            #expect(lines.allSatisfy { !$0.contains("48;2;") })
            #expect(lines.contains { $0.contains("48;5;") })
        }
    }

    /// A `Table`'s ramp runs over every row of its data and is asked only about
    /// the rows on screen; a mesh there is worked out a band at a time.
    @Test("A mesh down a tall extent is worked out only where it is asked about")
    func tallExtentIsLazy() throws {
        let mesh = MeshGradient(
            width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]],
            colors: [.rgb(0, 0, 0), .rgb(0, 0, 0), .rgb(255, 255, 255), .rgb(255, 255, 255)], smoothsColors: false)
        let sampler = try #require(
            RampSampler(
                paint: mesh.paint(in: EnvironmentValues()), extent: GradientFrame(width: 80, height: 1_000_000),
                depth: .truecolor, cellAspect: 2))
        let row = 750_000
        let entry = sampler.entry(column: 3, rowTerm: sampler.rowTerm(row))
        #expect(sampler.ramp[entry].rgbComponents?.red == 191)
        #expect(sampler.ramp.count <= MeshCells.bandRows, "more than one band was worked out")
    }
}
