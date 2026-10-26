//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorKeyboardSelectionTests.swift
//
//  A text editor selects from the keyboard as a text field does: Shift with
//  a motion key, and a plain arrow landing at the selection's edge.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUITextInput
@testable import TUIView

/// A mutable string backing a test `Binding`.
private final class Text2Sink: @unchecked Sendable {
    var value: String
    init(_ value: String) { self.value = value }
    var binding: Binding<String> { Binding(get: { self.value }, set: { self.value = $0 }) }
}

@MainActor
@Suite("TextEditor keyboard selection")
struct TextEditorKeyboardSelectionTests {
    private func editor(_ sink: Text2Sink, at position: (line: Int, column: Int)) -> TextEditorHandler {
        let editor = TextEditorHandler(focusID: "e", text: sink.binding)
        editor.cursorLine = position.line
        editor.cursorColumn = position.column
        // Where a click would leave it: the column a vertical move aims for.
        editor.syncDesiredColumn()
        return editor
    }

    private func press(_ editor: TextEditorHandler, _ key: Key, shift: Bool = true, alt: Bool = false, times: Int = 1) {
        for _ in 0..<times { _ = editor.handleKeyEvent(KeyEvent(key: key, alt: alt, shift: shift)) }
    }

    @Test("Shift-→ selects a character at a time, and typing replaces the selection")
    func shiftRightSelectsAndTypingReplaces() {
        let sink = Text2Sink("hello world")
        let editor = editor(sink, at: (0, 0))
        press(editor, .right, times: 5)
        #expect(editor.selectionRange?.start == TextEditorPosition(line: 0, column: 0))
        #expect(editor.selectionRange?.end == TextEditorPosition(line: 0, column: 5))
        _ = editor.handleKeyEvent(KeyEvent(key: .character("H")))
        #expect(sink.value == "H world")
    }

    @Test("Shift-Option-→ selects a word at a time")
    func shiftOptionRightSelectsWords() {
        let sink = Text2Sink("one two three")
        let editor = editor(sink, at: (0, 0))
        press(editor, .right, alt: true, times: 2)
        #expect(editor.selectionRange?.end == TextEditorPosition(line: 0, column: 7))
        _ = editor.handleKeyEvent(KeyEvent(key: .backspace))
        #expect(sink.value == " three")
    }

    @Test("Shift-↓ selects to the same column a line down, across the line break")
    func shiftDownSelectsALine() {
        let sink = Text2Sink("abc\ndef")
        let editor = editor(sink, at: (0, 1))
        press(editor, .down)
        #expect(editor.selectionRange?.start == TextEditorPosition(line: 0, column: 1))
        #expect(editor.selectionRange?.end == TextEditorPosition(line: 1, column: 1))
        _ = editor.handleKeyEvent(KeyEvent(key: .delete))
        #expect(sink.value == "aef")
    }

    @Test("Shift back over the anchor shrinks the selection to nothing, then grows it the other way")
    func shiftBackPastTheAnchor() {
        let sink = Text2Sink("abcdef")
        let editor = editor(sink, at: (0, 3))
        press(editor, .right)
        press(editor, .left)
        #expect(editor.selectionRange == nil)
        press(editor, .left, times: 2)
        #expect(editor.selectionRange?.start == TextEditorPosition(line: 0, column: 1))
        #expect(editor.selectionRange?.end == TextEditorPosition(line: 0, column: 3))
    }

    @Test("Shift-Home and Shift-End select to the document's ends")
    func shiftHomeEnd() {
        let sink = Text2Sink("ab\ncd")
        let editor = editor(sink, at: (0, 1))
        press(editor, .end)
        #expect(editor.selectionRange?.end == TextEditorPosition(line: 1, column: 2))
    }

    @Test("A plain ← or → with a selection lands at its start or its end and drops it")
    func plainArrowCollapsesToTheEdge() {
        let sink = Text2Sink("abcdef")
        let left = editor(sink, at: (0, 1))
        press(left, .right, times: 3)
        press(left, .left, shift: false)
        #expect(left.selectionRange == nil)
        #expect(left.cursor == TextEditorPosition(line: 0, column: 1))
        let right = editor(sink, at: (0, 1))
        press(right, .right, times: 3)
        press(right, .right, shift: false)
        #expect(right.selectionRange == nil)
        #expect(right.cursor == TextEditorPosition(line: 0, column: 4))
    }
}
