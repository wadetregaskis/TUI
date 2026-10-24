//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FrameBuffer+Frost.swift
//
//  A material's frost (owner ruling O5-FROSTED, 2026-10-23, shipped as (c)):
//  what is behind a material loses its glyphs, and its fields are tinted by the
//  material as before.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling

// MARK: - Marking

extension FrameBuffer {
    /// This buffer with its translucent FIELD claims marked as frosting what is
    /// behind them (``OpacityRegion/frosts``): the cells a material painted,
    /// which claim its surface's alpha. A claim at a field of 0 — a cell the
    /// drawing does not reach, handed back to what is behind — and an opaque
    /// one are left alone.
    func markingFrost() -> FrameBuffer {
        var result = self
        result.opacityRegions = opacityRegions.map { claim in
            guard claim.fieldOpacity > 0, claim.fieldOpacity < 1 else { return claim }
            var frosted = claim
            frosted.frosts = true
            return frosted
        }
        return result
    }
}

// MARK: - Frosting what is behind

extension FrameBuffer {
    /// `cell` — a cell behind a material's translucent field — as the frost
    /// leaves it: its field alone, the glyph and whatever the glyph wore (its
    /// ink, an underline) dropped (`Opacity as composition.md` §111).
    ///
    /// The field is the one the cell shows, kept as it is spelled: a reversed
    /// cell's (`cells(in:)` has already put it in `background`, and
    /// `isReversed` stays for the spelling), the terminal's own where the cell
    /// states it, and none where it names none, which the blend reads as the
    /// surface. The material's tint is laid over it as over any field; nothing
    /// is averaged with the cells around it.
    static func frosted(_ cell: RowCell) -> RowCell {
        var blank = cell
        blank.character = " "
        blank.foreground = nil
        // The field's slot exactly as the cell spells it, and nothing else.
        blank.style = SGRState()
        blank.style.setBackground(cell.style.backgroundColour)
        return blank
    }
}
