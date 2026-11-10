//  🖥️ TUI — A Terminal UI framework for Swift
//  Character+TypedText.swift
//
//  Which typed characters a text control puts in its text.
//
//  Created by Wade Tregaskis
//  License: MIT

extension Character {
    /// Whether a text control types this character when a key delivers it:
    /// anything but a control character, as a paste keeps anything but one.
    ///
    /// Not only letters, digits, punctuation, symbols and spaces. A terminal's
    /// input reaches the app a Unicode scalar at a time, so a character of
    /// several scalars arrives as its base and then keys that are each a mark
    /// or a format character alone: the joiners of 👨‍👩‍👧, the variation
    /// selector of ❤️, a Thai tone mark, a Persian zero-width non-joiner, an
    /// accent typed decomposed. Each merges into the character before it
    /// (``TextFieldHandler/insertCharacter(_:)``). An emoji newer than this
    /// build's Unicode tables, unassigned to them, is typed too.
    ///
    /// Whitespace stays in though it is a control character, as it always
    /// has: what a Return or a Tab key means is decided before a character
    /// gets here.
    var isTypedText: Bool {
        isWhitespace || !unicodeScalars.contains { $0.properties.generalCategory == .control }
    }
}
