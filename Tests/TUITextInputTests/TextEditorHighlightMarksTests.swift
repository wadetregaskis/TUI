//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHighlightMarksTests.swift
//
//  Marks through the highlight session (B-ATTRED-59): published for a version
//  of the text, refused for an old one, carried through the editor's edits
//  and its texts written whole by the rules an app's marks follow, and drawn
//  in their token's style over the highlighting and under the app's marks.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@_spi(TextEditorHighlighting) @testable import TUITextInput
@testable import TUIView

@MainActor
// As TextEditorHighlighterTests': a main-actor test can queue behind every other in a full parallel run.
@Suite("Text editor: a highlighter's marks", .timeLimit(.minutes(45)))
struct TextEditorHighlightMarksTests {
    typealias Rig = TextEditorHighlighterTests.Rig
    typealias Token = FakeTreeStyler.Token
    typealias Mark = TextEditorHighlightMark<Token>

    @Test("Marks published for a version are kept, a stale version's refused, and an edit carries them")
    func publishedAndCarried() async throws {
        let text = "one\nkey = 12\nlast"
        let (session, frames) = TextEditorHighlightSessionTests.session(text)
        _ = session.show(lines: 0..<3)
        let first = try #require(await session.nextUpdate())
        // "12", bytes 10..<12; a range past the text clamped, and one of no length dropped.
        #expect(session.publish(marks: [Mark(10..<12, token: .comment), Mark(15..<99, token: .word)], of: 0))
        #expect(session.keptMarks() == [Mark(10..<12, token: .comment), Mark(15..<17, token: .word)])
        #expect(frames.asked == 1)
        #expect(session.publish(marks: [Mark(3..<3, token: .word)] + session.keptMarks(), of: 0))
        #expect(session.takeMarks()?.published == true)
        #expect(session.takeMarks() == nil, "taken")
        // A key typed before the mark moves it; the session is told the bytes it moved by.
        let typed = try TextEditorHighlightSessionTests.edit(session, text, to: "one\nkeyX = 12\nlast")
        #expect(session.keptMarks() == [Mark(11..<13, token: .comment), Mark(16..<18, token: .word)])
        #expect(session.takeMarks()?.published == false, "carried: only the lines edited to draw again")
        #expect(!session.publish(marks: [], of: first.text.version), "for a text the editor has moved on from")
        #expect(session.keptMarks().count == 2)
        // Typed inside a mark, it grows; typed at its end, it stays outside it.
        let grown = try TextEditorHighlightSessionTests.edit(session, typed, to: "one\nkeyX = 152\nlast")
        _ = try TextEditorHighlightSessionTests.edit(session, grown, to: "one\nkeyX = 1527\nlast")
        #expect(session.keptMarks().first == Mark(11..<14, token: .comment))
        // Written whole, as the undo of the last key: carried through the change it is.
        _ = session.textWritten(to: grown, lineStarts: EditorLayout.lineBreaks(in: grown).starts)
        #expect(session.keptMarks() == [Mark(11..<14, token: .comment), Mark(17..<19, token: .word)])
        // Nothing in common: all new, and the marks go with the tokens.
        _ = session.textWritten(to: "X", lineStarts: [0])
        #expect(session.keptMarks().isEmpty)
        #expect(session.takeMarks()?.published == true)
    }

    nonisolated static let red = Color.rgb(220, 30, 30)

    static func ink(_ color: Color) -> SGRState.Colour? { TextEditorHighlighterTests.ink(color) }

    @Test("A highlighter's marks are drawn over its tokens, carried by a key and an undo, and under the app's marks")
    func drawnThroughTheEditor() async throws {
        // tuitree's adapter sent its parse's errors round through the app's state to `.textEditorMarks`, and
        // re-implemented the editor's rules for carrying them, to keep them drawn after a key or an undo.
        let inbox = SessionInbox()
        let text = "key 12\nnext"
        let undo = UndoManager()
        undo.groupsByEvent = false
        var red = AttributeContainer()
        red.foregroundColor = Self.red
        // The app's own mark, of "ne": drawn over the highlighter's.
        let appMark = TextEditorMark(text.index(text.startIndex, offsetBy: 7)..<text.index(text.startIndex, offsetBy: 9),
            attributes: red)
        let rig = Rig(text) {
            $0.textEditorHighlighter(SteppedHighlighter(inbox: inbox), style: TextEditorHighlighterTests.style)
                .textEditorMarks([appMark], in: text).environment(\.undoManager, undo)
        }
        rig.draw()
        let session = try await TextEditorHighlighterTests.session(inbox)
        let update = try #require(await session.nextUpdate())
        FakeTreeStyler().step(update, in: session)
        let (green, grey) = (Self.ink(TextEditorHighlighterTests.green), Self.ink(TextEditorHighlighterTests.grey))
        // "ey", marked as a comment: grey over the word's green.
        #expect(session.publish(marks: [Mark(1..<3, token: .comment)], of: update.text.version))
        #expect(rig.ink(line: 0, column: 1) == grey)
        #expect(rig.ink(line: 1, column: 3) == green)
        // A key typed at the line's start moves the mark with its text (column 1 is the caret's).
        rig.handler.moveCursor(toLine: 0, column: 0)
        _ = rig.handler.handleKeyEvent(KeyEvent(key: .character("x")))
        #expect(rig.ink(line: 0, column: 2) == grey && rig.ink(line: 0, column: 3) == grey)
        #expect(rig.ink(line: 0, column: 5) != grey)
        // And an undo, written whole, carries it back.
        undo.undo()
        try #require(rig.text.value == text, "undone")
        #expect(rig.ink(line: 0, column: 1) == grey && rig.ink(line: 0, column: 2) == grey)
        // Marks published anew, of "ex": the old one's line drawn again without it, the new under the app's.
        let now = try #require(await session.nextUpdate())
        #expect(session.publish(marks: [Mark(8..<10, token: .comment)], of: now.text.version))
        #expect(rig.ink(line: 0, column: 2) == green)
        #expect(rig.ink(line: 1, column: 1) == Self.ink(Self.red), "the app's, over the highlighter's")
        #expect(rig.ink(line: 1, column: 2) == grey)
    }
}
