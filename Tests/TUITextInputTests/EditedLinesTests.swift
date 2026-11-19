//  🖥️ TUI — A Terminal UI framework for Swift
//  EditedLinesTests.swift
//
//  An edit made over the layout's lines without copying them, and laid out in
//  the layout's own storage once the binding takes it: each checked against
//  the straightforward path it stands in for — the replacements made in a
//  copy of the lines, and the joined text laid out afresh.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUITextInput

@MainActor
@Suite("Editor layout: an edit over the lines, laid out in place")
struct EditedLinesTests {
    private final class Box: @unchecked Sendable {
        var text: String
        init(_ text: String) { self.text = text }
    }

    private static let pieces: [Character] = ["a", "b", " ", "é", "e\u{301}", "🇦🇺", "\t", "語"]

    private static func line(_ max: Int, _ random: inout SplitMix) -> [Character] {
        (0..<Int.random(in: 0...max, using: &random)).map { _ in pieces.randomElement(using: &random)! }
    }

    private static func position(in lines: [[Character]], _ random: inout SplitMix) -> TextEditorPosition {
        // The ends a third of the time each way: where an edit is likeliest wrong.
        let roll = Int.random(in: 0..<6, using: &random)
        if roll == 0 { return TextEditorPosition(line: 0, column: 0) }
        if roll == 1 { return TextEditorPosition(line: lines.count - 1, column: lines[lines.count - 1].count) }
        let index = Int.random(in: 0..<lines.count, using: &random)
        return TextEditorPosition(line: index, column: Int.random(in: 0...lines[index].count, using: &random))
    }

    /// One to four replacements, each on the lines the one before left — a
    /// block's rows last first among them — as the editor makes them.
    private static func replacements(
        in lines: [[Character]], _ random: inout SplitMix
    ) -> (made: [TextEditorReplacement], lines: [[Character]]) {
        var lines = lines
        var made: [TextEditorReplacement] = []
        for _ in 0..<Int.random(in: 1...4, using: &random) {
            let a = position(in: lines, &random)
            let b = position(in: lines, &random)
            let inserted = (0..<Int.random(in: 1...3, using: &random)).map { _ in line(3, &random) }
            let replacement = TextEditorReplacement(from: min(a, b), to: max(a, b), with: inserted)
            replacement.apply(to: &lines)
            made.append(replacement)
        }
        return (made, lines)
    }

    @Test("Replacements made over the lines leave the lines made in a copy of them")
    func editedLinesMatchACopy() {
        var random = SplitMix(state: 0xED17)
        for round in 0..<300 {
            let count = round.isMultiple(of: 10) ? 1 : Int.random(in: 1...12, using: &random)
            let base = (0..<count).map { _ in Self.line(6, &random) }
            let (made, expected) = Self.replacements(in: base, &random)
            var edited = EditedLines(base)
            for replacement in made { edited.apply(replacement) }
            #expect(edited.count == expected.count, "round \(round)")
            #expect((0..<edited.count).map { edited[$0] } == expected, "round \(round)")
            #expect(edited.array == expected, "round \(round)")
            // Every line outside the span replaced is the base's own.
            #expect(base[..<edited.replaced.lowerBound] == expected[..<edited.replaced.lowerBound], "round \(round)")
        }
    }

    /// Each random edit made from the layout the edit before it left, as the
    /// editor makes a run of keys, laid out both ways — in the layout's own
    /// storage and in a copy — and checked against the joined text's layout
    /// made afresh. The layout laid out from a copy must keep its own.
    @Test("A run of random edits laid out in place is the text's layout made afresh", arguments: ["\n", "\r\n", "\r"])
    func randomEditsMatchARebuild(ending: String) throws {
        var random = SplitMix(state: UInt64(ending.utf8.reduce(0) { $0 &* 31 &+ Int($1) }) &+ 7)
        for round in 0..<40 {
            let count = round.isMultiple(of: 10) ? 1 : Int.random(in: 1...12, using: &random)
            var layout = EditorLayout(text: (0..<count).map { _ in String(Self.line(6, &random)) }.joined(separator: ending))
            _ = layout.wrapped(width: 5, tabWidth: .periodic(4))
            for step in 0..<25 {
                let comment: Comment = "\(ending.debugDescription) round \(round) step \(step)"
                let (made, lines) = Self.replacements(in: layout.lines, &random)
                var edited = EditedLines(layout.lines)
                for replacement in made { edited.apply(replacement) }
                let edit = try #require(layout.replacing(edited), comment)
                let fresh = EditorLayout(text: lines.map { String($0) }.joined(separator: layout.lineEnding))
                #expect(Array(edit.text.utf8) == Array(fresh.text.utf8), comment)
                let inPlace = step.isMultiple(of: 2)
                let (text, oldLines, oldStarts) = (layout.text, layout.lines, layout.lineStarts)
                let after = layout.laidOut(edit, reusingStorage: inPlace)
                #expect(after.text == fresh.text, comment)
                #expect(after.lines == fresh.lines, comment)
                #expect(after.lineStarts == fresh.lineStarts, comment)
                #expect(after.characterStarts == fresh.characterStarts, comment)
                let kept = after.wrapped(width: 5, tabWidth: .periodic(4))
                let anew = fresh.wrapped(width: 5, tabWidth: .periodic(4))
                #expect(kept.lines == anew.lines, comment)
                #expect(kept.rowStarts == anew.rowStarts, comment)
                if !inPlace, after !== layout {
                    // A layout something else holds keeps its text and lines.
                    #expect(layout.text == text, comment)
                    #expect(layout.lines == oldLines, comment)
                    #expect(layout.lineStarts == oldStarts, comment)
                }
                layout = after
            }
        }
    }

    @Test("A layout that gave its storage up is the empty text's, whole")
    func spentLayoutIsEmpty() throws {
        let layout = EditorLayout(text: "one\ntwo\nthree")
        var edited = EditedLines(layout.lines)
        edited.apply(TextEditorReplacement(line: 1, columns: 0..<0, with: ["X"]))
        let edit = try #require(layout.replacing(edited))
        let after = layout.laidOut(edit, reusingStorage: true)
        #expect(after.text == "one\nXtwo\nthree")
        let empty: [[Character]] = [[]]
        #expect(layout.text.isEmpty)
        #expect(layout.lines == empty)
        #expect(layout.lineStarts == [0])
        #expect(layout.characterStarts == [0])
        #expect(layout.wrappings.isEmpty)
    }

    /// The rule the in-place edit must keep (7614f8c38): the layout before is
    /// left whole until the binding takes the edit, so a refused one leaves
    /// the handler that layout — its text, its lines and its wrappings.
    @Test("An edit the binding refuses leaves the handler its layout, whole")
    func refusedEditKeepsTheLayout() {
        let box = Box((0..<200).map { "line \($0)" }.joined(separator: "\n"))
        // Takes any text without a "#".
        let refusing = Binding(get: { box.text }, set: { if !$0.contains("#") { box.text = $0 } })
        let handler = TextEditorHandler(focusID: "editor", text: refusing)
        handler.clipboard = FakeClipboard().access
        let before = handler.layout()
        _ = before.wrapped(width: 8, tabWidth: .periodic(4))
        let (text, lines, starts, wrappings) = (before.text, before.lines, before.lineStarts, before.wrappings.count)
        handler.moveCursor(toLine: 100, column: 2)
        _ = handler.handleKeyEvent(KeyEvent(key: .character("#")))
        #expect(box.text == text, "the binding refused the #")
        #expect(handler.layout() === before)
        #expect(before.text == text)
        #expect(before.lines == lines)
        #expect(before.lineStarts == starts)
        #expect(before.wrappings.count == wrappings)
        // And one it takes is laid out as the text it holds.
        _ = handler.handleKeyEvent(KeyEvent(key: .character("x")))
        let after = handler.layout()
        let fresh = EditorLayout(text: box.text)
        #expect(after.text == box.text)
        #expect(after.lines == fresh.lines)
        #expect(after.lineStarts == fresh.lineStarts)
        #expect(after.characterStarts == fresh.characterStarts)
    }
}
