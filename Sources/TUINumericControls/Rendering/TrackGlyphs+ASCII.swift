//  🖥️ TUI — A Terminal UI framework for Swift
//  TrackGlyphs+ASCII.swift
//
//  A track's glyphs where text is spelled in ASCII (`TUI_PLAIN_TEXT`): the few
//  whose folding at output says the wrong thing, chosen where the track is
//  drawn, as a toggle's `[x]` and a spinner's frames are.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// The ASCII a track draws in place of a glyph that folds badly at output.
///
/// The folding (`TerminalSymbols.ASCII`) knows a glyph, not what it is for.
/// `▬` has no shape in the table and was blank, so `.dot` drew no fill at all.
/// Everything else is left to the folding, which spells it as a `Text`'s
/// glyphs are spelled: there `━` is `=`, a heavy line, so the two rails of
/// `.knob` differ (`=====o-----`), and a blank Braille cell is a space, so a
/// `.braille` track's empty cells are not dots as its fill is. (Both were
/// this table's until the folding learned them, 2026-11-11.)
enum TrackGlyphs {
    /// `glyph` as a track draws it in ASCII: a bar `=`; any other glyph as it
    /// is. (A half block, `▌`, is the folding's `#`, as every block is.)
    static func ascii(_ glyph: Character) -> Character {
        glyph == "▬" ? "=" : glyph
    }

    /// Each glyph of `glyphs` as ``ascii(_:)`` draws it.
    static func ascii(_ glyphs: String) -> String {
        String(glyphs.map(ascii))
    }
}

extension TrackConfiguration {
    /// This recipe with its glyphs as a track draws them in ASCII
    /// (``TrackGlyphs/ascii(_:)``); its colours as they are.
    var spelledInASCII: TrackConfiguration {
        var config = self
        config.fill = TrackGlyphs.ascii(fill)
        config.leadingEdge = leadingEdge?.map(TrackGlyphs.ascii)
        if case .pattern(let pattern) = background {
            config.background = .pattern(TrackGlyphs.ascii(pattern))
        }
        return config
    }
}
