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
/// `▬` has no shape in the table and was blank, so `.dot` drew no fill at all. A blank
/// Braille cell is a dot there as a full one is, so a `.braille` track was dots
/// end to end. And `━` is `-` as `─` is, so the two rails of `.knob` read alike.
/// Everything else is left to the folding, which spells it as a `Text`'s
/// glyphs are spelled.
enum TrackGlyphs {
    /// `glyph` as a track draws it in ASCII: a heavy rail `=`, a blank
    /// Braille cell a space; any other glyph as it is. (A half block, `▌`, is
    /// the folding's `#`, as every block is.)
    static func ascii(_ glyph: Character) -> Character {
        switch glyph {
        case "▬", "━": "="
        case "\u{2800}": " "
        default: glyph
        }
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
