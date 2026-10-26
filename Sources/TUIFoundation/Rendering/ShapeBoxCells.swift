//  🖥️ TUI — A Terminal UI framework for Swift
//  ShapeBoxCells.swift
//
//  The box-drawing tier: a rectangle-family shape stroked in line glyphs, a
//  corner per corner, and filled in whole cells with quadrant corners.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import TUICore
import TUIStyling

/// Which corners of a rectangle-family shape are rounded — the whole of what
/// its corner radii can say in a cell grid's line vocabulary.
struct RoundedCorners: Equatable, Sendable {
    var topLeading: Bool
    var topTrailing: Bool
    var bottomLeading: Bool
    var bottomTrailing: Bool

    /// Rounded wherever a radius is above zero.
    init(_ radii: RectangleCornerRadii) {
        topLeading = radii.topLeading > 0
        topTrailing = radii.topTrailing > 0
        bottomLeading = radii.bottomLeading > 0
        bottomTrailing = radii.bottomTrailing > 0
    }

    /// Every corner rounded, or none.
    init(all rounded: Bool) {
        topLeading = rounded
        topTrailing = rounded
        bottomLeading = rounded
        bottomTrailing = rounded
    }
}

/// The box-drawing tier of the rectangle family — `Rectangle`,
/// `RoundedRectangle`, `UnevenRoundedRectangle`, `Capsule` and the container
/// shapes — whose edges land on cell boundaries, so their natural drawing is
/// the terminal's own.
///
/// **A stroke** is a box of line glyphs round the frame's outermost cells:
/// `┌─┐` where a corner's radius is zero and `╭─╮` where it is not, decided
/// per corner, so `UnevenRoundedRectangle` and `RectangleCornerRadii` are
/// exactly what they say (refusal review W1). A frame one row tall ends in
/// `(` `)` where rounded and `[` `]` where not, as a lines button does; one
/// column tall runs `╷ │ ╵`; a single cell is `○` or `□`.
///
/// **A fill** is cells of the paint, with each corner cut at quadrant
/// resolution — the corner region the shape's own path leaves uncovered, by
/// the ½ rule a quadrant at a time — and at least the outermost quadrant of
/// any rounded corner, so a radius below what a quadrant can show still reads
/// as round (`▟` for a top-leading corner), the line tier's per-corner rule
/// again. A frame one row tall ends in the half-block caps `▐ ▌` wherever
/// rounded: the capsule vocabulary a text field and a solid button already
/// draw. Where the terminal draws Block Elements short of the line (Apple
/// Terminal, ``EnvironmentValues/blockElementsFillTheLine``), a corner is a
/// whole cell — drawn where at least half covered — as a solid button face's
/// is there, and only the one-row caps are glyphs. A single cell is every
/// corner at once, and cut at each it would be nothing: it is its coverage
/// alone on every terminal, so a one-cell capsule is a block, a status dot.
enum ShapeBoxCells {
    /// The quadrant glyph for each set of quadrants — bit 0 top-leading, 1
    /// top-trailing, 2 bottom-leading, 3 bottom-trailing.
    private static var quadrants: [Character] { TerminalSymbols.quadrants }

    /// The box of line glyphs round a `columns` × `rows` frame, each in
    /// `colour(x, y)`.
    static func stroke(columns: Int, rows: Int, corners: RoundedCorners, colour: (Int, Int) -> Color) -> ShapeCells {
        var cells = ShapeCells(width: columns, height: rows)
        guard columns > 0, rows > 0 else { return cells }
        func put(_ glyph: Character, _ x: Int, _ y: Int) {
            cells[x, y] = ShapeCells.Cell(ink: colour(x, y), field: nil, glyph: glyph)
        }
        switch (columns, rows) {
        case (1, 1):
            let round = corners.topLeading || corners.topTrailing || corners.bottomLeading || corners.bottomTrailing
            put(round ? "○" : "□", 0, 0)
        case (_, 1):
            put(corners.topLeading || corners.bottomLeading ? "(" : "[", 0, 0)
            for x in 1..<(columns - 1) { put("─", x, 0) }
            put(corners.topTrailing || corners.bottomTrailing ? ")" : "]", columns - 1, 0)
        case (1, _):
            put("╷", 0, 0)
            for y in 1..<(rows - 1) { put("│", 0, y) }
            put("╵", 0, rows - 1)
        default:
            put(corners.topLeading ? "╭" : "┌", 0, 0)
            put(corners.topTrailing ? "╮" : "┐", columns - 1, 0)
            put(corners.bottomLeading ? "╰" : "└", 0, rows - 1)
            put(corners.bottomTrailing ? "╯" : "┘", columns - 1, rows - 1)
            for x in 1..<(columns - 1) {
                put("─", x, 0)
                put("─", x, rows - 1)
            }
            for y in 1..<(rows - 1) {
                put("│", 0, y)
                put("│", columns - 1, y)
            }
        }
        return cells
    }

    /// `path` — the shape's own outline in square units over a `columns` ×
    /// `rows` frame of `aspect`-unit rows — filled in cells of
    /// `colour(x, y)`, its corners cut at quadrant resolution.
    ///
    /// - Parameters:
    ///   - wholeCells: Whether a cut corner is a whole cell rather than
    ///     quadrants, for a terminal that draws Block Elements short of the line.
    ///   - halves: The paint at half cell (`x`, `y`), `y` counting half rows,
    ///     for a paint that changes down a column on a terminal whose Block
    ///     Elements fill the line: a cell the shape covers whole is then its
    ///     two halves, as a rasterized shape's is
    ///     (``ShapeHalfBlocks/cell(upper:lower:)``, decisions B95). `nil` for
    ///     one sample a cell.
    static func fill(
        _ path: Path, columns: Int, rows: Int, aspect: Double, corners: RoundedCorners, wholeCells: Bool,
        colour: (Int, Int) -> Color, halves: ((Int, Int) -> Color)? = nil
    ) -> ShapeCells {
        var cells = ShapeCells(width: columns, height: rows)
        guard columns > 0, rows > 0, aspect > 0 else { return cells }
        // The path's coverage of each quadrant: half a column across, half a
        // row down.
        let unitsPerQuadrantRow = CGFloat(aspect / 2)
        let polygons = path.contours(tolerance: 0.05).map { $0.points.map { CGPoint(x: $0.x * 2, y: $0.y / unitsPerQuadrantRow) } }
        let coverage = ShapeCoverage(polygons: polygons, evenOdd: false, width: columns * 2, height: rows * 2)
        for row in 0..<rows {
            for column in 0..<columns {
                var bits = 0
                var total = 0.0
                for (bit, (dx, dy)) in [(0, 0), (1, 0), (0, 1), (1, 1)].enumerated() {
                    let covered = coverage.coverage(x: column * 2 + dx, y: row * 2 + dy)
                    total += covered
                    if covered >= 0.5 { bits |= 1 << bit }
                }
                if wholeCells { bits = total / 4 >= 0.5 ? 15 : 0 }
                bits = cut(bits, column: column, row: row, columns: columns, rows: rows, corners: corners, wholeCells: wholeCells)
                guard bits != 0 else { continue }
                if bits == 15, let halves {
                    cells[column, row] = ShapeHalfBlocks.cell(
                        upper: halves(column, row * 2), lower: halves(column, row * 2 + 1))
                    continue
                }
                let paint = colour(column, row)
                cells[column, row] =
                    bits == 15
                    ? ShapeCells.Cell(ink: nil, field: paint, glyph: " ")
                    : ShapeCells.Cell(ink: paint, field: nil, glyph: quadrants[bits])
            }
        }
        return cells
    }

    /// `bits` with a rounded corner's outermost quadrant removed where the
    /// cell is that corner's — or, one row tall, the cell's outer half where
    /// either corner of its end is rounded: the caps `▐ ▌`.
    private static func cut(
        _ bits: Int, column: Int, row: Int, columns: Int, rows: Int, corners: RoundedCorners, wholeCells: Bool
    ) -> Int {
        let (left, right) = (column == 0, column == columns - 1)
        let (top, bottom) = (row == 0, row == rows - 1)
        guard (left || right) && (top || bottom) else { return bits }
        // One cell is all four corners: cutting each would leave nothing.
        if rows == 1, columns == 1 { return bits }
        if rows == 1, columns > 1 {
            // The caps: a one-row face's ends, kept on every terminal, as a
            // solid button's are (Terminal compatibility survey, "Apple
            // Terminal draws Block Elements short of the line").
            if left, corners.topLeading || corners.bottomLeading { return bits & 0b1010 }
            if right, corners.topTrailing || corners.bottomTrailing { return bits & 0b0101 }
            return bits
        }
        // In whole cells a corner is its coverage alone, as a solid button's
        // face is there: a cut a whole cell wide would round far more than
        // the radius says.
        guard !wholeCells else { return bits }
        var keep = bits
        if top, left, corners.topLeading { keep &= ~0b0001 }
        if top, right, corners.topTrailing { keep &= ~0b0010 }
        if bottom, left, corners.bottomLeading { keep &= ~0b0100 }
        if bottom, right, corners.bottomTrailing { keep &= ~0b1000 }
        return keep
    }
}
