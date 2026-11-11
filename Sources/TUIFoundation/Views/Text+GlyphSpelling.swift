//  🖥️ TUI — A Terminal UI framework for Swift
//  Text+GlyphSpelling.swift
//
//  The transliteration's last step (`TUI_PLAIN_TEXT=transliterate`): what no
//  transform made ASCII but that has an ASCII form. Before it, an SF Symbol was
//  folded at output to two blank cells, and a `❤` typed without its selector
//  to one.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIStrings

/// Pictures and shapes in words: what the transliteration leaves that is not
/// ASCII, spelled where it has a form, in this order —
/// - an SF Symbol's glyph as the symbol's name between colons, as an emoji's
///   is, without its `fill` (how it looks, not what it is): `star.fill` is
///   `:star:`, `square.and.arrow.up` `:square.and.arrow.up:`. Only where the
///   name table is (Apple platforms), as only there is there a glyph;
/// - one of the framework's shapes, as `TerminalSymbols.ASCII` writes it
///   (`▶` `>`, `⟦` `[`), the same as the folding at output, so a shape is the
///   same in a `Text` as in a stepper. Before an emoji's name, since `▶` and
///   `↔` are emoji too;
/// - an emoji that is text by default (``EmojiSpelling/textSpelling(of:)``).
enum GlyphSpelling {
    /// `string` with each such character spelled; the same string where it
    /// has none.
    static func spelled(_ string: String) -> String {
        guard string.utf8.contains(where: { $0 >= 0x80 }) else { return string }
        var spelled = ""
        for character in string {
            if !character.isASCII, let ascii = spelling(of: character) {
                spelled += ascii
            } else {
                spelled.append(character)
            }
        }
        return spelled
    }

    /// `character` spelled, or `nil` where it has no form here.
    static func spelling(of character: Character) -> String? {
        guard let first = character.unicodeScalars.first else { return nil }
        if let name = SFSymbol.name(ofGlyph: first) { return ":" + shortName(name) + ":" }
        if let shape = TerminalSymbols.ASCII.spelling(of: first) { return shape }
        return EmojiSpelling.textSpelling(of: character)
    }

    /// A symbol's name without `fill`, which says how it is drawn.
    private static func shortName(_ name: String) -> String {
        let parts = name.split(separator: ".").filter { $0 != "fill" }
        return parts.isEmpty ? name : parts.joined(separator: ".")
    }
}
