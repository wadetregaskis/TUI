//  🖥️ TUIkit — Terminal UI Kit for Swift
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
        if let (scalar, length) = Self.reference(in: source, at: position) {
            appendText(.scalar(scalar))
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
            if atoms[index].is("&"), let (scalar, length) = reference(in: atoms, at: index) {
                result.append(.scalar(scalar))
                index += length
            } else {
                result.append(atoms[index])
                index += 1
            }
        }
        return result
    }

    /// The reference starting with the `&` at `start`: the character it names
    /// and how many atoms it spans, `;` included.
    ///
    /// Numeric references are CommonMark's: up to seven decimal or six hex
    /// digits, with zero and anything that is not a Unicode scalar read as
    /// U+FFFD. Named ones are looked up in ``namedReferences``.
    static func reference(in atoms: [Atom], at start: Int) -> (Unicode.Scalar, Int)? {
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
            return (decoded ?? "\u{FFFD}", index + 1 - start)
        }
        var name = ""
        while let letter = scalar(at: index), isASCIIAlphanumeric(letter), name.unicodeScalars.count < 32 {
            name.unicodeScalars.append(letter)
            index += 1
        }
        guard let first = name.unicodeScalars.first, isASCIILetter(first), scalar(at: index) == ";",
            let decoded = namedReferences[name]
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

    /// The named references a user-interface string plausibly carries: HTML's
    /// markup escapes, spaces and dashes, quotation marks, the common symbols,
    /// arrows and mathematical operators.
    ///
    /// Foundation knows all 2,125 of HTML's names. A name missing here stays
    /// as written — `&Aacute;` shows as `&Aacute;` — which is the one way this
    /// parse can differ from SwiftUI's on text Foundation accepts. The whole
    /// table is 20 KB of source; see the decisions document.
    static let namedReferences: [String: Unicode.Scalar] = Dictionary(
        uniqueKeysWithValues: namedReferenceList.lazy.map { ($0.0.description, $0.1) })

    /// ``namedReferences`` as written. `StaticString` names, made `String`s once
    /// as the dictionary is built: as a `[String: Unicode.Scalar]` literal each
    /// name was a `String` the optimiser assembled element by element, 69 ms of
    /// a release build's SIL optimisation against 31 ms for this list and the
    /// dictionary built from it (2026-10-07).
    private static let namedReferenceList: [(StaticString, Unicode.Scalar)] = [
        ("amp", "&"), ("lt", "<"), ("gt", ">"), ("quot", "\""), ("apos", "'"),
        ("nbsp", "\u{A0}"), ("ensp", "\u{2002}"), ("emsp", "\u{2003}"), ("thinsp", "\u{2009}"),
        ("zwnj", "\u{200C}"), ("zwj", "\u{200D}"), ("shy", "\u{AD}"),
        ("ndash", "\u{2013}"), ("mdash", "\u{2014}"), ("hyphen", "\u{2010}"), ("minus", "\u{2212}"),
        ("lsquo", "\u{2018}"), ("rsquo", "\u{2019}"), ("sbquo", "\u{201A}"),
        ("ldquo", "\u{201C}"), ("rdquo", "\u{201D}"), ("bdquo", "\u{201E}"),
        ("laquo", "\u{AB}"), ("raquo", "\u{BB}"), ("lsaquo", "\u{2039}"), ("rsaquo", "\u{203A}"),
        ("hellip", "\u{2026}"), ("bull", "\u{2022}"), ("middot", "\u{B7}"), ("prime", "\u{2032}"),
        ("Prime", "\u{2033}"), ("dagger", "\u{2020}"), ("Dagger", "\u{2021}"), ("permil", "\u{2030}"),
        ("copy", "\u{A9}"), ("reg", "\u{AE}"), ("trade", "\u{2122}"), ("sect", "\u{A7}"), ("para", "\u{B6}"),
        ("deg", "\u{B0}"), ("micro", "\u{B5}"), ("plusmn", "\u{B1}"), ("times", "\u{D7}"), ("divide", "\u{F7}"),
        ("frac12", "\u{BD}"), ("frac14", "\u{BC}"), ("frac34", "\u{BE}"),
        ("sup1", "\u{B9}"), ("sup2", "\u{B2}"), ("sup3", "\u{B3}"),
        ("cent", "\u{A2}"), ("pound", "\u{A3}"), ("euro", "\u{20AC}"), ("yen", "\u{A5}"), ("curren", "\u{A4}"),
        ("iexcl", "\u{A1}"), ("iquest", "\u{BF}"), ("ordf", "\u{AA}"), ("ordm", "\u{BA}"), ("not", "\u{AC}"),
        ("brvbar", "\u{A6}"), ("uml", "\u{A8}"), ("acute", "\u{B4}"), ("cedil", "\u{B8}"), ("macr", "\u{AF}"),
        ("larr", "\u{2190}"), ("uarr", "\u{2191}"), ("rarr", "\u{2192}"), ("darr", "\u{2193}"), ("harr", "\u{2194}"),
        ("lArr", "\u{21D0}"), ("uArr", "\u{21D1}"), ("rArr", "\u{21D2}"), ("dArr", "\u{21D3}"), ("hArr", "\u{21D4}"),
        ("crarr", "\u{21B5}"),
        ("le", "\u{2264}"), ("ge", "\u{2265}"), ("ne", "\u{2260}"), ("asymp", "\u{2248}"), ("equiv", "\u{2261}"),
        ("infin", "\u{221E}"), ("sum", "\u{2211}"), ("prod", "\u{220F}"), ("radic", "\u{221A}"), ("part", "\u{2202}"),
        ("forall", "\u{2200}"), ("exist", "\u{2203}"), ("empty", "\u{2205}"), ("isin", "\u{2208}"),
        ("notin", "\u{2209}"), ("and", "\u{2227}"), ("or", "\u{2228}"), ("cap", "\u{2229}"), ("cup", "\u{222A}"),
        ("sub", "\u{2282}"), ("sup", "\u{2283}"), ("int", "\u{222B}"), ("there4", "\u{2234}"),
        ("loz", "\u{25CA}"), ("spades", "\u{2660}"), ("clubs", "\u{2663}"), ("hearts", "\u{2665}"),
        ("diams", "\u{2666}"), ("check", "\u{2713}"), ("cross", "\u{2717}"), ("star", "\u{2606}"),
        ("starf", "\u{2605}"),
        ("alpha", "\u{3B1}"), ("beta", "\u{3B2}"), ("gamma", "\u{3B3}"), ("delta", "\u{3B4}"),
        ("epsilon", "\u{3B5}"), ("lambda", "\u{3BB}"), ("mu", "\u{3BC}"), ("pi", "\u{3C0}"), ("sigma", "\u{3C3}"),
        ("tau", "\u{3C4}"), ("phi", "\u{3C6}"), ("omega", "\u{3C9}"), ("Delta", "\u{394}"), ("Sigma", "\u{3A3}"),
        ("Omega", "\u{3A9}"),
    ]
}
