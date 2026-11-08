//  🖥️ TUI — A Terminal UI framework for Swift
//  NumberText.swift
//
//  Numbers written at a fixed width or to fixed digits, without a printf
//  format.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - Integers at a width

extension BinaryInteger {
    /// The digits of this value in `radix`, at least `width` characters wide:
    /// zeros between the sign and the digits, as `%04d` and `%02X` pad, or
    /// with `padding: " "` spaces before the sign, as `%7d` does.
    ///
    /// What the package writes in place of those printf formats, which are
    /// unsafe (`String(unsafeFormat:)`): `0x0A` is `10.digits(width: 2, radix:
    /// 16, uppercase: true)`, `"0A"`.
    package func digits(width: Int, radix: Int = 10, uppercase: Bool = false, padding: Character = "0") -> String {
        let digits = String(magnitude, radix: radix, uppercase: uppercase)
        let sign = self < 0 ? "-" : ""
        let fill = String(repeating: padding, count: max(0, width - sign.count - digits.count))
        return padding == "0" ? sign + fill + digits : fill + sign + digits
    }
}

// MARK: - Fractions to fixed digits

extension FormatStyle where Self == FloatingPointFormatStyle<Double> {
    /// `digits` digits after a full stop, never grouped, in every locale:
    /// what `%.2f` writes, for text a program reads back — a stored value, a
    /// benchmark's report — rather than a person.
    ///
    /// It rounds as a person would, half to even on the shortest decimal that
    /// names the value, where printf rounds the binary value exactly: 0.15,
    /// stored as 0.1499…, is `0.2` here and `0.1` from `%.1f`. Text for a
    /// person wants the locale's own marks instead:
    /// `.number.precision(.fractionLength(2))`.
    package static func fixed(_ digits: Int) -> Self {
        .number.precision(.fractionLength(digits)).grouping(.never).locale(Locale(identifier: "en_US_POSIX"))
    }
}
