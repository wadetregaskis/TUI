//  🖥️ TUI — A Terminal UI framework for Swift
//  EditorLayoutEditTests.swift
//
//  An edit made from the layout before it: its lines spliced into the text's
//  bytes, its wrappings kept for the lines it did not touch, and character
//  offsets found from where the lines start — each checked against the
//  layout of the text made afresh, which is what it stands in for.
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
@Suite("Editor layout: an edit spliced into the text")
struct EditorLayoutEditTests {
    /// The edit of `layout`'s lines to `newLines`, every line given as
    /// replaced, so the scans for what changed run from the ends.
    private static func replacing(_ layout: EditorLayout, with newLines: [[Character]]) -> EditorLayout.Edit? {
        layout.replacing(EditedLines(base: layout.lines, replacing: 0..<layout.lines.count, with: newLines))
    }

    /// `lines` joined, as the editor wrote every edit before.
    private static func joined(_ lines: [[Character]], _ ending: String) -> String {
        lines.map { String($0) }.joined(separator: ending)
    }

    /// Checks the edit of `text` to `newLines` against the layout of the
    /// joined text made afresh: its text, its lines' starts in bytes and in
    /// characters, and its rows at two widths.
    private func check(_ text: String, _ edit: ([[Character]]) -> [[Character]], _ comment: Comment) throws {
        let before = EditorLayout(text: text)
        let wrapped = [before.wrapped(width: 7, tabWidth: .periodic(4)), before.wrapped(width: 3, tabWidth: .periodic(4))]
        #expect(wrapped.count == 2)
        let newLines = edit(before.lines)
        let made = try #require(Self.replacing(before, with: newLines), comment)
        let fresh = EditorLayout(text: Self.joined(newLines, before.lineEnding))
        #expect(made.text == fresh.text, comment)
        #expect(Array(made.text.utf8) == Array(fresh.text.utf8), comment)
        let after = before.laidOut(made, reusingStorage: false)
        #expect(after.lines == fresh.lines, comment)
        #expect(after.lineStarts == fresh.lineStarts, comment)
        #expect(after.characterStarts == fresh.characterStarts, comment)
        // No change is the layout before, which wrapped at both widths.
        let wraps = after === before ? 2 : 0
        #expect(after.wrapsMade == wraps, comment)
        for width in [7, 3] {
            let kept = after.wrapped(width: width, tabWidth: .periodic(4))
            let anew = fresh.wrapped(width: width, tabWidth: .periodic(4))
            #expect(kept.lines == anew.lines, "\(comment) at \(width)")
            #expect(kept.rowStarts == anew.rowStarts, "\(comment) at \(width)")
        }
        #expect(after.wrapsMade == wraps, "both widths kept: \(comment)")
    }

    @Test("An edit anywhere is the text its lines joined make, byte for byte, laid out the same")
    func editsMatchTheJoinedText() throws {
        let texts = ["one two three\nfour\n\nfive six seven eight\nnine", "a\r\nbb\r\nccc d e f", "é\ne\u{301}x 🇦🇺\tz", ""]
        for text in texts {
            let ending = EditorLayout(text: text).lineEnding.debugDescription
            try check(text, { $0.enumerated().map { $0.offset == 0 ? $0.element + ["X"] : $0.element } }, "first line, \(ending)")
            try check(text, { lines in var edited = lines; edited[edited.count / 2].insert("Y", at: 0); return edited }, "a middle line")
            try check(text, { lines in var edited = lines; edited[edited.count - 1] += ["Z", " ", "Z"]; return edited }, "the last line")
            try check(text, { lines in var edited = lines; edited.insert(["n", "e", "w"], at: edited.count / 2); return edited }, "a line inserted")
            try check(text, { $0 + [["e", "n", "d"], []] }, "lines added at the end")
            try check(text, { [["s", "t", "a", "r", "t"]] + $0 }, "a line added at the start")
            if EditorLayout(text: text).lines.count > 1 {
                try check(text, { Array($0.dropLast()) }, "the last line removed")
                try check(text, { Array($0.dropFirst()) }, "the first line removed")
                try check(text, { lines in var edited = lines; edited[0] += edited.remove(at: 1); return edited }, "two lines joined")
            }
            try check(text, { $0 }, "nothing changed")
        }
    }

    /// Each random edit made from the layout the edit before it left, as the
    /// editor makes a run of keys, and checked against the text's layout
    /// made afresh: the line starts spliced (``EditorLayout/splice(_:_:with:shiftingRestBy:)``)
    /// must be the ones a full rebuild finds, in bytes and in characters,
    /// for edits within a line, across lines, at the start and at the end.
    @Test("A run of random edits keeps the line starts a full rebuild finds", arguments: ["\n", "\r\n", "\r"])
    func randomEditsMatchARebuild(ending: String) throws {
        let pieces: [Character] = ["a", "b", " ", "é", "e\u{301}", "🇦🇺", "\t", "語"]
        var random = SplitMix(state: UInt64(ending.utf8.reduce(0) { $0 &* 31 &+ Int($1) }))
        func line(_ max: Int) -> [Character] {
            (0..<Int.random(in: 0...max, using: &random)).map { _ in pieces.randomElement(using: &random)! }
        }
        func position(in lines: [[Character]]) -> TextEditorPosition {
            // The ends a third of the time each way: where an edit is likeliest wrong.
            let roll = Int.random(in: 0..<6, using: &random)
            if roll == 0 { return TextEditorPosition(line: 0, column: 0) }
            if roll == 1 { return TextEditorPosition(line: lines.count - 1, column: lines[lines.count - 1].count) }
            let index = Int.random(in: 0..<lines.count, using: &random)
            return TextEditorPosition(line: index, column: Int.random(in: 0...lines[index].count, using: &random))
        }
        for round in 0..<40 {
            // Empty lines among them, and now and then an empty text.
            let count = round.isMultiple(of: 10) ? 1 : Int.random(in: 1...12, using: &random)
            var layout = EditorLayout(text: (0..<count).map { _ in String(line(6)) }.joined(separator: ending))
            for step in 0..<25 {
                let comment: Comment = "\(ending.debugDescription) round \(round) step \(step)"
                let a = position(in: layout.lines)
                let b = position(in: layout.lines)
                // One to three lines put in: a deletion, typing, a paste of lines.
                let inserted = (0..<Int.random(in: 1...3, using: &random)).map { _ in line(3) }
                var lines = layout.lines
                TextEditorReplacement(from: min(a, b), to: max(a, b), with: inserted).apply(to: &lines)
                let made = try #require(Self.replacing(layout, with: lines), comment)
                let fresh = EditorLayout(text: lines.map { String($0) }.joined(separator: layout.lineEnding))
                #expect(Array(made.text.utf8) == Array(fresh.text.utf8), comment)
                let after = layout.laidOut(made, reusingStorage: step.isMultiple(of: 2))
                #expect(after.lines == fresh.lines, comment)
                #expect(after.lineStarts == fresh.lineStarts, comment)
                #expect(after.characterStarts == fresh.characterStarts, comment)
                layout = after
            }
        }
    }

    @Test("A text with more than one kind of line break is joined afresh")
    func mixedEndingsAreNotSpliced() {
        let layout = EditorLayout(text: "a\nb\r\nc")
        #expect(!layout.hasOneLineEnding)
        #expect(Self.replacing(layout, with: [["a"], ["b"], ["c", "!"]]) == nil)
    }

    /// The whole document wrapped again was most of a key's cost in a large
    /// text (tuitree's M4 feedback, item 3).
    @Test("A key in a wrapping editor wraps the line it changed, not the document")
    func aKeyWrapsItsLine() throws {
        let frames = EditorLayoutTests.Frames(width: 30, height: 6)
        let box = EditorLayoutTests.Box(EditorLayoutTests.longDocument)
        let page = EditorLayoutTests.Beside(text: box)
        for _ in 0..<2 { _ = frames.pass { renderToBuffer(page, context: frames.context) } }
        let handler = try #require(frames.handler)
        handler.moveCursor(toLine: 10, column: 4)
        _ = handler.handleKeyEvent(KeyEvent(character: "x"))
        _ = frames.pass { renderToBuffer(page, context: frames.context) }
        let layout = handler.layout()
        #expect(layout.text == box.value)
        #expect(layout.wrapsMade == 0, "the edit's layout kept the rows of every line but the one typed into")
        #expect(layout.wrappings.count >= 3)
    }

    @Test("Character offsets and indices found from the lines' starts are the walked ones")
    func offsetsMatchTheWalk() {
        let walked = WalkedCharacterOffsets()
        for text in ["one\ntwo\n\nthree", "a\r\nbé\r\ne\u{301}🇦🇺", "", "\n", "x"] {
            let layout = EditorLayout(text: text)
            let count = text.count
            for offset in 0...(count + 2) {
                #expect(layout.index(atOffset: offset, in: text) == walked.index(atOffset: offset, in: text), "\(text.debugDescription) \(offset)")
            }
            var index = text.startIndex
            while true {
                #expect(layout.offset(of: index, in: text) == walked.offset(of: index, in: text), "\(text.debugDescription)")
                guard index < text.endIndex else { break }
                index = text.utf8.index(after: index)
            }
        }
    }
}
