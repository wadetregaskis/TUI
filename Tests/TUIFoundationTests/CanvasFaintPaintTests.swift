//  🖥️ TUI — A Terminal UI framework for Swift
//  CanvasFaintPaintTests.swift
//
//  A see-through paint over a `Canvas`'s glyphs: it covers a glyph by how much
//  of the cell it hides, its share times its alpha and opacity, not by its
//  shape alone (hunt H-47, LEAF-5).
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
@testable import TUIStyling
@testable import TUITestSupport

private let red = Color.rgb(255, 0, 0)

@MainActor
@Suite("Canvas: a faint paint over a glyph")
struct CanvasFaintPaintTests {
    /// Whether the glyph drawn at the origin is still on a surface on which
    /// `paint` then drew over its cell.
    private func glyphSurvives(grain: CanvasGrain = .quadrants, _ paint: (inout GraphicsContext) -> Void) -> Bool {
        let surface = canvasSurface(columns: 2, rows: 1, grain: grain) { context, _ in
            context.draw(Text(verbatim: "a"), at: .zero, anchor: .topLeading)
            paint(&context)
        }
        return surface.rows[0]?[0]?.character == "a"
    }

    private static let cell = Path(CGRect(x: 0, y: 0, width: 1, height: 2))

    @Test("A fill at opacity 0 or 0.1 leaves the glyph; at 0.6 it covers it", arguments: [(0.0, true), (0.1, true), (0.6, false)])
    func opacity(opacity: Double, survives: Bool) {
        #expect(glyphSurvives { context in
            context.opacity = opacity
            context.fill(Self.cell, with: .color(red))
        } == survives)
    }

    @Test("A translucent colour covers by its alpha", arguments: [(0.2, true), (0.8, false)])
    func colourAlpha(alpha: Double, survives: Bool) {
        #expect(glyphSurvives { context in context.fill(Self.cell, with: .color(red.opacity(alpha))) } == survives)
    }

    @Test("Share, alpha and opacity multiply: an opaque fill over 3/4 of the cell at opacity 0.6 hides less than half")
    func shareTimesOpacity() {
        #expect(glyphSurvives(grain: .cells) { context in
            context.opacity = 0.6
            context.fill(Path(CGRect(x: 0, y: 0, width: 0.75, height: 2)), with: .color(red))
        })
        #expect(!glyphSurvives(grain: .cells) { context in
            context.fill(Path(CGRect(x: 0, y: 0, width: 0.75, height: 2)), with: .color(red))
        })
    }

    @Test("A gradient covers by its alpha where the glyph is")
    func gradientAlpha() {
        let fading = Gradient(colors: [red.opacity(0.1), red.opacity(0.1)])
        #expect(glyphSurvives { context in
            context.fill(Self.cell, with: .linearGradient(fading, startPoint: .zero, endPoint: CGPoint(x: 1, y: 0)))
        })
    }

    @Test("A filtered paint and a layer cover by the same rule")
    func filteredAndLayered() {
        #expect(glyphSurvives { context in
            context.opacity = 0.1
            context.addFilter(.blur(radius: 0.1))
            context.fill(Self.cell, with: .color(red))
        })
        #expect(glyphSurvives { context in
            context.opacity = 0.1
            context.drawLayer { layer in layer.fill(Self.cell, with: .color(red)) }
        })
        #expect(!glyphSurvives { context in
            context.drawLayer { layer in layer.fill(Self.cell, with: .color(red)) }
        })
    }

    @Test("The glyph a faint fill leaves keeps its ink and takes the fill as its field")
    func keptGlyphTakesTheField() {
        let canvas = Canvas { context, _ in
            context.draw(Text(verbatim: "a").foregroundStyle(Color.rgb(0, 0, 255)), at: .zero, anchor: .topLeading)
            context.opacity = 0.2
            context.fill(Path(CGRect(x: 0, y: 0, width: 2, height: 2)), with: .color(red))
        }
        let buffer = canvasDrawn(canvas.canvasGrain(.cells), columns: 2, rows: 1)
        let cell = paintedCells(buffer.lines[0])[0]
        #expect(cell.glyph == "a")
        #expect(cell.ink == .rgb(0, 0, 255), "the ink is not tinted: a cell is a glyph or pixels")
        #expect(cell.state.backgroundColour != nil, "the faint fill is its field")
    }
}
