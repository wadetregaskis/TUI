//  🖥️ TUI — A Terminal UI framework for Swift
//  CanvasLabelsOverFillsTests.swift
//
//  A `Canvas`'s text over its fills, as a treemap draws its names: which
//  glyph wins a cell, where a label is cut at the canvas's edge, wide glyphs,
//  and labels over every pixel grain. The glyphs are laid over the pixels'
//  cells a run at a time, in place; these pin that the result is what folding
//  each run through the copying composite gave, cell for cell.
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
private let green = Color.rgb(0, 160, 0)

@MainActor
@Suite("Canvas: labels over fills")
struct CanvasLabelsOverFillsTests {
    /// `surface`'s glyphs laid over `base` a run at a time through the copying
    /// composite, `FrameBuffer.composited(with:at:)`: what
    /// `Surface.glyphs(over:)` drew before it composited in place, kept here as
    /// the oracle it must still agree with.
    private func foldedRuns(of surface: GraphicsContext.Surface, over base: FrameBuffer) -> FrameBuffer {
        var result = base
        for (row, cells) in surface.rows.sorted(by: { $0.key < $1.key }) {
            var column = cells.keys.min() ?? 0
            let last = cells.keys.max() ?? -1
            while column <= last {
                guard cells[column] != nil else {
                    column += 1
                    continue
                }
                var end = column
                while let cell = cells[end] { end += cell.width }
                let run = surface.buffer(covering: (minX: column, minY: row, maxX: end, maxY: row + 1))
                result = result.composited(with: run, at: (x: column, y: row))
                column = end
            }
        }
        return result
    }

    /// A treemap in little: tiles of three colours, labels on them, one label
    /// over two tiles, one written over another, one past the right edge, wide
    /// glyphs, one at the edge, and a fill drawn over part of a label.
    private func drawMap(_ context: inout GraphicsContext, _ size: CGSize) {
        let colours = [red, blue, green]
        for index in 0..<12 {
            let rect = CGRect(x: CGFloat(index % 4) * 4, y: CGFloat(index / 4) * 2, width: 4, height: 2)
            context.fill(Path(rect.insetBy(dx: 0.25, dy: 0.25)), with: .color(colours[index % 3]))
        }
        context.draw(Text(verbatim: "alpha"), at: CGPoint(x: 1, y: 0), anchor: .topLeading)
        context.draw(Text(verbatim: "BE"), at: CGPoint(x: 2, y: 0), anchor: .topLeading)
        context.draw(Text(verbatim: "over the edge"), at: CGPoint(x: 11, y: 2), anchor: .topLeading)
        context.draw(Text(verbatim: "日本"), at: CGPoint(x: 5, y: 4), anchor: .topLeading)
        context.draw(Text(verbatim: "語"), at: CGPoint(x: 14, y: 4), anchor: .topLeading)
        context.draw(Text(verbatim: "gamma").foregroundStyle(.white), at: CGPoint(x: 0, y: 2), anchor: .topLeading)
        context.fill(Path(CGRect(x: 2, y: 2, width: 1, height: 2)), with: .color(blue))
    }

    @Test(
        "Labels over fills draw what folding each run through the copying composite drew, at every grain",
        arguments: [CanvasGrain.cells, .halfBlocks, .quadrants, .sextants, .octants, .braille])
    func matchesTheFold(grain: CanvasGrain) {
        let surface = canvasSurface(columns: 16, rows: 3, grain: grain) { context, size in drawMap(&context, size) }
        let base = surface.pixelCells(monochrome: false).buffer()
        let drawn = surface.glyphs(over: base)
        let folded = foldedRuns(of: surface, over: base)
        #expect(drawn == folded)
        #expect(drawn.linesAreUniformWidth, "every row one width, as the in-place composite keeps them")
        #expect(drawn.width == 16, "no glyph past the canvas's right edge")
        #expect(drawn.lines.count == 3)
        #expect(drawn.lines.allSatisfy { $0.strippedLength == 16 })
    }

    @Test("A label is cut at the canvas's right edge, and a wide glyph that would cross it is not drawn")
    func clippedAtTheEdge() {
        let canvas = Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(green))
            context.draw(Text(verbatim: "abcdef"), at: CGPoint(x: 3, y: 0), anchor: .topLeading)
            context.draw(Text(verbatim: "x日"), at: CGPoint(x: 4, y: 2), anchor: .topLeading)
        }
        let buffer = canvasDrawn(canvas.canvasGrain(.halfBlocks), columns: 6, rows: 2)
        #expect(buffer.width == 6)
        #expect(buffer.lines.map(\.strippedLength) == [6, 6])
        #expect(buffer.lines[0].stripped == "   abc")
        #expect(buffer.lines[1].stripped == "    x ")
        #expect(paintedCells(buffer.lines[1])[5].state.backgroundColour == .rgb(0, 160, 0), "the fill, where 日 was not drawn")
    }

    @Test("A glyph whose origin is on the canvas's right or bottom edge is not drawn")
    func originOnTheEdge() {
        let surface = canvasSurface(columns: 4, rows: 2) { context, size in
            context.draw(Text(verbatim: "r"), at: CGPoint(x: size.width, y: 0), anchor: .topLeading)
            context.draw(Text(verbatim: "b"), at: CGPoint(x: 0, y: size.height), anchor: .topLeading)
            context.draw(Text(verbatim: "日"), at: CGPoint(x: size.width - 1, y: 2), anchor: .topLeading)
            context.draw(Text(verbatim: "ok"), at: CGPoint(x: 2, y: 2), anchor: .topLeading)
        }
        #expect(surface.rows.keys.sorted() == [1])
        #expect(surface.rows[1]?.keys.sorted() == [2, 3])
    }

    @Test("Labels over a clear canvas draw what the fold drew, its blank cells left blank")
    func matchesTheFoldOverNothing() {
        let surface = canvasSurface(columns: 16, rows: 3) { context, _ in
            context.draw(Text(verbatim: "one"), at: .zero, anchor: .topLeading)
            context.draw(Text(verbatim: "日本 two"), at: CGPoint(x: 9, y: 2), anchor: .topLeading)
            var faded = context
            faded.opacity = 0.5
            faded.draw(Text(verbatim: "three"), at: CGPoint(x: 4, y: 4), anchor: .topLeading)
        }
        let base = ShapeCells(width: 16, height: 3).buffer()
        let drawn = surface.glyphs(over: base)
        #expect(drawn == foldedRuns(of: surface, over: base))
        #expect(!drawn.opacityRegions.isEmpty, "the faded label's claim is kept")
    }

    @Test("A label written over another wins the cells they share, and keeps each tile's field")
    func laterLabelWins() {
        let canvas = Canvas { context, _ in
            context.fill(Path(CGRect(x: 0, y: 0, width: 3, height: 2)), with: .color(red))
            context.fill(Path(CGRect(x: 3, y: 0, width: 3, height: 2)), with: .color(blue))
            context.draw(Text(verbatim: "aaaaa"), at: .zero, anchor: .topLeading)
            context.draw(Text(verbatim: "BB"), at: CGPoint(x: 2, y: 0), anchor: .topLeading)
        }
        let buffer = canvasDrawn(canvas.canvasGrain(.quadrants), columns: 6, rows: 1)
        #expect(buffer.lines.map(\.stripped) == ["aaBBa "])
        let cells = paintedCells(buffer.lines[0])
        #expect(cells[2].state.backgroundColour == .rgb(255, 0, 0), "B over the red tile")
        #expect(cells[3].state.backgroundColour == .rgb(0, 0, 255), "B over the blue tile")
    }

    @Test("A wide glyph over a fill covers two cells and takes the fill as its field")
    func wideGlyphOverFill() {
        let canvas = Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(red))
            context.draw(Text(verbatim: "日"), at: CGPoint(x: 1, y: 0), anchor: .topLeading)
        }
        let buffer = canvasDrawn(canvas.canvasGrain(.quadrants), columns: 4, rows: 1)
        #expect(buffer.lines[0].stripped == " 日 ")
        #expect(buffer.lines[0].strippedLength == 4)
        let cells = paintedCells(buffer.lines[0])
        #expect(cells[1].glyph == "日")
        #expect(cells[1].state.backgroundColour == .rgb(255, 0, 0))
    }
}
