//  🖥️ TUI — A Terminal UI framework for Swift
//  InlineMarkdownAttributeTests.swift
//
//  The `key: value` list of a `^[text](attributes)`, as the parse reads it:
//  Foundation's JSON5 grammar, and where the attributes land — measured on
//  macOS 15.8.1 (`Tools/SwiftUIProbes/Markdown attribute syntax/decode.swift`).
//  What the keys draw is `TextMarkdownAttributeTests`'.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUIStrings

extension InlineMarkdownTests {
    typealias Attribute = InlineMarkdown.Attribute

    /// The attributes of the span whose text is `word`, as `key=value`
    /// strings, a quoted value in quotes.
    private func attributes(of word: String, in source: String) -> [String]? {
        InlineMarkdown.parse(source).first { text($0.atoms) == word }.map { span in
            span.attributes.map { attribute in
                switch attribute.value {
                case .string(let value): "\(attribute.key)=\"\(value)\""
                case .word(let value): "\(attribute.key)=\(value)"
                }
            }
        }
    }

    @Test("An attribute list reads as Foundation's JSON5 members")
    func attributeGrammar() {
        let cases: [(source: String, attributes: [String])] = [
            ("^[x](dim: true)", ["dim=true"]),
            ("^[x](a: 1, b: 'q', c: \"r\")", ["a=1", "b=\"q\"", "c=\"r\""]),
            ("^[x](\"dim\": true)", ["dim=true"]),
            ("^[x](dim: true,)", ["dim=true"]),
            ("^[x]( dim :true , blink:\ttrue )", ["dim=true", "blink=true"]),
            ("^[x](/* c */ dim: true // to the end\n)", ["dim=true"]),
            ("^[x](a: {b: [1, \"}\"]}, dim: true)", ["dim=true"]),
            ("^[x](a: [1, 2], dim: true)", ["dim=true"]),
            ("^[x](foregroundColor: #ff0000)", ["foregroundColor=#ff0000"]),
            ("^[x](a: \"\\u0041\\n\\\\\")", ["a=\"A\n\\\""]),
            ("^[x](a: 'it\\'s')", ["a=\"it's\""]),
            ("^[x](dim: true, dim: false)", ["dim=true", "dim=false"]),
            ("^[x]()", []),
        ]
        for (source, expected) in cases {
            #expect(attributes(of: "x", in: source) == expected, "\(source.debugDescription)")
        }
    }

    @Test("A quoted value may hold a comma and a balanced parenthesis")
    func quotedPunctuation() {
        #expect(
            attributes(of: "x", in: "^[x](note: \"a (b), c\", dim: true)") == ["note=\"a (b), c\"", "dim=true"])
        // A lone `)` in quotes still ends the parentheses, as Foundation's
        // scan ends them (`attrs.out`): the list is `note: "`, which does not
        // read, and the rest is text.
        let spans = InlineMarkdown.parse("^[x](note: \")\", dim: true)")
        #expect(spans.map { text($0.atoms) }.joined() == "x\", dim: true)")
        #expect(spans.allSatisfy { $0.attributes.isEmpty })
    }

    @Test("A list that does not read gives no attributes, and the text is drawn")
    func unreadableLists() {
        for source in [
            "^[x](garbage)", "^[x](a:)", "^[x](a 1)", "^[x](dim: true b: 2)", "^[x](, dim: true)",
            "^[x](a: \"unterminated)", "^[x](a: \"\\q\")", "^[x](a: \\))", "^[x](a: (1))", "^[x](a: {b: 1)",
            "^[x](a: \"\\u00\")",
        ] {
            let spans = InlineMarkdown.parse(source)
            #expect(spans.map { text($0.atoms) } == ["x"], "\(source.debugDescription)")
            #expect(spans.allSatisfy { $0.attributes.isEmpty }, "\(source.debugDescription)")
        }
    }

    @Test("An interpolated value inside the attributes gives none")
    func argumentInAttributes() {
        let spans = InlineMarkdown.parse(atoms("^[x](foregroundColor: ", 0, ")"))
        #expect(spans.map { text($0.atoms) } == ["x"])
        #expect(spans.allSatisfy { $0.attributes.isEmpty })
    }

    @Test("Attributes nest inner first, and combine with emphasis")
    func attributeNesting() {
        // Foundation: an inner attribute beats an outer one of the same key,
        // so the inner list comes first and the first of a key holds.
        let nested = "^[a ^[b](dim: false)](dim: true)"
        #expect(attributes(of: "a ", in: nested) == ["dim=true"])
        #expect(attributes(of: "b", in: nested) == ["dim=false", "dim=true"])
        #expect(InlineMarkdown.parse("**^[a](dim: true)**").map(\.traits) == [.strong])
        #expect(attributes(of: "a", in: "**^[a](dim: true)**") == ["dim=true"])
        let inside = InlineMarkdown.parse("^[**a** b](dim: true)")
        #expect(inside.map(\.traits) == [.strong, []])
        #expect(inside.allSatisfy { $0.attributes.map(\.key) == ["dim"] })
    }

    @Test("A link drops the attributes inside it, and keeps those around it")
    func attributesAndLinks() {
        let inside = InlineMarkdown.parse("[^[a](dim: true)](https://x.y)")
        #expect(inside.count == 1)
        #expect(inside.first?.attributes.isEmpty == true)
        #expect(inside.first?.link != nil)
        let around = InlineMarkdown.parse("^[[a](https://x.y)](dim: true)")
        #expect(around.count == 1)
        #expect(around.first?.attributes.map(\.key) == ["dim"])
        #expect(around.first?.link != nil)
    }

    @Test("Spans of different attributes stay apart, and an email address keeps them")
    func attributesSplitSpans() {
        #expect(InlineMarkdown.parse("a ^[b](dim: true) c").map { text($0.atoms) } == ["a ", "b", " c"])
        let email = InlineMarkdown.parse("^[mail a@b.cd now](dim: true)")
        #expect(email.map { text($0.atoms) } == ["mail ", "a@b.cd", " now"])
        #expect(email.allSatisfy { $0.attributes.map(\.key) == ["dim"] })
        #expect(email[1].link != nil)
    }
}
