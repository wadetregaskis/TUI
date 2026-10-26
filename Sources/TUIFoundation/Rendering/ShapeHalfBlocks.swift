//  🖥️ TUI — A Terminal UI framework for Swift
//  ShapeHalfBlocks.swift
//
//  The rasterizer tier: a path filled or stroked into half-block pixels, each
//  cell's two halves drawn at the share of them it covers.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import TUIStyling

/// What a shape is asked to draw: its inside, or a stroke along its outline.
enum ShapeDrawing: Equatable, Sendable {
    /// The inside, by `FillStyle`'s rule.
    case fill(FillStyle)
    /// A stroke, antialiased or not.
    case stroke(StrokeStyle, antialiased: Bool)

    /// Whether partial coverage is drawn as alpha.
    var isAntialiased: Bool {
        switch self {
        case .fill(let style): style.isAntialiased
        case .stroke(_, let antialiased): antialiased
        }
    }
}

/// The rasterizer tier of a shape: any path, at half-block resolution.
///
/// A cell is two pixels, its top half and its bottom half — one column across
/// and half a row down, which at the usual cell aspect of 2 is one square unit
/// each way, so a circle's pixels are square. Each pixel's coverage comes from
/// ``ShapeCoverage``; its colour from the paint at that pixel. A cell is then
/// drawn by `Opacity as composition.md` §42.2's table, which the image path's
/// half blocks already follow:
///
/// | top    | bottom | cell |
/// |--------|--------|------|
/// | absent | absent | a space stating nothing |
/// | absent | there  | `▄` in the bottom's colour, no field |
/// | there  | absent | `▀` in the top's colour, no field |
/// | there  | there  | a space on the field where both agree, `▄` over the top's colour where they do not |
///
/// "There" is any coverage at all, and each colour carries its coverage as
/// alpha, so an edge blends into whatever is behind it at composite time.
/// Unantialiased, a half is there when at least half covered (§6a's ½ rule),
/// and at full strength. On a terminal with no colour the halves are glyphs
/// alone — `▀`, `▄`, `█` — by the same ½ rule.
enum ShapeHalfBlocks {
    /// The cells `path` drawn as `drawing` covers in a `columns` × `rows`
    /// frame whose rows are `aspect` units tall.
    ///
    /// - Parameters:
    ///   - path: The path, in square units: the frame is `columns` wide and
    ///     `rows × aspect` tall.
    ///   - drawing: Fill or stroke, and how.
    ///   - columns: The frame's width, in cells.
    ///   - rows: Its height, in rows.
    ///   - aspect: How many units tall a row is — the cell's height over its
    ///     width.
    ///   - monochrome: Whether the terminal shows no colour, so halves are
    ///     glyphs alone.
    ///   - colour: The paint at pixel (`x`, `y`) — `x` a column, `y` a half
    ///     row — resolved and at its own alpha.
    static func cells(
        _ path: Path, drawing: ShapeDrawing, columns: Int, rows: Int, aspect: Double, monochrome: Bool,
        colour: (Int, Int) -> Color
    ) -> ShapeCells {
        var cells = ShapeCells(width: columns, height: rows)
        guard columns > 0, rows > 0, aspect > 0 else { return cells }
        let coverage = coverage(of: path, drawing: drawing, columns: columns, rows: rows, aspect: aspect)
        let antialiased = drawing.isAntialiased && !monochrome
        func share(_ x: Int, _ y: Int) -> Double {
            let covered = coverage.coverage(x: x, y: y)
            return antialiased ? covered : (covered >= 0.5 ? 1 : 0)
        }
        for row in 0..<rows {
            for column in 0..<columns {
                let (top, bottom) = (share(column, row * 2), share(column, row * 2 + 1))
                if monochrome {
                    let glyph: Character? =
                        switch (top > 0, bottom > 0) {
                        case (true, true): "█"
                        case (true, false): "▀"
                        case (false, true): "▄"
                        case (false, false): nil
                        }
                    if let glyph { cells[column, row] = ShapeCells.Cell(ink: nil, field: nil, glyph: glyph) }
                    continue
                }
                let upper = top > 0 ? colour(column, row * 2).opacity(top) : nil
                let lower = bottom > 0 ? colour(column, row * 2 + 1).opacity(bottom) : nil
                switch (upper, lower) {
                case (nil, nil):
                    continue
                case (nil, let lower?):
                    cells[column, row] = ShapeCells.Cell(ink: lower, field: nil, glyph: "▄")
                case (let upper?, nil):
                    cells[column, row] = ShapeCells.Cell(ink: upper, field: nil, glyph: "▀")
                case (let upper?, let lower?):
                    cells[column, row] = cell(upper: upper, lower: lower)
                }
            }
        }
        return cells
    }

    /// A cell both of whose halves are there: a space on the field where the
    /// two agree, `▄` in the bottom's colour over the top's where they do not
    /// (the table's last row above).
    ///
    /// The one spelling of a two-sample cell, so whatever draws one — a shape
    /// rasterized here, a box-drawn fill, a gradient behind blank cells — draws
    /// it alike.
    static func cell(upper: Color, lower: Color) -> ShapeCells.Cell {
        upper == lower
            ? ShapeCells.Cell(ink: nil, field: upper, glyph: " ")
            : ShapeCells.Cell(ink: lower, field: upper, glyph: "▄")
    }

    /// How much of each half-block pixel `path`, drawn as `drawing`, covers.
    static func coverage(of path: Path, drawing: ShapeDrawing, columns: Int, rows: Int, aspect: Double) -> ShapeCoverage {
        // A pixel is a column across and half a row down: `aspect / 2` units.
        let unitsPerPixelRow = CGFloat(aspect / 2)
        // Straight lines to within a twentieth of a pixel, finer than the four
        // samples a side a pixel is measured at.
        let tolerance = min(1, unitsPerPixelRow) / 20
        let contours = path.contours(tolerance: tolerance)
        let polygons: [[CGPoint]]
        let evenOdd: Bool
        switch drawing {
        case .fill(let style):
            polygons = contours.map(\.points)
            evenOdd = style.isEOFilled
        case .stroke(let style, _):
            polygons = ShapeStroker.polygons(of: contours, style: style)
            evenOdd = false
        }
        let pixels = polygons.map { polygon in polygon.map { CGPoint(x: $0.x, y: $0.y / unitsPerPixelRow) } }
        return ShapeCoverage(polygons: pixels, evenOdd: evenOdd, width: columns, height: rows * 2)
    }
}
