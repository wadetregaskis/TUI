//  🖥️ TUI — A Terminal UI framework for Swift
//  Character+PositionalDigit.swift
//
//  A typed character's value as a digit of a positional number, in any script.
//
//  Created by Wade Tregaskis
//  License: MIT

extension Character {
    /// This character's value as a digit of a positional decimal number — 0
    /// through 9 for `7`, `٣`, `३`, `７` — or `nil` for one that has a numeric
    /// value but cannot be typed into a positional field.
    ///
    /// `Character.isWholeNumber` is the wrong question in both directions. It is
    /// true for `Ⅷ` (8), `③` (3) and `万` (10000), none of which is a digit you
    /// can append to a field; and code that then read the character with
    /// `Int(_:)` or `Double(_:)`, which parse ASCII only, consumed `٣` and `३` —
    /// what those keyboard layouts actually produce — and read them as nothing.
    ///
    /// Unicode's own `numericType == .decimal` is exactly "decimal digit in a
    /// positional system", so this is derived from the character database
    /// rather than from a hand-written list of ranges that would go stale with
    /// each new script. Every such scalar has a value of 0-9 by definition.
    package var positionalDigitValue: Int? {
        let scalars = unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first,
            scalar.properties.numericType == .decimal,
            let value = scalar.properties.numericValue
        else { return nil }
        return Int(exactly: value)
    }
}
