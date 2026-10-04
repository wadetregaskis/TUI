//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InlineMarkdown.swift
//
//  The inline Markdown SwiftUI applies to a `Text` made from a key: CommonMark's
//  inline syntax plus GitHub's strikethrough and autolinks, as Foundation's
//  `inlineOnlyPreservingWhitespace` parse reads it. Foundation's parser is not
//  there on Linux, so this is TUIkit's own, written to give the same runs.
//
//  Created by Wade Tregaskis
//  License: MIT

/// A parse of inline Markdown into styled spans.
///
/// SwiftUI draws a `Text` made from a key as Foundation's
/// `AttributedString(markdown:options:)` reads it with
/// `.inlineOnlyPreservingWhitespace` — measured on macOS 15.8, where the two
/// rendered identically for every case tried, a hundred of them. That parse is
/// Darwin's only: swift-foundation on Linux has neither the initializer nor
/// `InlinePresentationIntent`. So this one is TUIkit's, and it is the
/// CommonMark inline algorithm (delimiter runs, the rule of three, brackets)
/// with the two GitHub extensions Foundation turns on: `~`/`~~` strikethrough
/// and bare-URL autolinks.
///
/// What it reads, as Foundation does:
///
/// - `*a*` and `_a_` emphasis, `**a**` and `__a__` strong, nested and
///   overlapping as CommonMark resolves them;
/// - `~a~` and `~~a~~` strikethrough (three or more tildes are literal);
/// - `` `code` `` spans, of any backtick length, with a space either side
///   stripped;
/// - `[label](destination "title")` links, `<scheme:…>` and `<email>`
///   autolinks, and bare `https://…`, `www.…` and `name@host.domain` text;
/// - `![alt](source)`, which SwiftUI draws as its alt text, and
///   `^[text](attributes)`, which draws its text (TUIkit has no inflection);
/// - backslash escapes, a backslash before a newline (a line break), and
///   character references (`&amp;`, `&#65;`, `&#x42;`).
///
/// Everything else is text, whitespace included: headings, lists, quotes and
/// HTML are not inline syntax, and a delimiter with nothing to pair with stays
/// on the screen.
///
/// The input is a list of ``Atom``s rather than a string so that an
/// interpolated value can sit in the source as ONE opaque element: SwiftUI
/// parses the key's format and substitutes the values afterwards (measured —
/// `Text("**\(name)**")` is bold whatever `name` holds, and a `*` inside it is
/// drawn, not parsed), so a value is a letter to the delimiter rules and never
/// part of the syntax.
enum InlineMarkdown {
    /// The styles a span carries. Code is kept apart from plain text although a
    /// terminal draws both alike, because what a code span contains is never
    /// autolinked.
    struct Traits: OptionSet, Hashable, Sendable {
        let rawValue: UInt8

        static let emphasized = Self(rawValue: 1 << 0)
        static let strong = Self(rawValue: 1 << 1)
        static let code = Self(rawValue: 1 << 2)
        static let strikethrough = Self(rawValue: 1 << 3)
    }

    /// One element of the source: a character, or the slot an interpolated
    /// argument fills.
    enum Atom: Hashable, Sendable {
        case scalar(Unicode.Scalar)
        case argument(Int)
    }

    /// A run of the parsed text with one set of traits and at most one link.
    struct Span: Equatable, Sendable {
        /// The span's text, arguments in their slots.
        var atoms: [Atom]
        /// Its emphasis.
        var traits: Traits
        /// Where it links, arguments in their slots; `nil` for no link.
        var link: [Atom]?
    }

    /// The spans `source` parses to, adjacent spans of equal style merged.
    static func parse(_ source: [Atom]) -> [Span] {
        var parser = InlineMarkdownParser(source: source)
        return parser.run()
    }

    /// The spans `string` parses to, for a source with no arguments.
    static func parse(_ string: String) -> [Span] {
        parse(string.unicodeScalars.map(Atom.scalar))
    }

    /// Whether `template` contains anything the parse could act on.
    ///
    /// A byte scan, so the overwhelming majority of keys — `"Save"`,
    /// `"Name:"` — never reach the parser at all: every construct the parser
    /// knows starts with one of these bytes, or is an autolink, which needs a
    /// `://`, a `www.` or an `@`.
    static func mightContainMarkup(_ template: String) -> Bool {
        // The three bytes before this one, in locals: this runs for every key a
        // `Text` is built from, every frame, so it allocates nothing.
        var last: UInt8 = 0
        var secondLast: UInt8 = 0
        var thirdLast: UInt8 = 0
        let slash = UInt8(ascii: "/")
        let letterW = UInt8(ascii: "w")
        for byte in template.utf8 {
            switch byte {
            case UInt8(ascii: "*"), UInt8(ascii: "_"), UInt8(ascii: "`"), UInt8(ascii: "~"),
                UInt8(ascii: "["), UInt8(ascii: "<"), UInt8(ascii: "\\"), UInt8(ascii: "&"),
                UInt8(ascii: "@"):
                return true
            case slash where last == slash && secondLast == UInt8(ascii: ":"):
                // "://" — a URL autolink's scheme separator.
                return true
            case UInt8(ascii: ".") where last == letterW && secondLast == letterW && thirdLast == letterW:
                // "www." — a www autolink, lowercase only, as cmark-gfm matches it.
                return true
            default:
                break
            }
            thirdLast = secondLast
            secondLast = last
            last = byte
        }
        return false
    }
}

// MARK: - Character classes

extension InlineMarkdown.Atom {
    /// The scalar, or `nil` for an argument.
    var scalar: Unicode.Scalar? {
        if case .scalar(let scalar) = self { scalar } else { nil }
    }

    /// CommonMark's Unicode whitespace: a space separator, tab, line feed, form
    /// feed or carriage return. An argument is not whitespace.
    var isWhitespace: Bool {
        guard let scalar else { return false }
        switch scalar.value {
        case 0x09, 0x0A, 0x0C, 0x0D, 0x20: return true
        default: return scalar.properties.generalCategory == .spaceSeparator
        }
    }

    /// CommonMark's punctuation: ASCII punctuation, or a Unicode punctuation
    /// category. An argument is not punctuation — to the delimiter rules it is
    /// a letter, which is what makes `**\(name)**` bold whatever `name` is.
    var isPunctuation: Bool {
        guard let scalar else { return false }
        if scalar.isASCII { return InlineMarkdownParser.isASCIIPunctuation(scalar) }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
            .initialPunctuation, .finalPunctuation, .otherPunctuation:
            return true
        default:
            return false
        }
    }

    /// Whether this is the scalar `character`.
    func `is`(_ character: Unicode.Scalar) -> Bool {
        scalar == character
    }
}
