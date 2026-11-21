//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorWrittenTextTests.swift
//
//  A text written whole into a highlighted editor (the app's write, an undo,
//  a redo) told to the session as an edit of the last (B-ATTRED-58): the
//  change found from the bytes the two texts share at either end, by whole
//  lines at line starts both texts have; the tokens of the lines it left
//  kept, and those of a line edited in place carried. Checked against
//  chosen cases and against random writes in each kind of line break.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFoundation
@_spi(TextEditorHighlighting) @testable import TUITextInput

@Suite("Text editor: a text written whole, as an edit of the last", .timeLimit(.minutes(45)))
struct TextEditorWrittenTextTests {
    typealias Session = TextEditorHighlightSessionTests.Session

    /// `new` written over `old`, as the session finds it.
    static func written(_ new: String, over old: String, window: Range<Int> = 0..<10_000) -> EditorWrittenText {
        EditorWrittenText(
            new, lineStarts: EditorLayout.lineBreaks(in: new).starts, over: old,
            lineCount: EditorLayout.lineBreaks(in: old).starts.count, window: window)
    }

    /// Checks what `new` written over `old` was found to be: the same text,
    /// a text with nothing in common, or an edit whose change takes `old`'s
    /// bytes to `new`'s at line starts of both, whose lines moved are the
    /// same lines, and whose shifts are the lines' own. Returns the edit.
    @discardableResult
    static func check(
        _ new: String, over old: String, sourceLocation: SourceLocation = #_sourceLocation
    ) -> EditorHighlightEdit? {
        let label = "\(old.debugDescription) → \(new.debugDescription)"
        switch written(new, over: old) {
        case .same:
            #expect(old == new, "\(label)", sourceLocation: sourceLocation)
            return nil
        case .whole:
            #expect(old.utf8.first != new.utf8.first && old.utf8.last != new.utf8.last, "\(label)",
                sourceLocation: sourceLocation)
            return nil
        case .edit(let edit):
            let (oldText, newText) = (TextEditorText(version: 0, string: old), TextEditorText(version: 1, string: new))
            let change = edit.change
            TextEditorHighlightSessionTests.expectApplies(change, from: old, to: new)
            // Each end a line's start, or the text's end, in both texts.
            func boundary(_ text: TextEditorText, _ line: Int) -> Int {
                line < text.lineCount ? text.utf8Offset(ofLine: line) : text.utf8Count
            }
            #expect(boundary(oldText, change.oldLines.upperBound) == change.oldUTF8.upperBound, "\(label)",
                sourceLocation: sourceLocation)
            #expect(boundary(newText, change.newLines.upperBound) == change.newUTF8.upperBound, "\(label)",
                sourceLocation: sourceLocation)
            // The lines the tokens move past are the same lines, before and after.
            for line in 0..<edit.replaced.lowerBound {
                #expect(Array(oldText.line(line)) == Array(newText.line(line)), "\(label), line \(line)",
                    sourceLocation: sourceLocation)
            }
            let after = edit.replaced.lowerBound + edit.replacementCount
            for offset in 0..<(oldText.lineCount - edit.replaced.upperBound) {
                #expect(
                    Array(oldText.line(edit.replaced.upperBound + offset)) == Array(newText.line(after + offset)),
                    "\(label), line \(edit.replaced.upperBound + offset)", sourceLocation: sourceLocation)
            }
            #expect(after + oldText.lineCount - edit.replaced.upperBound == newText.lineCount, "\(label)",
                sourceLocation: sourceLocation)
            // A carried line's shift is its own bytes'.
            for (line, shift) in edit.carried {
                #expect(shift == EditorLineShift(from: oldText.line(line), to: newText.line(line)),
                    "\(label), line \(line)", sourceLocation: sourceLocation)
            }
            // And the lines of the new text, found from the old's through it, as a whole walk finds them.
            if let found = TextEditorText.lineStarts(of: new.utf8, changing: oldText, by: change) {
                #expect(found == newText.lineStarts, "\(label)", sourceLocation: sourceLocation)
            }
            return edit
        }
    }

    @Test("A write that shares a start and an end with the last text is a change of the lines between")
    func changeByLines() throws {
        // A key undone in the middle: the one line, its tokens carried.
        let typed = try #require(Self.check("one\ntwo\nthree", over: "one\ntwoX\nthree"))
        #expect(typed.change.oldLines == 1..<2 && typed.change.newLines == 1..<2)
        #expect(typed.change.oldUTF8 == 4..<9 && typed.change.newUTF8 == 4..<8)
        #expect(typed.replaced == 1..<2 && typed.replacementCount == 1 && typed.carried.keys.sorted() == [1])
        // A line put in, and one taken, in the middle: no line before or after it touched.
        let put = try #require(Self.check("a\nnew\nb", over: "a\nb"))
        #expect(put.change.oldLines == 1..<1 && put.change.newLines == 1..<2)
        let taken = try #require(Self.check("a\nb", over: "a\nnew\nb"))
        #expect(taken.change.oldLines == 1..<2 && taken.change.newLines == 1..<1)
        // A line added at the end, and taken from it: the line before is the change's (B-ATTRED-36), and its tokens stay.
        let added = try #require(Self.check("a\nb\nc", over: "a\nb"))
        #expect(added.change.oldLines == 1..<2 && added.change.newLines == 1..<3)
        #expect(added.replaced == 2..<2 && added.replacementCount == 1)
        let removed = try #require(Self.check("a\nb", over: "a\nb\nc"))
        #expect(removed.change.oldLines == 1..<3 && removed.change.newLines == 1..<2)
        #expect(removed.replaced == 2..<3 && removed.replacementCount == 0)
        // At the start.
        let first = try #require(Self.check("Xa\nb", over: "a\nb"))
        #expect(first.change.oldLines == 0..<1 && first.change.newLines == 0..<1)
        // A lone CR before the write, which an LF after it would join: the line before is in the change.
        let joined = try #require(Self.check("a\r\nb", over: "a\rxb"))
        #expect(joined.change.oldLines.lowerBound == 0)
        Self.check("a\rb", over: "a\r\nb")
        Self.check("a\r\n", over: "a\r")
    }

    @Test("The same text is no change; a text with nothing in common at either end is all new")
    func sameAndWhole() {
        guard case .same = Self.written("a\nb", over: "a\nb") else { Issue.record("the same text"); return }
        guard case .whole = Self.written("xyz", over: "a\nb") else { Issue.record("nothing shared"); return }
        guard case .edit = Self.written("a", over: "ab") else { Issue.record("a byte shared"); return }
    }

    @Test("Random writes over random texts, in every kind of line break, each as its change")
    func randomWrites() {
        var random = SplitMix(state: 0x5EA_7E57)
        func next(_ bound: Int) -> Int { bound > 0 ? Int.random(in: 0..<bound, using: &random) : 0 }
        let pieces = ["a", "bc", "é", "\n", "\r", "\r\n", " ", "\n\n"]
        func text(_ count: Int) -> [String] { (0..<count).map { _ in pieces[next(pieces.count)] } }
        for _ in 0..<2_000 {
            var old = text(next(16))
            let new: [String]
            if next(8) == 0 {
                new = text(next(16))
            } else {
                var edited = old
                let at = next(edited.count + 1)
                let upTo = min(edited.count, at + next(4))
                edited.replaceSubrange(at..<upTo, with: text(next(4)))
                new = edited
            }
            if next(4) == 0 { old.append("\n") }
            Self.check(new.joined(), over: old.joined())
        }
    }

    // MARK: - Through a session

    @Test("Written whole, a text keeps the tokens of the lines it left, carries the line it edited, and comes as a change")
    func sessionKeepsTokens() async throws {
        let text = "zero\none\ntwo\nthree"
        let (session, _) = TextEditorHighlightSessionTests.session(text)
        _ = session.show(lines: 0..<4)
        let first = try #require(await session.nextUpdate())
        let word = TextEditorHighlightSessionTests.tokens([(0, .word), (3, .gap)])
        #expect(session.publish(Array(repeating: word, count: 4), forLines: 0..<4, of: first.text.version) == .kept(0..<4))
        // An undo's write: line 1 edited in place, its tokens carried.
        let typed = "zero\nONE\ntwo\nthree"
        _ = session.textWritten(to: typed, lineStarts: EditorLayout.lineBreaks(in: typed).starts)
        #expect(session.keptLine(0)?.isProvisional == false)
        #expect(session.keptLine(1)?.isProvisional == true, "edited: carried")
        #expect(session.keptLine(3)?.isProvisional == false)
        // And a redo's: line 2 taken, the line after moved up with its tokens.
        let undone = "zero\nONE\nthree"
        _ = session.textWritten(to: undone, lineStarts: EditorLayout.lineBreaks(in: undone).starts)
        #expect(session.keptLine(1)?.isProvisional == true, "left by this one: still carried")
        #expect(session.keptLine(2)?.isProvisional == false, "\"three\", moved up")
        let update = try #require(await session.nextUpdate())
        let change = try #require(update.change)
        #expect(change.oldLines == 1..<3 && change.newLines == 1..<2)
        #expect(update.text.string == undone)
        #expect(update.linesToStyle == RangeSet(1..<2))
        // The same text again: nothing to tell, no new version.
        _ = session.textWritten(to: undone, lineStarts: EditorLayout.lineBreaks(in: undone).starts)
        #expect(session.publish(word, forLine: 1, of: update.text.version) == .kept(1..<2))
        // Nothing in common: all new, as before.
        _ = session.textWritten(to: "X", lineStarts: [0])
        #expect(session.keptLine(0) == nil)
        #expect(try #require(await session.nextUpdate()).change == nil)
    }
}
