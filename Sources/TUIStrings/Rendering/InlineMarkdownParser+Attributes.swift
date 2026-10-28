//  🖥️ TUI — A Terminal UI framework for Swift
//  InlineMarkdownParser+Attributes.swift
//
//  The `(…)` of Apple's `^[text](attributes)`: where it ends, as Foundation
//  finds the end, and the `key: value` list inside it, read as Foundation's
//  grammar for it (JSON5, without the braces) reads it.
//
//  Created by Wade Tregaskis
//  License: MIT

extension InlineMarkdownParser {
    /// The `(…)` of Apple's `^[text](attributes)`, or `nil` if no `(` follows
    /// the `]`. Leaves ``position`` past the `)` on success.
    ///
    /// It ends at the `)` that balances the `(`, a backslash escaping the
    /// character after it — and nothing else. Quotes shelter no parenthesis,
    /// and attributes that do not parse are no reason to keep the text
    /// literal: Foundation draws the bracket text whatever the attributes say,
    /// `^[x](a: ")")` closing at the quoted `)` and `^[x](a: "(")` left
    /// literal, unbalanced (measured on macOS 15.8, B86's open item;
    /// `Tools/SwiftUIProbes/Markdown attribute syntax/attrs.swift`).
    ///
    /// What is inside is then read as a `key: value` list
    /// (``AttributeList``): every pair that reads, or none at all when the
    /// list does not — where Foundation, given a scope that reads any of its
    /// keys, throws (`decode.swift` beside `attrs.swift`). A `Text` cannot
    /// throw, so its text is drawn plain. An interpolated value inside the
    /// parentheses makes the list one that does not read: the parse is the
    /// template's, before any value is known, so there is nothing to decode.
    mutating func parseAttributeTail() -> [InlineMarkdown.Attribute]? {
        guard atom(at: position)?.is("(") == true else { return nil }
        let start = position + 1
        var index = start
        var depth = 0
        while let atom = atom(at: index) {
            defer { index += 1 }
            guard let scalar = atom.scalar else { continue }
            switch scalar {
            case "\\": index += 1
            case "(": depth += 1
            case ")":
                if depth == 0 {
                    position = index + 1
                    return AttributeList.decode(source[start..<index])
                }
                depth -= 1
            default: break
            }
        }
        return nil
    }
}

/// A reading of the `key: value, …` list inside a `^[…](…)`.
///
/// The grammar is JSON5's members, as Foundation's decoder reads them
/// (measured, `Tools/SwiftUIProbes/Markdown attribute syntax/decode.swift`):
/// a key bare or quoted, a value a string in either quotes, a number, `true`,
/// `false`, `null`, an object or an array; a trailing comma; `//` and `/* */`
/// comments. Two liberties, both for a `Text` that cannot throw: an unquoted
/// value is any run of characters JSON5 would not stop at, so a name such as
/// `red` reads where Foundation wants `"red"`; and an object or array is
/// stepped over, its pair dropped, since no key a `Text` reads takes one.
struct AttributeList {
    typealias Attribute = InlineMarkdown.Attribute

    private let scalars: [Unicode.Scalar]
    private var index = 0

    private init(_ scalars: [Unicode.Scalar]) {
        self.scalars = scalars
    }

    /// The pairs `atoms` hold, in order, duplicates kept; empty when they do
    /// not read as a list, or hold an interpolated value.
    static func decode(_ atoms: ArraySlice<InlineMarkdown.Atom>) -> [Attribute] {
        var scalars: [Unicode.Scalar] = []
        scalars.reserveCapacity(atoms.count)
        for atom in atoms {
            guard let scalar = atom.scalar else { return [] }
            scalars.append(scalar)
        }
        var list = Self(scalars)
        return list.members() ?? []
    }

    // MARK: Members

    private mutating func members() -> [Attribute]? {
        var result: [Attribute] = []
        skipSpace()
        while index < scalars.count {
            guard let key = quoted() ?? word() else { return nil }
            skipSpace()
            guard take(":") else { return nil }
            skipSpace()
            if let opening = peek, opening == "{" || opening == "[" {
                guard skipCompound() else { return nil }
            } else if let value = quoted() {
                result.append(Attribute(key: key, value: .string(value)))
            } else if let value = word() {
                result.append(Attribute(key: key, value: .word(value)))
            } else {
                return nil
            }
            skipSpace()
            guard index < scalars.count else { break }
            guard take(",") else { return nil }
            skipSpace()
        }
        return result
    }

    // MARK: Tokens

    private var peek: Unicode.Scalar? {
        index < scalars.count ? scalars[index] : nil
    }

    private mutating func take(_ scalar: Unicode.Scalar) -> Bool {
        guard peek == scalar else { return false }
        index += 1
        return true
    }

    /// Whitespace, and JSON5's comments.
    private mutating func skipSpace() {
        while let scalar = peek {
            if scalar.properties.isWhitespace || scalar == "\u{FEFF}" {
                index += 1
            } else if scalar == "/", index + 1 < scalars.count, scalars[index + 1] == "/" {
                while let next = peek, next != "\n", next != "\r" { index += 1 }
            } else if scalar == "/", index + 1 < scalars.count, scalars[index + 1] == "*" {
                index += 2
                while index < scalars.count, !(scalars[index] == "*" && index + 1 < scalars.count && scalars[index + 1] == "/") {
                    index += 1
                }
                index = min(index + 2, scalars.count)
            } else {
                return
            }
        }
    }

    /// The characters that end an unquoted word: JSON5's punctuation, a
    /// quote, a parenthesis, and whitespace.
    private static func endsWord(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case ",", ":", "{", "}", "[", "]", "(", ")", "\"", "'": true
        default: scalar.properties.isWhitespace
        }
    }

    /// An unquoted word at ``index``, or `nil` if none starts here.
    private mutating func word() -> String? {
        let start = index
        while let scalar = peek, !Self.endsWord(scalar) { index += 1 }
        guard index > start else { return nil }
        var word = String.UnicodeScalarView()
        word.append(contentsOf: scalars[start..<index])
        return String(word)
    }

    /// A quoted string at ``index``, its escapes decoded — JSON's, and
    /// JSON5's `\'` and line continuation — or `nil` if none starts here or
    /// it does not end. An escape JSON5 lacks fails it, as `\)` fails
    /// Foundation's (measured).
    private mutating func quoted() -> String? {
        guard let opening = peek, opening == "\"" || opening == "'" else { return nil }
        var result = String.UnicodeScalarView()
        var cursor = index + 1
        while cursor < scalars.count {
            let scalar = scalars[cursor]
            cursor += 1
            if scalar == opening {
                index = cursor
                return String(result)
            }
            guard scalar == "\\" else {
                result.append(scalar)
                continue
            }
            guard cursor < scalars.count else { return nil }
            let escaped = scalars[cursor]
            cursor += 1
            switch escaped {
            case "\"", "'", "\\", "/": result.append(escaped)
            case "b": result.append("\u{08}")
            case "f": result.append("\u{0C}")
            case "n": result.append("\n")
            case "r": result.append("\r")
            case "t": result.append("\t")
            case "\n", "\u{2028}", "\u{2029}": break
            case "u":
                guard cursor + 4 <= scalars.count,
                    let value = UInt32(String(String.UnicodeScalarView(scalars[cursor..<(cursor + 4)])), radix: 16),
                    let decoded = Unicode.Scalar(value)
                else { return nil }
                result.append(decoded)
                cursor += 4
            default: return nil
            }
        }
        return nil
    }

    /// Steps over an object or array at ``index``, nested ones and strings
    /// inside it included; `false` if it does not close.
    private mutating func skipCompound() -> Bool {
        var depth = 0
        while let scalar = peek {
            switch scalar {
            case "\"", "'":
                guard quoted() != nil else { return false }
                continue
            case "{", "[": depth += 1
            case "}", "]":
                depth -= 1
                if depth == 0 {
                    index += 1
                    return true
                }
            default: break
            }
            index += 1
        }
        return false
    }
}
