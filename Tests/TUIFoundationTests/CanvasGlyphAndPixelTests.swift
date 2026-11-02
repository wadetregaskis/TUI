//  🖥️ TUI — A Terminal UI framework for Swift
//  CanvasGlyphAndPixelTests.swift
//
//  A `Canvas`'s text and symbols, which are cells, and TUI's additions that
//  address its grid.
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
private let blue = Color.rgb(0, 0, 255)

@MainActor
@Suite("Canvas: glyphs and the pixel grid")
struct CanvasGlyphAndPixelTests {
    // MARK: Text and symbols

    @Test("Text lands on the cell its anchor says, and over pixels takes them as its field")
    func textOverPixels() {
        let canvas = Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(red))
            context.draw(Text(verbatim: "Hi"), at: CGPoint(x: 1, y: 2), anchor: .topLeading)
        }
        let buffer = canvasDrawn(canvas.canvasGrain(.quadrants), columns: 4, rows: 2)
        #expect(buffer.lines.map(\.stripped) == ["    ", " Hi "])
        let cell = paintedCells(buffer.lines[1])[1]
        #expect(cell.glyph == "H")
        #expect(cell.state.backgroundColour == .rgb(255, 0, 0))
    }

    @Test("Text centres on its point by default, and measures in units")
    func textMeasure() {
        var measured = CGSize.zero
        let canvas = Canvas { context, size in
            let resolved = context.resolve(Text(verbatim: "abcd"))
            measured = resolved.measure(in: size)
            context.draw(resolved, at: CGPoint(x: size.width / 2, y: size.height / 2))
        }
        let buffer = canvasDrawn(canvas, columns: 8, rows: 3)
        #expect(measured == CGSize(width: 4, height: 2), "a line is a row, two units")
        #expect(buffer.lines[1].stripped == "  abcd  ")
    }

    @Test("Text in a rectangle wraps to it")
    func textInRect() {
        let canvas = Canvas { context, _ in
            context.draw(Text(verbatim: "aa bb"), in: CGRect(x: 0, y: 0, width: 2, height: 4))
        }
        let buffer = canvasDrawn(canvas, columns: 4, rows: 2)
        #expect(buffer.lines.map(\.stripped) == ["aa  ", "bb  "])
    }

    @Test("A resolved text's shading is the colour it draws in")
    func textShading() {
        let canvas = Canvas { context, _ in
            var resolved = context.resolve(Text(verbatim: "x"))
            resolved.shading = .color(red)
            context.draw(resolved, at: .zero, anchor: .topLeading)
        }
        #expect(paintedCells(canvasDrawn(canvas).lines[0])[0].ink == .rgb(255, 0, 0))
    }

    @Test("A shape over most of a glyph's cell covers the glyph; a glyph drawn after it stays")
    func glyphsAndPixelsTakeTurns() {
        let canvas = Canvas { context, _ in
            context.draw(Text(verbatim: "ab"), at: .zero, anchor: .topLeading)
            context.fill(Path(CGRect(x: 1, y: 0, width: 1, height: 2)), with: .color(red))
            context.draw(Text(verbatim: "c"), at: CGPoint(x: 3, y: 0), anchor: .topLeading)
            context.fill(Path(CGRect(x: 3, y: 0, width: 0.25, height: 0.25)), with: .color(red))
        }
        let buffer = canvasDrawn(canvas.canvasGrain(.cells), columns: 4, rows: 1)
        #expect(buffer.lines[0].stripped == "a  c")
    }

    @Test("A clip keeps a glyph whole or not at all")
    func clipKeepsGlyphsWhole() {
        let canvas = Canvas { context, _ in
            context.clip(to: Path(CGRect(x: 0, y: 0, width: 1.75, height: 2)))
            context.draw(Text(verbatim: "abc"), at: .zero, anchor: .topLeading)
        }
        #expect(canvasDrawn(canvas, columns: 3, rows: 1).lines[0].stripped == "ab ")
    }

    @Test("A glyph drawn in a layer takes the opacity the layer lands at, and stays on top of it")
    func glyphInALayer() {
        var regions: [OpacityRegion] = []
        let canvas = Canvas { context, _ in
            context.opacity = 0.5
            context.drawLayer { layer in
                layer.fill(Path(CGRect(x: 0, y: 0, width: 2, height: 2)), with: .color(red))
                layer.draw(Text(verbatim: "a"), at: .zero, anchor: .topLeading)
            }
        }
        let buffer = canvasDrawn(canvas.canvasGrain(.cells), columns: 2, rows: 1)
        regions = buffer.opacityRegions
        #expect(buffer.lines[0].stripped.hasPrefix("a"))
        #expect(regions.contains { $0.offsetX == 0 && $0.opacity == 0.5 })
    }

    @Test("A symbol is found by its tag, sized as its view, and drawn where it is asked")
    func symbols() {
        var size = CGSize.zero
        var missing: GraphicsContext.ResolvedSymbol?
        let canvas = Canvas { context, _ in
            missing = context.resolveSymbol(id: "nothing")
            guard let symbol = context.resolveSymbol(id: "dot") else { return }
            size = symbol.size
            context.draw(symbol, at: CGPoint(x: 3, y: 2), anchor: .topLeading)
            context.draw(symbol, at: .zero, anchor: .topLeading)
        } symbols: {
            Text(verbatim: "other").tag("other")
            Text(verbatim: "••").tag("dot")
        }
        let buffer = canvasDrawn(canvas, columns: 6, rows: 2)
        #expect(missing == nil)
        #expect(size == CGSize(width: 2, height: 2))
        #expect(buffer.lines.map(\.stripped) == ["••    ", "   •• "])
    }

    @Test("A foreach's rows are symbols by their elements' ids")
    func symbolsFromForEach() {
        let canvas = Canvas { context, _ in
            guard let symbol = context.resolveSymbol(id: 2) else { return }
            context.draw(symbol, at: .zero, anchor: .topLeading)
        } symbols: {
            ForEach(1..<4, id: \.self) { Text(verbatim: "\($0)") }
        }
        #expect(canvasDrawn(canvas, columns: 1, rows: 1).lines[0].stripped == "2")
    }

    // MARK: A text renderer's context

    @Test("A text renderer can paint too, in cells' units, beneath its glyphs")
    func textRendererFill() {
        struct Underlay: TextRenderer {
            func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
                ctx.fill(Path(CGRect(x: 0, y: 0, width: 1, height: 1)), with: .color(.rgb(255, 0, 0)))
                for line in layout { ctx.draw(line) }
            }
        }
        let buffer = canvasDrawn(Text(verbatim: "ab").textRenderer(Underlay()), columns: 2, rows: 1)
        #expect(buffer.lines[0].stripped == "ab")
        #expect(paintedCells(buffer.lines[0])[0].state.backgroundColour == .rgb(255, 0, 0))
        #expect(paintedCells(buffer.lines[0])[1].state.backgroundColour == nil)
    }

    // MARK: TUI's additions

    @Test("The pixel grid is the grain's")
    func pixelGrid() {
        func grid(_ grain: CanvasGrain) -> (Int, Int) {
            var seen = (0, 0)
            _ = canvasSurface(columns: 3, rows: 2, grain: grain) { context, _ in seen = context.pixelGrid }
            return seen
        }
        #expect(grid(.cells) == (3, 2))
        #expect(grid(.halfBlocks) == (3, 4))
        #expect(grid(.quadrants) == (6, 4))
        #expect(grid(.sextants) == (6, 6))
        #expect(grid(.octants) == (6, 8))
        #expect(grid(.braille) == (6, 8))
    }

    @Test("setPixel sets exactly one, past the transform, and off the grid is nothing")
    func setPixel() {
        let drawn = canvasSurface(columns: 2, rows: 1) { context, _ in
            context.translateBy(x: 1, y: 0)
            context.setPixel(x: 2, y: 1, to: red)
            context.setPixel(x: -1, y: 0, to: red)
            context.setPixel(x: 99, y: 0, to: red)
        }
        #expect(canvasLetters(drawn) == ["....", "..R."])
    }

    @Test("setPixel honours the clip")
    func setPixelClipped() {
        let drawn = canvasSurface(columns: 2, rows: 1) { context, _ in
            context.clip(to: Path(CGRect(x: 0, y: 0, width: 1, height: 2)))
            context.setPixel(x: 0, y: 0, to: red)
            context.setPixel(x: 3, y: 0, to: red)
        }
        #expect(canvasLetters(drawn)[0] == "R...")
    }

    @Test("drawLine is one pixel a step, sharp, its end included")
    func drawLine() {
        let drawn = canvasSurface(columns: 2, rows: 2) { context, _ in
            // Pixels are half a unit across and a unit down.
            context.drawLine(from: CGPoint(x: 0.25, y: 0.5), to: CGPoint(x: 1.75, y: 3.5), with: .color(red))
        }
        #expect(canvasLetters(drawn) == ["R...", ".R..", "..R.", "...R"])
    }

    @Test("drawPixels fills its rectangle with sharp blocks")
    func drawPixels() {
        let drawn = canvasSurface(columns: 2, rows: 1) { context, size in
            context.drawPixels([red, blue], width: 2, height: 1, in: CGRect(origin: .zero, size: size))
            context.drawPixels([red], width: 2, height: 1, in: CGRect(origin: .zero, size: size))
        }
        #expect(canvasLetters(drawn) == ["RRBB", "RRBB"], "and a count that does not fit draws nothing")
    }

    @Test("setCell writes a whole cell, with its colours")
    func setCell() {
        let canvas = Canvas { context, _ in
            context.setCell(column: 1, row: 0, to: "┼", foreground: red, background: blue)
            context.setCell(column: 99, row: 0, to: "x")
        }
        let buffer = canvasDrawn(canvas, columns: 3, rows: 1)
        #expect(buffer.lines[0].stripped == " ┼ ")
        let cell = paintedCells(buffer.lines[0])[1]
        #expect(cell.ink == .rgb(255, 0, 0) && cell.state.backgroundColour == .rgb(0, 0, 255))
    }

    // MARK: Whatever it is asked

    @Test("Far-off and non-finite coordinates draw nothing, and do not trap")
    func extremes() {
        let huge = CGFloat.greatestFiniteMagnitude
        let drawn = canvasSurface { context, size in
            context.fill(Path(CGRect(x: huge, y: huge, width: 1, height: 1)), with: .color(red))
            context.stroke(Path { $0.move(to: .zero); $0.addLine(to: CGPoint(x: huge, y: CGFloat.nan)) }, with: .color(red))
            context.drawLine(from: CGPoint(x: CGFloat.nan, y: 0), to: CGPoint(x: huge, y: huge), with: .color(red))
            context.draw(Text(verbatim: "a"), at: CGPoint(x: huge, y: CGFloat.nan))
            context.drawPixels([red], width: 1, height: 1, in: CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1))
            context.scaleBy(x: 0, y: 0)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [red, blue]), startPoint: .zero, endPoint: .zero))
        }
        _ = drawn.pixelCells(monochrome: false)
    }

    @Test("A canvas with no room draws nothing")
    func noRoom() {
        var runs = 0
        let buffer = canvasDrawn(Canvas { _, _ in runs += 1 }, columns: 0, rows: 3)
        #expect(runs == 0)
        #expect(buffer.lines.isEmpty)
    }
}
