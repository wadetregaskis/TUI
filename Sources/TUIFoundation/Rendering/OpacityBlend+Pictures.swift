//  🖥️ TUI — A Terminal UI framework for Swift
//  OpacityBlend+Pictures.swift
//
//  A translucent layer over a picture the terminal draws: the cells under it
//  re-pointed at a copy of the picture with the layer applied
//  (`Terminal graphics protocols.md` §14).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

extension FrameBuffer {
    /// ``overPicture(_:under:alpha:images:)`` for the cell at `column` of
    /// `cells` — `nil` where there is no such cell, no alpha over it, or no
    /// store to draw a copy from. The one call `blendedSpan` makes per covered
    /// cell.
    static func overPicture(
        _ cells: ArraySlice<RowCell?>, at column: Int, under cell: RowCell, alpha: CellAlpha?,
        images: TerminalImageStore?
    ) -> RowCell? {
        guard let images, let alpha, cells.indices.contains(column), let behind = cells[column] else { return nil }
        return overPicture(behind, under: cell, alpha: alpha, images: images)
    }

    /// What a cell of a translucent layer, `cell` at `alpha`, makes of the
    /// picture cell `behind` — or `nil` where `behind` is not a picture this
    /// app put in the terminal.
    ///
    /// - A cell painting nothing — no glyph, no field, no frost — leaves the
    ///   picture as it is.
    /// - One painting a field, or frosting what is behind it, draws a copy of
    ///   the picture, blurred where it frosts and mixed toward the field by its
    ///   alpha: the same row and column of the copy (``TerminalImageStore/derived(_:by:)``).
    /// - One drawing a glyph cannot also hold a picture, so the glyph stands on
    ///   the copy's average colour there.
    static func overPicture(
        _ behind: RowCell, under cell: RowCell, alpha: CellAlpha, images: TerminalImageStore
    ) -> RowCell? {
        guard let ink = behind.foreground?.rgbComponents,
            let picture = KittyGraphics.placeholderCell(behind.character, foreground: ink)
        else { return nil }
        // The paint over the picture: a painter's translucent field where one is
        // under the content — a material, a `.background` — at the alpha its claim
        // lets through, the topmost of them; otherwise the cell's own field at its
        // alphas. A painter's field the cell shows is the cell's background.
        let painter = alpha.painterFields.first
        let field = (painter?.colour ?? cell.background)?.rgbComponents
        let fraction = field == nil ? 0 : painter.map { $0.layer * $0.field } ?? alpha.layer * alpha.field
        let paintsGlyph = cell.character != " " || cell.style.paintsInkOnBlankCell
        let transform = ImageTransform(blurs: alpha.frosts, toward: field ?? (0, 0, 0), fraction: fraction)
        guard transform.blurs || transform.amount > 0 || paintsGlyph else { return behind }
        guard let copy = images.derived(picture, by: transform) else { return nil }
        if paintsGlyph {
            guard let average = images.average(of: picture, by: transform) else { return nil }
            var drawn = cell
            // An average, not a colour a control picks: what the picture shows there.
            // swiftlint:disable:next framework_colour_literal
            let ground = Color.rgb(average.red, average.green, average.blue)
            drawn.background = ground
            drawn.style = drawn.style.settingBackground(ground)
            return drawn
        }
        var drawn = behind
        drawn.character = copy.character
        // The copy's id, spelled as the picture's own cells spell theirs.
        // swiftlint:disable:next framework_colour_literal
        let id = Color.rgb(UInt8((copy.id >> 16) & 0xFF), UInt8((copy.id >> 8) & 0xFF), UInt8(copy.id & 0xFF))
        drawn.foreground = id
        drawn.style = drawn.style.settingForeground(id, depth: .truecolor)
        return drawn
    }
}
