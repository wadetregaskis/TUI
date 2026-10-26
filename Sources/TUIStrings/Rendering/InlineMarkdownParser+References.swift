//  🖥️ TUI — A Terminal UI framework for Swift
//  InlineMarkdownParser+References.swift
//
//  Character references — `&amp;`, `&#65;`, `&#x42;` — in text and in link
//  destinations.
//
//  Created by Wade Tregaskis
//  License: MIT

extension InlineMarkdownParser {
    /// A character reference at ``position``, decoded into the text, or a
    /// literal `&`.
    mutating func parseReference() {
        if let (scalars, length) = Self.reference(in: source, at: position) {
            for scalar in scalars { appendText(.scalar(scalar)) }
            position += length
        } else {
            appendText(.scalar("&"))
            position += 1
        }
    }

    /// `atoms` with every character reference decoded.
    static func decodingReferences(in atoms: [Atom]) -> [Atom] {
        guard atoms.contains(where: { $0.is("&") }) else { return atoms }
        var result: [Atom] = []
        var index = 0
        while index < atoms.count {
            if atoms[index].is("&"), let (scalars, length) = reference(in: atoms, at: index) {
                result.append(contentsOf: scalars.map { .scalar($0) })
                index += length
            } else {
                result.append(atoms[index])
                index += 1
            }
        }
        return result
    }

    /// The reference starting with the `&` at `start`: the scalars it names
    /// (two, for a few of HTML's names) and how many atoms it spans, `;`
    /// included.
    ///
    /// Numeric references are CommonMark's: up to seven decimal or six hex
    /// digits, with zero and anything that is not a Unicode scalar read as
    /// U+FFFD. Named ones are HTML's, every one Foundation's parser knows
    /// (``HTMLEntities``).
    static func reference(in atoms: [Atom], at start: Int) -> ([Unicode.Scalar], Int)? {
        var index = start + 1
        func scalar(at offset: Int) -> Unicode.Scalar? {
            offset < atoms.count ? atoms[offset].scalar : nil
        }
        if scalar(at: index) == "#" {
            index += 1
            var radix: UInt32 = 10
            var maxDigits = 7
            if let marker = scalar(at: index), marker == "x" || marker == "X" {
                radix = 16
                maxDigits = 6
                index += 1
            }
            var value: UInt32 = 0
            var digits = 0
            while let digit = scalar(at: index), let digitValue = Self.digitValue(digit, radix: radix) {
                guard digits < maxDigits else { return nil }
                value = value * radix + digitValue
                digits += 1
                index += 1
            }
            guard digits > 0, scalar(at: index) == ";" else { return nil }
            let decoded = value == 0 ? nil : Unicode.Scalar(value)
            return ([decoded ?? "\u{FFFD}"], index + 1 - start)
        }
        var name = ""
        while let letter = scalar(at: index), isASCIIAlphanumeric(letter), name.unicodeScalars.count < 32 {
            name.unicodeScalars.append(letter)
            index += 1
        }
        guard let first = name.unicodeScalars.first, isASCIILetter(first), scalar(at: index) == ";",
            let decoded = HTMLEntities.scalars(named: name)
        else { return nil }
        return (decoded, index + 1 - start)
    }

    private static func digitValue(_ scalar: Unicode.Scalar, radix: UInt32) -> UInt32? {
        switch scalar.value {
        case 0x30...0x39: return scalar.value - 0x30
        case 0x41...0x46 where radix == 16: return scalar.value - 0x41 + 10
        case 0x61...0x66 where radix == 16: return scalar.value - 0x61 + 10
        default: return nil
        }
    }
}
