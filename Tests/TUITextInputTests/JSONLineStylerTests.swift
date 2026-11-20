//  🖥️ TUI — A Terminal UI framework for Swift
//  JSONLineStylerTests.swift
//
//  The JSON line styler (`TUIJSONStyler`, lane H5′ of the highlighting
//  design): each kind of token, escapes, a malformed line styled as far as
//  it can be, and the styler through an editor: its colours drawn, and a
//  line past the seam's limit drawn unstyled (B-ATTRED-15).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUICore
@testable import TUIFoundation
import TUIJSONStyler
@testable import TUITestSupport
@_spi(TextEditorHighlighting) @testable import TUITextInput

@MainActor
// A styler that never publishes would otherwise hang the run.
// Very generous, as NamedTaskTests' is: in a full parallel run a @MainActor test queues behind every other
// main-actor test its process has started, and a single hop has been measured at 17 s (AsyncSettling.swift).
// Three minutes failed four tests of the highlighter suite beside this one in the batch50 gate (2026-11-20) though each passes alone.
@Suite("Text editor: the JSON line styler", .timeLimit(.minutes(45)))
struct JSONLineStylerTests {
    typealias Rig = TextEditorHighlighterTests.Rig

    /// `line`'s tokens, each with the text it covers.
    static func tokens(_ line: String) -> [(JSONToken, String)] {
        let bytes = Array(line.utf8)
        let tokens = JSONLineStyler.tokens(of: line[...].utf8)
        return tokens.tokens.indices.map { index in
            let end = index + 1 < tokens.offsets.count ? tokens.offsets[index + 1] : bytes.count
            return (tokens.tokens[index], String(bytes: bytes[tokens.offsets[index]..<end], encoding: .utf8) ?? "")
        }
    }

    /// Whether `line` is styled as `expected` says, token by token.
    static func expect(_ line: String, _ expected: [(JSONToken, String)], sourceLocation: SourceLocation = #_sourceLocation) {
        let got = tokens(line)
        #expect(got.map(\.0) == expected.map(\.0), "kinds of \(line)", sourceLocation: sourceLocation)
        #expect(got.map(\.1) == expected.map(\.1), "texts of \(line)", sourceLocation: sourceLocation)
    }

    // MARK: - Tokens

    @Test("Keys, strings, numbers, literals, punctuation and blanks")
    func eachKind() {
        Self.expect(
            #"{"id": -12.5e3, "ok": true, "no": false, "x": null, "s": "a b"},"#,
            [
                (.punctuation, "{"), (.key, #""id""#), (.punctuation, ":"), (.space, " "), (.number, "-12.5e3"),
                (.punctuation, ","), (.space, " "), (.key, #""ok""#), (.punctuation, ":"), (.space, " "),
                (.literal, "true"), (.punctuation, ","), (.space, " "), (.key, #""no""#), (.punctuation, ":"),
                (.space, " "), (.literal, "false"), (.punctuation, ","), (.space, " "), (.key, #""x""#),
                (.punctuation, ":"), (.space, " "), (.literal, "null"), (.punctuation, ","), (.space, " "),
                (.key, #""s""#), (.punctuation, ":"), (.space, " "), (.string, #""a b""#), (.punctuation, "},"),
            ])
        // A key is a key past blanks before its colon; a string in an array
        // is a value.
        Self.expect("  \"k\"\t : [\"v\", 1]", [
            (.space, "  "), (.key, #""k""#), (.space, "\t "), (.punctuation, ":"), (.space, " "), (.punctuation, "["),
            (.string, #""v""#), (.punctuation, ","), (.space, " "), (.number, "1"), (.punctuation, "]"),
        ])
        #expect(Self.tokens("").isEmpty, "an empty line: no tokens")
        // The fixture's own style: a colour for each kind but the gaps.
        let styled: [JSONToken] = [.key, .string, .escape, .number, .literal, .invalid]
        for (index, token) in styled.enumerated() {
            #expect(JSONLineStyler.style(token) != AttributeContainer(), "\(token): styled")
            for other in styled[(index + 1)...] { #expect(JSONLineStyler.style(token) != JSONLineStyler.style(other)) }
        }
        #expect(JSONLineStyler.style(.punctuation) == AttributeContainer())
        #expect(JSONLineStyler.style(.space) == AttributeContainer())
    }

    @Test("Escapes inside strings and keys, a quote escaped never closing one, and escapes JSON lacks")
    func escapes() {
        Self.expect(#"["x\"y\u00e9\\", "é\n"]"#, [
            (.punctuation, "["), (.string, #""x"#), (.escape, #"\""#), (.string, "y"), (.escape, #"\u00e9\\"#),
            (.string, #"""#), (.punctuation, ","), (.space, " "), (.string, #""é"#), (.escape, #"\n"#),
            (.string, #"""#), (.punctuation, "]"),
        ])
        Self.expect(#"{"a\"b": 1}"#, [
            (.punctuation, "{"), (.key, #""a"#), (.escape, #"\""#), (.key, #"b""#), (.punctuation, ":"),
            (.space, " "), (.number, "1"), (.punctuation, "}"),
        ])
        // `\q` is no escape, nor is a `\u` short of four hex digits.
        Self.expect(#""\q\u12""#, [(.string, #"""#), (.invalid, #"\q\u12"#), (.string, #"""#)])
    }

    @Test("A malformed line doesn't crash, and styles what it can")
    func malformed() {
        Self.expect(#"{oops: tru, "k": 12abc @é "open"#, [
            (.punctuation, "{"), (.invalid, "oops"), (.punctuation, ":"), (.space, " "), (.invalid, "tru"),
            (.punctuation, ","), (.space, " "), (.key, #""k""#), (.punctuation, ":"), (.space, " "), (.number, "12"),
            (.invalid, "abc"), (.space, " "), (.invalid, "@é"), (.space, " "), (.string, #""open"#),
        ])
        // An unterminated string is a string to the line's end, never a key,
        // and a backslash at the end is no escape.
        Self.expect(#""k": "v\"#, [
            (.key, #""k""#), (.punctuation, ":"), (.space, " "), (.string, #""v"#), (.invalid, #"\"#),
        ])
        Self.expect(#"""#, [(.string, #"""#)])
        // Every byte, singly and in pairs: offsets in order and in the line.
        for first in UInt8(0)...UInt8(127) {
            for second: UInt8 in [0x22, 0x5C, 0x3A, 0x75, 0xC3] {
                let bytes = [first, second, 0x22, first]
                let tokens = JSONLineStyler.tokens(of: bytes)
                #expect(tokens.offsets == tokens.offsets.sorted() && tokens.offsets.allSatisfy { $0 < bytes.count })
            }
        }
    }

    // MARK: - Through an editor

    @Test("An editor with the styler draws its tokens' colours")
    func drawnThroughAnEditor() async {
        let rig = Rig(#"{"k": "v", "n": 1}"# + "\n" + #"[true, "a\n"]"#) {
            $0.textEditorHighlighter(JSONHighlighter(), style: Self.style)
        }
        // Column 0 is the caret's.
        await settle(until: { rig.ink(line: 0, column: 1) == Self.ink(.key) })
        #expect(rig.ink(line: 0, column: 1) == Self.ink(.key), "a key")
        #expect(rig.ink(line: 0, column: 4) != Self.ink(.key), "punctuation: the editor's ink")
        #expect(rig.ink(line: 0, column: 6) == Self.ink(.string), "a string")
        #expect(rig.ink(line: 0, column: 16) == Self.ink(.number), "a number")
        #expect(rig.ink(line: 1, column: 1) == Self.ink(.literal), "a literal")
        #expect(rig.ink(line: 1, column: 9) == Self.ink(.escape), "an escape")
        rig.draw(false)
    }

    @Test("A line longer than the seam's limit is drawn unstyled, the lines about it styled")
    func longLineUnstyled() async throws {
        let long = "\"" + String(repeating: "x", count: 60) + "\""
        let rig = Rig(#"{"k": 1}"# + "\n" + long + "\n" + "true", height: 8) {
            $0.textEditorHighlighter(JSONHighlighter(), maximumLineLength: 40, style: Self.style)
        }
        await settle(until: { rig.ink(line: 0, column: 1) == Self.ink(.key) })
        let rows = rig.draw()
        let literal = try #require(rows.firstIndex { $0.first?.character == "t" }, "the last line drawn")
        // The second line's rows, wrapped, between the first line's and the last's.
        for row in 1..<literal {
            #expect(rows[row][1].state.foregroundColour != Self.ink(.string), "row \(row): unstyled")
        }
        #expect(rows[literal][1].state.foregroundColour == Self.ink(.literal), "the line after it: styled")
        rig.draw(false)
    }

    /// A colour of each token's own, stated in RGB so that it draws as stated
    /// (named colours resolve through the palette), or none.
    nonisolated static func colour(_ token: JSONToken) -> Color? {
        switch token {
        case .key: .rgb(0, 200, 200)
        case .string: .rgb(0, 200, 0)
        case .escape: .rgb(0, 0, 200)
        case .number: .rgb(200, 200, 0)
        case .literal: .rgb(200, 0, 200)
        case .invalid: .rgb(200, 0, 0)
        case .punctuation, .space: nil
        }
    }

    /// ``colour(_:)`` as a style.
    static func style(_ token: JSONToken) -> AttributeContainer {
        var container = AttributeContainer()
        if let colour = colour(token) { container.foregroundColor = colour }
        return container
    }

    /// The ink `token` is drawn in.
    static func ink(_ token: JSONToken) -> SGRState.Colour? {
        colour(token).flatMap { TextEditorHighlighterTests.ink($0) }
    }
}
