//  🖥️ TUI — A Terminal UI framework for Swift
//  ShapeCells.swift
//
//  A shape's cells — a glyph, an ink and a field each, at whatever alpha —
//  written as styled lines and the opacity claims their alphas owe.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIStyling
import TUIView

/// A rectangle of cells a shape drew, and the one place they become bytes.
///
/// Both of a shape's render paths end here — the box-drawing one, whose cells
/// are line glyphs and quadrant corners, and the rasterizer, whose cells are
/// half blocks — so a gradient paints per cell and a translucent or partly
/// covered cell composites over what is behind it the same way whichever path
/// drew it.
///
/// A cell states three things: its glyph; its INK, the colour that glyph is
/// drawn in; and its FIELD, the colour behind it. Each colour carries its own
/// alpha, and either may be absent — a glyph with no ink is drawn in the
/// terminal's own colour, which is all a terminal with no colour has. The bytes state each colour's opaque spelling, because an emitter
/// has no backdrop to blend against, and the alphas travel beside them as
/// ``OpacityRegion`` claims, resolved where what is behind is known —
/// `Documentation/Colour and styling/Opacity as composition.md`. A cell that
/// states neither colour is not there at all: it is a space, claimed at a
/// field alpha of 0, so a glyph a sibling drew beneath it survives the
/// composite.
struct ShapeCells {
    /// One cell: its glyph, the colour of that glyph, and the colour behind
    /// it; `nil` for a colour the cell does not state.
    struct Cell: Equatable {
        var ink: Color?
        var field: Color?
        var glyph: Character

        /// A cell the shape does not reach.
        static let empty = Self(ink: nil, field: nil, glyph: " ")

        /// Whether the cell draws nothing: no colour and no glyph.
        var isEmpty: Bool { ink == nil && field == nil && glyph == " " }
    }

    /// The width, in cells.
    let width: Int
    /// The height, in rows.
    let height: Int
    /// The cells, row by row from the top.
    var cells: [Cell]

    /// A `width` × `height` rectangle the shape does not reach anywhere.
    init(width: Int, height: Int) {
        self.width = max(0, width)
        self.height = max(0, height)
        cells = [Cell](repeating: .empty, count: self.width * self.height)
    }

    /// The cell at (`x`, `y`).
    subscript(x: Int, y: Int) -> Cell {
        get { cells[y * width + x] }
        set { cells[y * width + x] = newValue }
    }

    /// The cells as styled lines, with the claims their alphas owe.
    ///
    /// A run of cells stating the same two colours is one introducer; a run
    /// stating none is bare spaces. Claims are coalesced as they are made, so
    /// an opaque shape owes none but its uncovered cells' and a ring's interior
    /// is one rectangle a row.
    func buffer() -> FrameBuffer {
        var lines: [String] = []
        lines.reserveCapacity(height)
        var claims: [OpacityRegion] = []
        for row in 0..<height {
            var line = ""
            var run = ""
            var runInk: Color?
            var runField: Color?
            func flush() {
                guard !run.isEmpty else { return }
                if runInk == nil, runField == nil {
                    line += run
                } else {
                    line += ANSIRenderer.colorize(run, foreground: runInk, background: runField)
                }
                run = ""
            }
            for column in 0..<width {
                let cell = self[column, row]
                let ink = cell.ink?.opaqueSpelling
                let field = cell.field?.opaqueSpelling
                if ink != runInk || field != runField {
                    flush()
                    runInk = ink
                    runField = field
                }
                run.append(cell.glyph)
                claims.appendCoalescing(Self.claim(for: cell, column: column, row: row))
            }
            flush()
            lines.append(line)
        }
        var buffer = FrameBuffer(lines: lines, width: width, lineWidths: Array(repeating: width, count: height))
        buffer.opacityRegions = claims
        return buffer
    }

    /// What `cell` owes the compositor: its colours' alphas, or — for a cell
    /// stating neither — a field at 0, which hands the cell back to whatever
    /// is behind it.
    private static func claim(for cell: Cell, column: Int, row: Int) -> OpacityRegion? {
        if cell.isEmpty {
            return OpacityRegion.claim(offsetX: column, offsetY: row, width: 1, height: 1, inkAlpha: .max, fieldAlpha: 0)
        }
        return OpacityRegion.claim(
            offsetX: column, offsetY: row, width: 1, height: 1,
            inkAlpha: cell.ink?.alpha ?? .max, fieldAlpha: cell.field?.alpha ?? .max)
    }
}

// MARK: - Glyphs through a view's blank cells

extension FrameBuffer {
    /// The claims that let `layer`'s glyphs show through this buffer's blank
    /// cells, `layer` drawn behind it from the same top-left.
    ///
    /// Behind a view, a layer's GLYPH shows only where the view draws no cell,
    /// and padding is cells: blank ones. So wherever `layer` draws a glyph — a
    /// cap, a quadrant corner, a half block, a line — and this buffer's cell
    /// there shows nothing (a space with no field, no reverse and no line drawn
    /// across it), the cell is claimed at a field of 0: the compositor's
    /// "nothing at all", which leaves the layer's cell as it was. Everywhere
    /// else this buffer is in front, as over any background; a cell the layer
    /// paints whole is field, which shows through a blank cell anyway.
    ///
    /// - Parameter layer: The cells drawn behind this buffer.
    /// - Returns: The claims, coalesced.
    func claimsShowingGlyphs(of layer: ShapeCells) -> [OpacityRegion] {
        let columns = min(width, layer.width)
        var claims: [OpacityRegion] = []
        for (row, line) in lines.prefix(layer.height).enumerated() {
            let nothing = line.columnsShowingNothing(width: columns)
            for column in 0..<columns where nothing[column] && layer[column, row].glyph != " " {
                claims.appendCoalescing(
                    OpacityRegion.claim(offsetX: column, offsetY: row, width: 1, height: 1, inkAlpha: .max, fieldAlpha: 0))
            }
        }
        return claims
    }
}
