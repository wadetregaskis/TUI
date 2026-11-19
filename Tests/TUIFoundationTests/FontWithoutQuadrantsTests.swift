//  🖥️ TUI — A Terminal UI framework for Swift
//  FontWithoutQuadrantsTests.swift
//
//  Where the terminal's font has no quadrants (the classic Windows console in
//  Consolas), nothing TUI draws of its own accord is built of them: a shape's
//  corners and a solid face are cut in whole cells, and a canvas at its
//  automatic grain draws half blocks, which the font has.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// `view` drawn in a `width` × `height` frame, as the screen would show it,
/// by a terminal whose font has the quadrants or not.
@MainActor
private func glyphs(_ view: some View, width: Int, height: Int, quadrants: Bool) -> [String] {
    var context = makeRenderContext(width: width, height: height)
    context.environment.fontHasQuadrants = quadrants
    return ColorDepth.withCurrent(.truecolor) { renderToScreen(view, context: context) }.lines.map(\.stripped)
}

/// The quadrants: every glyph cutting a cell in quarters that is not a half
/// block, a full block or a space.
private let quadrants = Set(TerminalSymbols.quadrants).subtracting([" ", "▀", "▄", "▌", "▐", "█"])

private func drawsQuadrants(_ rows: [String]) -> Bool {
    rows.joined().contains { quadrants.contains($0) }
}

private let downward = LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom)

@MainActor
@Suite("A font without quadrants")
struct FontWithoutQuadrantsTests {

    @Test("A rounded rectangle's and a capsule's corners are whole cells, not quadrants")
    func shapeCorners() {
        for shape in [AnyShape(RoundedRectangle(cornerRadius: 1)), AnyShape(RoundedRectangle(cornerRadius: 4)), AnyShape(Capsule())] {
            #expect(drawsQuadrants(glyphs(shape.fill(.blue), width: 10, height: 4, quadrants: true)))
            #expect(!drawsQuadrants(glyphs(shape.fill(.blue), width: 10, height: 4, quadrants: false)))
        }
    }

    @Test("A one-row capsule keeps its half-block caps, which the font has")
    func capsuleCaps() {
        #expect(glyphs(Capsule().fill(.blue), width: 6, height: 1, quadrants: false) == ["▐    ▌"])
    }

    @Test("A ramp down a rounded rectangle keeps its two samples a cell: the font has the half blocks")
    func halvesKept() {
        let rows = glyphs(RoundedRectangle(cornerRadius: 1).fill(downward), width: 6, height: 3, quadrants: false)
        #expect(rows[1] == "▄▄▄▄▄▄")
        #expect(!drawsQuadrants(rows))
    }

    @Test("A canvas at its automatic grain draws half blocks; one asked for in quadrants keeps them")
    func canvasGrain() {
        // In cells: a canvas the terminal could draw as a picture is one.
        let canvas = Canvas { context, size in
            context.fill(Circle().path(in: CGRect(origin: .zero, size: size)), with: .color(.blue))
        }.gradientGraphics(false)
        let automatic = glyphs(canvas, width: 8, height: 4, quadrants: false)
        #expect(automatic == glyphs(canvas.canvasGrain(.halfBlocks), width: 8, height: 4, quadrants: true))
        #expect(!drawsQuadrants(automatic))
        #expect(drawsQuadrants(glyphs(canvas, width: 8, height: 4, quadrants: true)))
        #expect(drawsQuadrants(glyphs(canvas.canvasGrain(.quadrants), width: 8, height: 4, quadrants: false)))
    }

    @Test("A three-row solid face is drawn in whole cells")
    func solidFace() {
        var environment = EnvironmentValues()
        #expect(SolidRaster(environment) != .wholeCells)
        environment.fontHasQuadrants = false
        #expect(SolidRaster(environment) == .wholeCells)
        #expect(BlockElementDrawing(environment).fillTheLine, "the half blocks still reach the line")
    }
}
