//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorMarksPublicTests.swift
//
//  `TextEditorMark` and `.textEditorMarks(_:in:)` as an app writes them, with
//  no `@testable` and no `@_spi`: the marks are public API (lane H4′ of the
//  highlighting design's §8.6), drawn over a real editor and carried through
//  the keys typed into it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing
import TUITesting
import TUITextInput

/// An editor of `text`, whose app marks the ranges `marked` finds in
/// `stated`: the text it parsed, which the tests keep while keys are typed.
private struct MarkedEditor: View {
    @State private var text: String
    let stated: String
    let marked: [String]

    init(text: String, stated: String, marked: [String]) {
        _text = State(initialValue: text)
        self.stated = stated
        self.marked = marked
    }

    var body: some View {
        TextEditor(text: $text)
            .textEditorMarks(Self.marks(of: marked, in: stated), in: stated)
            .frame(width: 30, height: 3)
    }

    static func marks(of words: [String], in text: String) -> [TextEditorMark] {
        var red = AttributeContainer()
        red.foregroundColor = Color(red: 1, green: 0, blue: 0)
        return words.compactMap { word in text.range(of: word).map { TextEditorMark($0, attributes: red) } }
    }
}

@MainActor
@Suite("TextEditor marks, as an app writes them")
struct TextEditorMarksPublicTests {
    /// Pure red, as 24-bit colour sends it.
    static let red = "38;2;255;0;0"

    /// The escape sequences drawn just before `word` on `row`: what it is
    /// drawn in, as far as its first character goes.
    static func ink(before word: String, on row: String) -> String {
        guard let found = row.range(of: word) else { return "" }
        var escapes = ""
        var at = found.lowerBound
        // Walks back over the `ESC [ … m` sequences that end where the word
        // starts, one at a time.
        while at > row.startIndex, row[row.index(before: at)] == "m",
            let start = row[..<at].range(of: "\u{1B}[", options: .backwards)?.lowerBound
        {
            escapes = String(row[start..<at]) + escapes
            at = start
        }
        return escapes
    }

    /// `row` from `word` to its end, escapes and all. A blank's ink is not
    /// drawn, so where the ink changes after a blank the frame changes it
    /// after the blank, not before: a word, not a blank, marks the place.
    static func drawn(from word: String, on row: String) -> Substring {
        guard let found = row.range(of: word) else { return "" }
        return row[found.lowerBound...]
    }

    @Test("A mark draws its range in its attributes, and nothing else in them")
    func drawn() throws {
        let app = TestApp(width: 30, height: 3) {
            MarkedEditor(text: "abc def ghi", stated: "abc def ghi", marked: ["def"])
        }
        let row = app.screen.styledLines[0]
        #expect(Self.ink(before: "def", on: row).contains(Self.red), "\(row.debugDescription)")
        #expect(!Self.ink(before: "abc", on: row).contains(Self.red), "\(row.debugDescription)")
        #expect(!Self.drawn(from: "ghi", on: row).contains(Self.red), "\(row.debugDescription)")
    }

    @Test("Marks of the text before a key are carried through it, so the app's parse may lag")
    func carriedThroughKeys() throws {
        let app = TestApp(width: 30, height: 3) {
            MarkedEditor(text: "abc def ghi", stated: "abc def ghi", marked: ["def"])
        }
        app.press(.home)
        app.type("XY ")
        #expect(app.screen.lines[0].hasPrefix("XY abc def ghi"), "\(app.screen)")
        let row = app.screen.styledLines[0]
        #expect(Self.ink(before: "def", on: row).contains(Self.red), "moved with its text: \(row.debugDescription)")
        #expect(!Self.drawn(from: "ghi", on: row).contains(Self.red), "and no further: \(row.debugDescription)")
    }

    @Test("A mark's attributes can be any an attributed editor draws: a curly underline")
    func curlyUnderline() {
        var error = AttributeContainer()
        error.underlineStyle = Text.LineStyle(pattern: .curly, color: .red)
        let text = "let x = ]"
        let mark = TextEditorMark(text.range(of: "]")!, attributes: error)
        let app = TestApp(width: 30, height: 3) {
            TextEditor(text: .constant(text)).textEditorMarks([mark], in: text)
        }
        let plain = TestApp(width: 30, height: 3) { TextEditor(text: .constant(text)) }
        #expect(app.screen.lines == plain.screen.lines)
        #expect(app.screen.styledLines[0] != plain.screen.styledLines[0], "the mark draws something")
    }
}
