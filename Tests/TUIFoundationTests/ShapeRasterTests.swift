//  🖥️ TUI — A Terminal UI framework for Swift
//  ShapeRasterTests.swift
//
//  The machinery under a drawn shape: coverage of polygons, the stroker's
//  pieces, the half-block and box-drawing tiers' cells, and the bytes and
//  claims those cells become.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing

@testable import TUIFoundation

/// The glyphs of `cells`, a row to a string.
private func glyphs(_ cells: ShapeCells) -> [String] {
    (0..<cells.height).map { row in String((0..<cells.width).map { cells[$0, row].glyph }) }
}

/// A square's corners, clockwise on screen.
private func square(_ x: CGFloat, _ y: CGFloat, _ side: CGFloat) -> [CGPoint] {
    [CGPoint(x: x, y: y), CGPoint(x: x + side, y: y), CGPoint(x: x + side, y: y + side), CGPoint(x: x, y: y + side)]
}

@MainActor
@Suite("A shape's coverage, stroke pieces and cells")
struct ShapeRasterTests {

    // MARK: Coverage

    @Test("A polygon covers the pixels it spans, and a half pixel by its share")
    func coverageOfASquare() {
        let whole = ShapeCoverage(polygons: [square(1, 1, 2)], evenOdd: false, width: 4, height: 4)
        #expect(whole.coverage(x: 1, y: 1) == 1)
        #expect(whole.coverage(x: 2, y: 2) == 1)
        #expect(whole.coverage(x: 0, y: 0) == 0)
        #expect(whole.coverage(x: 3, y: 2) == 0)
        // Offset by half a pixel each way: a quarter of each of four pixels.
        let offset = ShapeCoverage(polygons: [square(0.5, 0.5, 1)], evenOdd: false, width: 2, height: 2)
        #expect(offset.coverage(x: 0, y: 0) == 0.25)
        #expect(offset.coverage(x: 1, y: 1) == 0.25)
    }

    @Test("Nested squares: the non-zero rule fills the hole, even-odd leaves it")
    func fillRules() {
        let nested = [square(0, 0, 6), square(2, 2, 2)]
        let nonZero = ShapeCoverage(polygons: nested, evenOdd: false, width: 6, height: 6)
        let evenOdd = ShapeCoverage(polygons: nested, evenOdd: true, width: 6, height: 6)
        #expect(nonZero.coverage(x: 2, y: 2) == 1)
        #expect(evenOdd.coverage(x: 2, y: 2) == 0)
        #expect(evenOdd.coverage(x: 0, y: 0) == 1)
    }

    /// Before, a crossing was converted to a sample index before it was held
    /// to the row, and one past `Int.max` trapped.
    @Test("A far-off point's crossings are held to the grid")
    func farOffPoints() {
        // A triangle reaching to the largest finite x covers the whole grid,
        // and one reaching as far left the whole of its own rows.
        let wedge = [[CGPoint.zero, CGPoint(x: CGFloat.greatestFiniteMagnitude, y: 0), CGPoint(x: 0, y: 4)]]
        let coverage = ShapeCoverage(polygons: wedge, evenOdd: false, width: 4, height: 4)
        #expect((0..<4).allSatisfy { x in (0..<4).allSatisfy { coverage.coverage(x: x, y: $0) == 1 } })
        let left = [[CGPoint(x: 4, y: 0), CGPoint(x: -CGFloat.greatestFiniteMagnitude, y: 2), CGPoint(x: 4, y: 4)]]
        #expect(ShapeCoverage(polygons: left, evenOdd: false, width: 4, height: 4).coverage(x: 0, y: 1) == 1)
        // An edge too steep for its slope to be finite, beginning on a row of
        // samples: its crossing there is its top, not zero times infinity.
        let sliver = [[CGPoint(x: 0, y: 0.125), CGPoint(x: CGFloat.greatestFiniteMagnitude, y: 0.125 + 1e-15), CGPoint(x: 0, y: 3)]]
        #expect(ShapeCoverage(polygons: sliver, evenOdd: false, width: 4, height: 4).coverage(x: 3, y: 1) == 1)
    }

    // MARK: Stroking

    /// The stroke of `points` in `style`, as coverage of a `size` grid.
    private func stroked(_ points: [CGPoint], closed: Bool = false, _ style: StrokeStyle, size: Int = 12) -> ShapeCoverage {
        let polygons = ShapeStroker.polygons(of: [Path.Contour(points: points, isClosed: closed)], style: style)
        return ShapeCoverage(polygons: polygons, evenOdd: false, width: size, height: size)
    }

    @Test("A line's stroke is its width across, and its caps end it")
    func caps() {
        let line = [CGPoint(x: 2, y: 4), CGPoint(x: 8, y: 4)]
        let butt = stroked(line, StrokeStyle(lineWidth: 2))
        #expect(butt.coverage(x: 2, y: 3) == 1)
        #expect(butt.coverage(x: 7, y: 4) == 1)
        #expect(butt.coverage(x: 4, y: 2) == 0)
        #expect(butt.coverage(x: 1, y: 3) == 0)
        let square = stroked(line, StrokeStyle(lineWidth: 2, lineCap: .square))
        #expect(square.coverage(x: 1, y: 3) == 1)
        #expect(square.coverage(x: 8, y: 4) == 1)
        let round = stroked(line, StrokeStyle(lineWidth: 2, lineCap: .round))
        #expect(round.coverage(x: 1, y: 3) > 0)
        #expect(round.coverage(x: 1, y: 3) < 1)
    }

    @Test("A corner's join: a miter reaches the point, a bevel cuts it, a round one rounds it")
    func joins() {
        let corner = [CGPoint(x: 2, y: 8), CGPoint(x: 8, y: 8), CGPoint(x: 8, y: 2)]
        let miter = stroked(corner, StrokeStyle(lineWidth: 2, lineJoin: .miter))
        let bevel = stroked(corner, StrokeStyle(lineWidth: 2, lineJoin: .bevel))
        let round = stroked(corner, StrokeStyle(lineWidth: 2, lineJoin: .round))
        // The outer corner pixel, (8, 8)…(9, 9).
        #expect(miter.coverage(x: 8, y: 8) == 1)
        #expect(bevel.coverage(x: 8, y: 8) < 0.75)
        #expect(round.coverage(x: 8, y: 8) > bevel.coverage(x: 8, y: 8))
        #expect(round.coverage(x: 8, y: 8) < 1)
        // A miter past its limit is a bevel.
        let limited = stroked(corner, StrokeStyle(lineWidth: 2, lineJoin: .miter, miterLimit: 1))
        #expect(limited.coverage(x: 8, y: 8) == bevel.coverage(x: 8, y: 8))
    }

    @Test("Dashes alternate along the length from the phase; a zero dash with round caps is a dot")
    func dashes() {
        let line = [CGPoint(x: 0, y: 4), CGPoint(x: 10, y: 4)]
        let dashed = stroked(line, StrokeStyle(lineWidth: 2, dash: [2, 2]))
        #expect(dashed.coverage(x: 0, y: 3) == 1)
        #expect(dashed.coverage(x: 2, y: 3) == 0)
        #expect(dashed.coverage(x: 4, y: 3) == 1)
        #expect(dashed.coverage(x: 6, y: 3) == 0)
        let shifted = stroked(line, StrokeStyle(lineWidth: 2, dash: [2, 2], dashPhase: 2))
        #expect(shifted.coverage(x: 0, y: 3) == 0)
        #expect(shifted.coverage(x: 2, y: 3) == 1)
        let dots = stroked(line, StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0, 4]))
        #expect(dots.coverage(x: 0, y: 3) > 0)
        #expect(dots.coverage(x: 4, y: 3) > 0)
        #expect(dots.coverage(x: 2, y: 3) == 0)
    }

    /// CoreGraphics' own strokes (the W1 review's `arcs.swift` probe): `[4]`
    /// is `####....`, `[4, 2, 6]` is `####..######....##......`. Before, a lone
    /// length dashed nothing: every stretch of it was painted.
    @Test("An odd number of dash lengths runs twice, so painted and unpainted alternate")
    func oddDashes() {
        let line = [CGPoint(x: 0, y: 4), CGPoint(x: 24, y: 4)]
        let single = stroked(line, StrokeStyle(lineWidth: 2, dash: [4]), size: 24)
        #expect((0..<24).map { single.coverage(x: $0, y: 3) == 1 ? "#" : "." }.joined() == "####....####....####....")
        let triple = stroked(line, StrokeStyle(lineWidth: 2, dash: [4, 2, 6]), size: 24)
        #expect((0..<24).map { triple.coverage(x: $0, y: 3) == 1 ? "#" : "." }.joined() == "####..######....##......")
    }

    /// Before, the pattern was walked a dash at a time whatever its size: a
    /// dash of `1e-6` round this circle was a hundred million dashes, and one
    /// along a line to the edge of the plane never ended.
    @Test("A dash pattern too fine to see, or too long to walk, draws the line unbroken")
    func unbrokenDashes() {
        let circle = Path(ellipseIn: CGRect(x: 0, y: 0, width: 40, height: 40)).contours(tolerance: 0.05)
        for dash: [CGFloat] in [[1e-6], [1e-13], [0.1, 0.3], [0.25, 0.25]] {
            #expect(ShapeStroker.dashed(circle, style: StrokeStyle(dash: dash)) == circle, "dash \(dash)")
        }
        // A pattern a pixel long is dashes.
        #expect(ShapeStroker.dashed(circle, style: StrokeStyle(dash: [0.5, 0.5])).count > 100)
        // A line to the edge of the plane.
        let horizon = [Path.Contour(points: [CGPoint(x: 0, y: 4), CGPoint(x: CGFloat.greatestFiniteMagnitude, y: 4)], isClosed: false)]
        #expect(ShapeStroker.dashed(horizon, style: StrokeStyle(dash: [2, 2])) == horizon)
        // Drawn, the fine pattern is the line.
        let line = [CGPoint(x: 0, y: 4), CGPoint(x: 10, y: 4)]
        let fine = stroked(line, StrokeStyle(lineWidth: 2, dash: [1e-6]))
        #expect((0..<10).allSatisfy { fine.coverage(x: $0, y: 3) == 1 })
    }

    // MARK: Half blocks

    /// A circle filling a `columns` × `rows` frame at aspect 2.
    private func circle(columns: Int, rows: Int) -> Path {
        Path(ellipseIn: CGRect(x: 0, y: 0, width: CGFloat(columns), height: CGFloat(rows) * 2))
    }

    @Test("A circle's cells: field inside, half blocks at its rim, nothing outside")
    func halfBlockCircle() {
        let cells = ShapeHalfBlocks.cells(
            circle(columns: 10, rows: 5), drawing: .fill(FillStyle()), columns: 10, rows: 5, aspect: 2,
            monochrome: false
        ) { _, _ in .red }
        #expect(cells[0, 0].isEmpty)
        #expect(cells[9, 4].isEmpty)
        #expect(cells[5, 2] == ShapeCells.Cell(ink: nil, field: .red, glyph: " "))
        // Two columns in from the top-leading corner the rim crosses the top
        // row: its lower half covered, its upper partly — `▄` in the full
        // colour over the partial one.
        #expect(cells[2, 0].glyph == "▄")
        #expect(cells[2, 0].ink == .red)
        let upper = cells[2, 0].field?.alpha ?? 0
        #expect(upper > 0 && upper < 255, "the edge is antialiased")
        // And the shape is its own mirror image, top to bottom.
        for column in 0..<10 {
            #expect(cells[column, 0].isEmpty == cells[column, 4].isEmpty)
        }
    }

    @Test("Unantialiased, a half is drawn whole or not at all; with no colour, as a glyph alone")
    func halfBlockRules() {
        let path = circle(columns: 10, rows: 5)
        let crisp = ShapeHalfBlocks.cells(
            path, drawing: .fill(FillStyle(antialiased: false)), columns: 10, rows: 5, aspect: 2, monochrome: false
        ) { _, _ in .blue }
        for cell in crisp.cells {
            #expect(cell.ink.map { $0.alpha == 255 } ?? true)
            #expect(cell.field.map { $0.alpha == 255 } ?? true)
        }
        let mono = ShapeHalfBlocks.cells(path, drawing: .fill(FillStyle()), columns: 10, rows: 5, aspect: 2, monochrome: true) { _, _ in .blue }
        #expect(mono.cells.allSatisfy { $0.ink == nil && $0.field == nil })
        #expect(glyphs(mono)[2].contains("█"))
        #expect(glyphs(mono)[0].contains("▄"))
    }

    @Test("A stroked circle is a ring: its centre is empty")
    func ring() {
        let cells = ShapeHalfBlocks.cells(
            circle(columns: 10, rows: 5), drawing: .stroke(StrokeStyle(lineWidth: 1), antialiased: true), columns: 10,
            rows: 5, aspect: 2, monochrome: false
        ) { _, _ in .green }
        #expect(cells[5, 2].isEmpty)
        #expect(!cells[0, 2].isEmpty)
    }

    // MARK: Box drawing

    @Test("A box of lines, a corner glyph per corner")
    func boxStroke() {
        func box(_ columns: Int, _ rows: Int, _ corners: RoundedCorners) -> [String] {
            glyphs(ShapeBoxCells.stroke(columns: columns, rows: rows, corners: corners) { _, _ in .white })
        }
        #expect(box(4, 3, RoundedCorners(all: true)) == ["╭──╮", "│  │", "╰──╯"])
        #expect(box(4, 3, RoundedCorners(all: false)) == ["┌──┐", "│  │", "└──┘"])
        let uneven = RoundedCorners(RectangleCornerRadii(topLeading: 2, bottomTrailing: 1))
        #expect(box(3, 2, uneven) == ["╭─┐", "└─╯"])
        #expect(box(5, 1, RoundedCorners(all: true)) == ["(───)"])
        #expect(box(5, 1, RoundedCorners(all: false)) == ["[───]"])
        #expect(box(1, 3, RoundedCorners(all: false)) == ["╷", "│", "╵"])
        #expect(box(1, 1, RoundedCorners(all: true)) == ["○"])
    }

    @Test("A filled box: cells of the paint, rounded corners cut by a quadrant, one row capped")
    func boxFill() {
        func filled(_ path: Path, _ columns: Int, _ rows: Int, _ corners: RoundedCorners, wholeCells: Bool = false) -> [String] {
            glyphs(ShapeBoxCells.fill(path, columns: columns, rows: rows, aspect: 2, corners: corners, wholeCells: wholeCells) { _, _ in .red })
        }
        let frame = CGRect(x: 0, y: 0, width: 6, height: 6)
        let rounded = Path(roundedRect: frame, cornerRadius: 1)
        #expect(filled(rounded, 6, 3, RoundedCorners(all: true)) == ["▟    ▙", "      ", "▜    ▛"])
        #expect(filled(Path(frame), 6, 3, RoundedCorners(all: false)) == ["      ", "      ", "      "])
        let capsule = Path(roundedRect: CGRect(x: 0, y: 0, width: 6, height: 2), cornerRadius: 1)
        #expect(filled(capsule, 6, 1, RoundedCorners(all: true)) == ["▐    ▌"])
        // Whole cells keep the caps, and a corner is its coverage.
        #expect(filled(capsule, 6, 1, RoundedCorners(all: true), wholeCells: true) == ["▐    ▌"])
        #expect(filled(rounded, 6, 3, RoundedCorners(all: true), wholeCells: true) == ["      ", "      ", "      "])
        let cells = ShapeBoxCells.fill(rounded, columns: 6, rows: 3, aspect: 2, corners: RoundedCorners(all: true), wholeCells: false) { _, _ in .red }
        #expect(cells[1, 1] == ShapeCells.Cell(ink: nil, field: .red, glyph: " "))
        #expect(cells[0, 0] == ShapeCells.Cell(ink: .red, field: nil, glyph: "▟"))
    }

    /// Before, every corner of the one cell lost its quadrant, and the cell
    /// drew nothing — while Apple Terminal's whole cells drew it, and the same
    /// shape stroked drew `○`.
    @Test("A one-cell rounded fill is its coverage, on every terminal")
    func oneCellFill() {
        let dot = Path(roundedRect: CGRect(x: 0, y: 0, width: 1, height: 2), cornerRadius: 0.5)
        for wholeCells in [false, true] {
            let cells = ShapeBoxCells.fill(
                dot, columns: 1, rows: 1, aspect: 2, corners: RoundedCorners(all: true), wholeCells: wholeCells
            ) { _, _ in .red }
            #expect(cells[0, 0] == ShapeCells.Cell(ink: nil, field: .red, glyph: " "), "whole cells: \(wholeCells)")
        }
    }

    // MARK: Bytes and claims

    @Test("Cells become one introducer a run, and claims for what is translucent or absent")
    func buffer() {
        var cells = ShapeCells(width: 4, height: 1)
        cells[1, 0] = ShapeCells.Cell(ink: nil, field: .red, glyph: " ")
        cells[2, 0] = ShapeCells.Cell(ink: nil, field: .red, glyph: " ")
        cells[3, 0] = ShapeCells.Cell(ink: Color.blue.opacity(0.5), field: nil, glyph: "▄")
        let buffer = cells.buffer()
        #expect(buffer.width == 4)
        #expect(buffer.lines[0].strippedLength == 4)
        #expect(buffer.lines[0].hasPrefix(" "), "an absent cell states no colour")
        // The absent cell hands itself back (field 0); the translucent ink is
        // claimed at its alpha; the opaque field owes nothing.
        #expect(buffer.opacityRegions.count == 2)
        #expect(buffer.opacityRegions[0].offsetX == 0 && buffer.opacityRegions[0].fieldOpacity == 0)
        #expect(buffer.opacityRegions[1].offsetX == 3 && abs(buffer.opacityRegions[1].inkOpacity - 128.0 / 255) < 1e-9)
    }
}
