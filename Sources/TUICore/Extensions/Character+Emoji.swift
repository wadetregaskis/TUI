//  🖥️ TUI — A Terminal UI framework for Swift
//  Character+Emoji.swift
//
//  Which characters are emoji: drawn as a picture rather than in the text's
//  colour.
//
//  Created by Wade Tregaskis
//  License: MIT

extension Character {
    /// Whether this character asks to be drawn as an emoji: one that is an
    /// emoji by default (`🎉`, `✅`, a flag), one whose emoji presentation
    /// selector, U+FE0F, asks for it (`ℹ️`, `❤️`), or a keycap (`1️⃣`).
    ///
    /// A skin tone after a base makes an emoji too: a raised finger (U+261D)
    /// is text alone, and an emoji with one (`☝🏽`).
    ///
    /// `©` and `™` are not: they are text by default, and are emoji only with
    /// the selector. Nor is an ASCII digit, `#` or `*`, which Unicode counts
    /// as an emoji base only for the keycap it starts.
    package var isEmojiPresented: Bool {
        let scalars = unicodeScalars
        guard let first = scalars.first else { return false }
        // A keycap: the key, a digit or `#` or `*`, the selector, then U+20E3.
        if first.isASCII { return scalars.contains("\u{20E3}") }
        return first.properties.isEmojiPresentation
            || (first.properties.isEmoji && scalars.contains("\u{FE0F}"))
            || (first.properties.isEmojiModifierBase
                && scalars.dropFirst().contains { (0x1F3FB...0x1F3FF).contains($0.value) })
    }

    /// Whether a terminal draws this character in colours of its own, which no
    /// foreground colour reaches, so no fade does: an emoji
    /// (``isEmojiPresented``), or a bare pictograph from the supplementary
    /// planes (`🖥` without its selector), which terminals paint from a colour
    /// emoji font for want of a text glyph (`isBarePictographUnderAdvancer`).
    package var drawsInItsOwnColours: Bool {
        isEmojiPresented || isBarePictographUnderAdvancer
    }
}
