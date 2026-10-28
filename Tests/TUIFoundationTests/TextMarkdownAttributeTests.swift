//  🖥️ TUI — A Terminal UI framework for Swift
//  TextMarkdownAttributeTests.swift
//
//  What the keys of a `^[text](key: value, …)` in a `Text`'s key draw: each
//  exactly what the `Text` modifier it names does. TUI's own vocabulary, not
//  SwiftUI's (Deliberate deviations T3); the parse of the list is
//  `InlineMarkdownAttributeTests`'.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport

extension TextMarkdownTests {
    /// The style of `word`'s run in `text`, or `nil` if no run is `word`.
    private func style(of word: String, in text: Text) -> TextStyle? {
        text.runs?.first { $0.text == word }?.style
    }

    /// What `modify` does to a `Text`'s style: the style a key should give.
    private func modified(_ modify: (Text) -> Text) -> TextStyle {
        modify(Text(verbatim: "x")).style
    }

    @Test("Each key styles its text as the modifier it names does")
    func eachKey() {
        var background = TextStyle()
        background.backgroundColor = .blue
        let cases: [(key: LocalizedStringKey, style: TextStyle)] = [
            ("a ^[x](foregroundColor: red) b", modified { $0.foregroundStyle(.red) }),
            ("a ^[x](backgroundColor: blue) b", background),
            ("a ^[x](underlineStyle: true) b", modified { $0.underline() }),
            ("a ^[x](underlineStyle: false) b", modified { $0.underline(false) }),
            ("a ^[x](underlineStyle: curly) b", modified { $0.underline(pattern: .curly) }),
            ("a ^[x](underlineStyle: \"dashDot\") b", modified { $0.underline(pattern: .dashDot) }),
            ("a ^[x](underlineColor: red) b", modified { $0.underline(color: .red) }),
            ("a ^[x](strikethroughStyle: true) b", modified { $0.strikethrough() }),
            ("a ^[x](strikethroughStyle: dot) b", modified { $0.strikethrough(pattern: .dot) }),
            ("a ^[x](strikethroughColor: green) b", modified { $0.strikethrough(color: .green) }),
            ("a ^[x](font: headline) b", modified { $0.font(.headline) }),
            ("a ^[x](font: caption2) b", modified { $0.font(.caption2) }),
            ("a ^[x](fontWeight: light) b", modified { $0.fontWeight(.light) }),
            ("a ^[x](fontWeight: black) b", modified { $0.fontWeight(.black) }),
            ("a ^[x](dim: true) b", modified { $0.dim() }),
            ("a ^[x](dim: false) b", modified { $0.dim(false) }),
            ("a ^[x](blink: true) b", modified { $0.blink() }),
            ("a ^[x](inverse: true) b", modified { $0.inverted() }),
            ("a ^[x](textScale: secondary) b", modified { $0.textScale(.secondary) }),
        ]
        for (key, expected) in cases {
            let text = Text(key)
            #expect(text.content == "a x b", "\(key)")
            #expect(style(of: "x", in: text) == expected, "\(key)")
        }
    }

    @Test("A colour is a Color's name, a palette role, or #rgb / #rrggbb")
    func colourValues() {
        let cases: [(value: String, color: Color)] = [
            ("magenta", .magenta), ("gray", .gray), ("default", .default), ("primary", .primary),
            ("secondary", .secondary), ("accentColor", .accentColor), ("accent", .palette.accent),
            ("palette.info", .palette.info), ("foregroundTertiary", .palette.foregroundTertiary),
            ("\"error\"", .error), ("#ff8000", .rgb(255, 128, 0)), ("'#F80'", .rgb(255, 136, 0)),
        ]
        for (value, color) in cases {
            // Built as a `String` first: a literal with an interpolation would
            // make `value` the key's argument, not its text.
            let source = "^[x](foregroundColor: \(value))"
            let text = Text(LocalizedStringKey(source))
            #expect(text.runs?.first?.style == modified { $0.foregroundStyle(color) }, "\(value)")
        }
        for name in ["chartreuse", "Red", "ff0000", "#ff00", "#gggggg", "palette.", "clear", "bad"] {
            #expect(Color.named(name) == nil, "\(name)")
        }
    }

    @Test("Several keys on one span all apply, in any order")
    func severalKeys() {
        let expected = modified {
            $0.foregroundStyle(.red).dim().underline(pattern: .dash, color: .blue).font(.headline)
        }
        let forwards = Text("^[x](foregroundColor: red, dim: true, underlineStyle: dash, underlineColor: blue, font: headline)")
        let backwards = Text("^[x](font: headline, underlineColor: blue, underlineStyle: dash, dim: true, foregroundColor: red)")
        #expect(forwards.runs?.first?.style == expected)
        #expect(backwards.runs?.first?.style == expected)
        // A weight states the faint flag too; `dim` says it last.
        #expect(Text("^[x](dim: true, fontWeight: bold)").runs?.first?.style == modified { $0.fontWeight(.bold).dim() })
    }

    @Test("Attributes nest with emphasis, and with each other")
    func nesting() {
        let outer = Text("**^[x](foregroundColor: red)** y")
        #expect(style(of: "x", in: outer) == modified { $0.bold().foregroundStyle(.red) })
        let inner = Text("^[**x** y](foregroundColor: red)")
        #expect(style(of: "x", in: inner) == modified { $0.bold().foregroundStyle(.red) })
        #expect(style(of: " y", in: inner) == modified { $0.foregroundStyle(.red) })
        // The inner bracket's key wins; an outer key the inner did not say
        // still reaches it.
        let nested = Text("^[a ^[b](foregroundColor: blue)](foregroundColor: red, dim: true)")
        #expect(style(of: "a ", in: nested) == modified { $0.foregroundStyle(.red).dim() })
        #expect(style(of: "b", in: nested) == modified { $0.foregroundStyle(.blue).dim() })
        // Of two equal keys in one list, the first.
        #expect(Text("^[x](dim: true, dim: false)").runs?.first?.style == modified { $0.dim() })
    }

    @Test("An unknown key draws nothing, byte for byte")
    func unknownKeys() {
        #expect(Text("a ^[x](inflect: true) b").runs == nil)
        #expect(lines(Text("a ^[x](inflect: true) b")) == lines(Text("a x b")))
        #expect(lines(Text("**a** ^[b](inflect: true, morphology: {number: \"one\"})")) == lines(Text("**a** b")))
    }

    @Test("A value that does not read is passed over, and the text drawn")
    func badValues() {
        for key: LocalizedStringKey in [
            "a ^[x](dim: 1) b", "a ^[x](dim: \"true\") b", "a ^[x](foregroundColor: chartreuse) b",
            "a ^[x](underlineStyle: wiggly) b", "a ^[x](font: huge) b", "a ^[x](fontWeight: 700) b",
            "a ^[x](textScale: tertiary) b", "a ^[x](dim: true b: 2) b", "a ^[x](foregroundColor: {r: 1}) b",
        ] {
            let text = Text(key)
            #expect(text.content == "a x b", "\(key)")
            #expect(text.runs == nil, "\(key)")
        }
        // Only the key whose value does not read: the others still apply.
        #expect(Text("^[x](foregroundColor: nope, dim: true)").runs?.first?.style == modified { $0.dim() })
        // And a later valid value of the key stands in for it.
        #expect(
            Text("^[x](foregroundColor: nope, foregroundColor: red)").runs?.first?.style
                == modified { $0.foregroundStyle(.red) })
    }

    @Test("A quoted value may hold a comma and a balanced parenthesis")
    func quotedValues() {
        let text = Text("^[x](note: \"a (b), c\", foregroundColor: \"#00ff00\")")
        #expect(text.content == "x")
        #expect(text.runs?.first?.style == modified { $0.foregroundStyle(.rgb(0, 255, 0)) })
    }

    @Test("An interpolated value is never read as an attribute")
    func interpolatedValue() {
        let colour = "red"
        let text = Text("^[x](foregroundColor: \(colour)) y")
        #expect(text.content == "x y")
        #expect(text.runs == nil)
    }

    @Test("The keys draw on the terminal")
    func drawn() {
        // Joined as a `String` and made a key: `Text` parses only a key.
        let source =
            "^[dim](dim: true) ^[blink](blink: true) ^[inverse](inverse: true) "
            + "^[under](underlineStyle: true) ^[struck](strikethroughStyle: true)"
        let drawn = lines(Text(LocalizedStringKey(source)))
        #expect(attributes(of: "dim", in: drawn) == [2])
        #expect(attributes(of: "blink", in: drawn) == [5])
        #expect(attributes(of: "inverse", in: drawn) == [7])
        #expect(attributes(of: "under", in: drawn) == [4])
        #expect(attributes(of: "struck", in: drawn) == [9])
        // A secondary scale steps the run's own intensity down a tier, as
        // `.textScale(.secondary)` steps a text's: plain to faint, bold to
        // plain.
        let scaled = lines(Text("^[plain](textScale: secondary) **^[bold](textScale: secondary)** **heavy**"))
        #expect(attributes(of: "plain", in: scaled) == [2])
        #expect(attributes(of: "bold", in: scaled).isEmpty)
        #expect(attributes(of: "heavy", in: scaled) == [1])
    }

    @Test("A text with no attributes draws as it did")
    func unchangedWithoutAttributes() {
        // A plain key is a plain text, and a bold one the escape sequences
        // `**` has always drawn.
        #expect(lines(Text("no markup")) == lines(Text(verbatim: "no markup")))
        let ink = "38;2;51;255;51"
        #expect(lines(Text("no markup")).first == "\u{1B}[\(ink)mno markup\u{1B}[0m")
        #expect(
            lines(Text("**bold** text")).first == "\u{1B}[1;\(ink)mbold\u{1B}[0m\u{1B}[\(ink)m text\u{1B}[0m")
    }
}
