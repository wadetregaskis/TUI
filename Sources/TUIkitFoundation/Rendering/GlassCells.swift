//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GlassCells.swift
//
//  A glass drawn: the surface filling its shape, and the rim — the shape's
//  outline in the appearance's lines — laid over it.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import TUIkitCore
import TUIkitStyling
import TUIkitView

/// The cells of a glass, for a view to be composited over.
///
/// **The surface** is the shape filled with ``Glass``'s surface colour, as
/// `background(_:in:)` fills one: the rectangle family in whole cells with
/// quadrant corners, anything else rasterized.
///
/// **The rim** is the shape's outline, in the glass's highlighted ink, drawn
/// in the family of the ``Appearance`` in force — the family a bordered button
/// is drawn in (`ButtonFaceFamily`), so glass and buttons are of a piece:
///
/// | family | the rectangle family | any other shape |
/// |---|---|---|
/// | lines (`.rounded`, `.line`, `.heavy`, `.doubleLine`) | a box of the style's lines; a light style's corners `╭` where the shape is rounded and `┌` where not; one row, the ends `( … )` or `[ … ]` | its rasterized border, a column wide |
/// | Braille | a dotted outline of the shape | the same |
/// | solid (`.block`) | a band: the surface's outermost cells in the rim's colour; one row, its ends | its rasterized border |
/// | blank | none | none |
///
/// On a terminal with no colour there is no surface to show; the rim is
/// drawn, as glyphs alone.
enum GlassCells {
    /// `glass` in `shape`, filling a `columns` × `rows` frame, its rim lifted
    /// while `hovered`.
    ///
    /// - Parameters:
    ///   - glass: The glass.
    ///   - shape: Its shape — one standing for another (`.buttonBorder`, a
    ///     container's) is drawn as that one.
    ///   - columns: The frame's width.
    ///   - rows: The frame's height.
    ///   - hovered: Whether the pointer is over interactive glass.
    ///   - presence: How far the glass has arrived, 0 to 1
    ///     (`glassEffectTransition(_:)`): its surface at that fraction of its
    ///     opacity, and its rim's lines drawn from half-way.
    ///   - context: The context the glass is drawn in.
    ///   - owner: The type drawing it, which keys the surface's colour
    ///     animation at the context's identity; `nil` to draw the surface as it
    ///     is, for glass drawn somewhere that is not its own (a container's).
    /// - Returns: The glass's cells.
    @MainActor
    static func drawing(
        _ glass: Glass, in shape: any Shape, columns: Int, rows: Int, hovered: Bool, presence: Double = 1,
        context: RenderContext, owner: Any.Type?
    ) -> ShapeCells {
        let environment = context.environment
        let frame = ShapeFrame(columns: columns, rows: rows, aspect: environment.imageCellAspect)
        let drawn = resolvedShape(shape, in: context, columns: columns, rows: rows)
        let target = glass.surface(in: environment)
        let animated = owner.map { ColorAnimation.resolving(target, owner: $0, context: context) } ?? target
        let surface = presence < 1 ? animated.opacity(presence) : animated
        let painter = ShapePainter(
            paint: .color(surface), extent: GradientFrame(width: columns, height: rows), aspect: frame.aspect,
            palette: environment.palette)
        let fill = ShapeCells.drawing(
            drawn, as: .fill(FillStyle()), frame: frame, painter: painter, monochrome: false,
            wholeCells: !environment.blockElementsFillTheLine)
        // A glyph is drawn or not, by the ½ rule every glyph decision takes, so
        // a glass part-way arrived draws its rim's lines from half-way, in its
        // ink part-way from the surface they land on.
        let ink = glass.rimInk(hovered: hovered, in: environment)
        let rim = rimCells(
            of: drawn, frame: frame, family: ButtonFaceFamily(environment.appearance), fill: fill,
            ink: presence < 1 ? ink.opacity(presence, over: environment.enclosingSurface) : ink)
        let monochrome = ColorDepth.current == .noColor
        var cells = monochrome ? ShapeCells(width: columns, height: rows) : fill
        cells.laying(rim)
        if presence < 0.5 { cells.droppingGlyphs() }
        if monochrome { cells.dropColours() }
        return cells
    }

    /// The rim of `shape` over `frame` in `family`'s drawing, in `ink` — over
    /// `fill`, the surface it rims, whose outermost cells a solid family's band
    /// recolours.
    static func rimCells(
        of shape: any Shape, frame: ShapeFrame, family: ButtonFaceFamily, fill: ShapeCells, ink: Color
    ) -> ShapeCells {
        let corners = (shape as? any BoxDrawnShape)?.boxCorners(in: frame.rect).map { RoundedCorners($0) }
        switch family {
        case .blank:
            return ShapeCells(width: frame.columns, height: frame.rows)
        case .braille(let thickness):
            return dotOutline(shape.path(in: frame.rect), frame: frame, thickness: thickness, ink: ink)
        case .lines(let style):
            if let corners { return box(columns: frame.columns, rows: frame.rows, corners: corners, style: style, ink: ink) }
        case .solid:
            if corners != nil { return band(of: fill, ink: ink) }
        }
        return border(of: shape, frame: frame, ink: ink)
    }

    // MARK: - Lines

    /// A box of `style`'s lines round a `columns` × `rows` frame, in `ink`.
    ///
    /// A light style — `.rounded` and `.line` — takes the shape's corners, `╭`
    /// where it is rounded and `┌` where not, as a shape's stroke does; a heavy
    /// or double one has no rounded corners, and keeps its own. One row tall
    /// the box is its ends, `(` where rounded and `[` where not, as a lines
    /// button's are — the row between them is the content's. One column is
    /// `╷ │ ╵`; one cell `○` or `□`.
    static func box(columns: Int, rows: Int, corners: RoundedCorners, style: BorderStyle, ink: Color) -> ShapeCells {
        var cells = ShapeCells(width: columns, height: rows)
        guard columns > 0, rows > 0 else { return cells }
        func put(_ glyph: Character, _ x: Int, _ y: Int) {
            cells[x, y] = ShapeCells.Cell(ink: ink, field: nil, glyph: glyph)
        }
        let light = style.horizontal == "─" && style.vertical == "│"
        let leadingRound = corners.topLeading || corners.bottomLeading
        let trailingRound = corners.topTrailing || corners.bottomTrailing
        switch (columns, rows) {
        case (1, 1):
            put(leadingRound || trailingRound ? "○" : "□", 0, 0)
        case (_, 1):
            put(leadingRound ? "(" : "[", 0, 0)
            put(trailingRound ? ")" : "]", columns - 1, 0)
        case (1, _):
            put(light ? "╷" : style.vertical, 0, 0)
            for y in 1..<(rows - 1) { put(style.vertical, 0, y) }
            put(light ? "╵" : style.vertical, 0, rows - 1)
        default:
            put(light ? (corners.topLeading ? "╭" : "┌") : style.topLeft, 0, 0)
            put(light ? (corners.topTrailing ? "╮" : "┐") : style.topRight, columns - 1, 0)
            put(light ? (corners.bottomLeading ? "╰" : "└") : style.bottomLeft, 0, rows - 1)
            put(light ? (corners.bottomTrailing ? "╯" : "┘") : style.bottomRight, columns - 1, rows - 1)
            for x in 1..<(columns - 1) {
                put(style.horizontal, x, 0)
                put(style.bottomHorizontal, x, rows - 1)
            }
            for y in 1..<(rows - 1) {
                put(style.vertical, 0, y)
                put(style.rightVertical, columns - 1, y)
            }
        }
        return cells
    }

    /// The rasterized border of `shape`: its outline inset by half a column
    /// where the shape insets, traced a column wide — what
    /// `strokeBorder(lineWidth: 1)` draws — or, where it cannot be inset,
    /// traced on the outline itself.
    static func border(of shape: any Shape, frame: ShapeFrame, ink: Color) -> ShapeCells {
        func inset<T: InsettableShape>(_ insettable: T) -> Path { insettable.inset(by: 0.5).path(in: frame.rect) }
        let path = (shape as? any InsettableShape).map { inset($0) } ?? shape.path(in: frame.rect)
        return ShapeHalfBlocks.cells(
            path, drawing: .stroke(StrokeStyle(lineWidth: 1), antialiased: true), columns: frame.columns,
            rows: frame.rows, aspect: frame.aspect, monochrome: false, colour: { _, _ in ink })
    }

    // MARK: - Solid

    /// The outermost cells of `fill` in `ink`: a band round the surface, as a
    /// `.block` border is a band round a box. One row tall it is the row's two
    /// ends — its caps.
    static func band(of fill: ShapeCells, ink: Color) -> ShapeCells {
        var band = ShapeCells(width: fill.width, height: fill.height)
        for y in 0..<fill.height {
            for x in 0..<fill.width {
                let isEnd = x == 0 || x == fill.width - 1
                guard isEnd || (fill.height > 1 && (y == 0 || y == fill.height - 1)) else { continue }
                let cell = fill[x, y]
                guard !cell.isEmpty else { continue }
                band[x, y] =
                    cell.field != nil
                    ? ShapeCells.Cell(ink: nil, field: ink, glyph: cell.glyph)
                    : ShapeCells.Cell(ink: ink, field: nil, glyph: cell.glyph)
            }
        }
        return band
    }

    // MARK: - Braille

    /// A dotted outline of `path` over `frame`, `thickness` Braille dots thick,
    /// in `ink`.
    ///
    /// A Braille cell is two dots across and four down — at the usual cell
    /// aspect, square dots. A dot is on the outline when the shape covers at
    /// least half of it and one within `thickness` dots of it, across or down,
    /// is outside: the rule a Braille button's face is drawn by
    /// (`_ButtonStyleBody.dotRows`), here from the shape's own path, so any
    /// shape has one.
    static func dotOutline(_ path: Path, frame: ShapeFrame, thickness: Int, ink: Color) -> ShapeCells {
        let (columns, rows) = (frame.columns, frame.rows)
        var cells = ShapeCells(width: columns, height: rows)
        guard columns > 0, rows > 0, frame.aspect > 0 else { return cells }
        let (across, down) = (columns * 2, rows * 4)
        let unitsPerDotRow = CGFloat(frame.aspect / 4)
        let polygons = path.contours(tolerance: 0.05).map {
            $0.points.map { CGPoint(x: $0.x * 2, y: $0.y / unitsPerDotRow) }
        }
        let coverage = ShapeCoverage(polygons: polygons, evenOdd: false, width: across, height: down)
        var covered = [Bool](repeating: false, count: across * down)
        for y in 0..<down {
            for x in 0..<across { covered[y * across + x] = coverage.coverage(x: x, y: y) >= 0.5 }
        }
        func inside(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < across && y < down && covered[y * across + x]
        }
        let reach = min(max(thickness, 1), 4)
        // Each dot's bit, by row and column of the cell (Unicode's Braille numbering).
        let bits: [[UInt32]] = [[0x01, 0x08], [0x02, 0x10], [0x04, 0x20], [0x40, 0x80]]
        for row in 0..<rows {
            for column in 0..<columns {
                var mask: UInt32 = 0
                for dy in 0..<4 {
                    for dx in 0..<2 {
                        let (x, y) = (column * 2 + dx, row * 4 + dy)
                        let onOutline =
                            inside(x, y)
                            && (1...reach).contains { step in
                                !inside(x - step, y) || !inside(x + step, y) || !inside(x, y - step)
                                    || !inside(x, y + step)
                            }
                        if onOutline { mask |= bits[dy][dx] }
                    }
                }
                guard mask != 0, let scalar = Unicode.Scalar(0x2800 + mask) else { continue }
                cells[column, row] = ShapeCells.Cell(ink: ink, field: nil, glyph: Character(scalar))
            }
        }
        return cells
    }
}

extension ShapeCells {
    /// These cells with their glyphs taken away: a glyph's cell keeps only its
    /// field, and one with none draws nothing.
    mutating func droppingGlyphs() {
        for index in cells.indices where cells[index].glyph != " " {
            cells[index] = cells[index].field.map { Cell(ink: nil, field: $0, glyph: " ") } ?? .empty
        }
    }

    /// These cells with those inside `rect` taken away, cut to these cells'
    /// bounds: what a joined glass's members draw themselves.
    mutating func clearing(_ rect: CellRect) {
        let (top, bottom) = (max(0, rect.y), min(height, rect.y + rect.height))
        let (left, right) = (max(0, rect.x), min(width, rect.x + rect.width))
        guard top < bottom, left < right else { return }
        for row in top..<bottom {
            for column in left..<right { self[column, row] = .empty }
        }
    }

    /// `top` laid over these cells with its top-left at `origin`, cut to these
    /// cells' bounds: each cell `top` draws takes the place of the one under
    /// it, keeping that one's field under a glyph that states none — a rim's
    /// line on the surface it rims.
    mutating func laying(_ top: ShapeCells, at origin: (x: Int, y: Int) = (0, 0)) {
        for row in 0..<top.height {
            let y = origin.y + row
            guard y >= 0, y < height else { continue }
            for column in 0..<top.width {
                let x = origin.x + column
                guard x >= 0, x < width else { continue }
                var cell = top[column, row]
                guard !cell.isEmpty else { continue }
                let under = self[x, y]
                if cell.field == nil, under.glyph == " " { cell.field = under.field }
                self[x, y] = cell
            }
        }
    }
}
