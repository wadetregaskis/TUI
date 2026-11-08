//  🖥️ TUI — A Terminal UI framework for Swift
//  RejectedEditCaretTests.swift
//
//  A binding may refuse an edit: a digits-only field's setter that keeps the
//  old text when it is given a letter. The text then stays put, and so must the
//  caret, as it does in an AppKit field whose delegate rejects the change. The
//  caret was moved by what the control MEANT to write, so each rejected key
//  stepped it on, and the next Delete or Backspace then acted in the wrong
//  place.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUITextInput

/// The string a control is bound to.
private final class TextBox: @unchecked Sendable {
    var text: String
    init(_ text: String) { self.text = text }
}

@MainActor
@Suite("A rejected edit leaves the caret where it was")
struct RejectedEditCaretTests {

    /// A field whose binding keeps only digits, over `initial` with the caret at `caret`.
    private func digitsOnlyField(_ initial: String, caret: Int) -> (TextFieldHandler, TextBox) {
        let box = TextBox(initial)
        let binding = Binding<String>(
            get: { box.text }, set: { if $0.allSatisfy(\.isNumber) { box.text = $0 } })
        let handler = TextFieldHandler(focusID: "field", text: binding, cursorPosition: caret)
        handler.clipboard = FakeClipboard().access
        return (handler, box)
    }

    /// A field whose binding keeps nothing at all.
    private func frozenField(_ initial: String, caret: Int) -> (TextFieldHandler, TextBox) {
        let box = TextBox(initial)
        let handler = TextFieldHandler(
            focusID: "field", text: Binding(get: { box.text }, set: { _ in }), cursorPosition: caret)
        handler.clipboard = FakeClipboard().access
        return (handler, box)
    }

    @Test("A typed character the binding refuses does not move the caret")
    func typedCharacter() {
        let (field, box) = digitsOnlyField("123", caret: 1)
        _ = field.handleKeyEvent(KeyEvent(key: .character("x")))
        _ = field.handleKeyEvent(KeyEvent(key: .character("x")))
        #expect(box.text == "123")
        #expect(field.cursorPosition == 1)
        // And an accepted one still does.
        _ = field.handleKeyEvent(KeyEvent(key: .character("9")))
        #expect(box.text == "1923")
        #expect(field.cursorPosition == 2)
    }

    @Test("A paste the binding refuses does not move the caret")
    func paste() {
        let (field, box) = digitsOnlyField("123", caret: 1)
        field.insertText("ab")
        #expect(box.text == "123")
        #expect(field.cursorPosition == 1)
    }

    @Test("A Backspace the binding refuses does not move the caret")
    func backspace() {
        let (field, box) = frozenField("123", caret: 2)
        _ = field.handleKeyEvent(KeyEvent(key: .backspace))
        #expect(box.text == "123")
        #expect(field.cursorPosition == 2)
    }

    @Test("Deleting a selection the binding refuses does not move the caret")
    func deleteSelection() {
        let (field, box) = frozenField("12345", caret: 4)
        field.deleteRangeWithoutUndo(1..<3)
        #expect(box.text == "12345")
        #expect(field.cursorPosition == 4)
    }

    @Test("A transpose the binding refuses does not move the caret")
    func transpose() {
        let (field, box) = frozenField("1234", caret: 2)
        _ = field.handleKeyEvent(KeyEvent(key: .character("t"), ctrl: true))
        #expect(box.text == "1234")
        #expect(field.cursorPosition == 2)
    }

    @Test("A character an editor's binding refuses does not move its caret")
    func editorCharacter() {
        let box = TextBox("123")
        let editor = TextEditorHandler(
            focusID: "editor",
            text: Binding(get: { box.text }, set: { if $0.allSatisfy(\.isNumber) { box.text = $0 } }))
        editor.clipboard = FakeClipboard().access
        editor.moveCursor(toLine: 0, column: 1)
        _ = editor.handleKeyEvent(KeyEvent(key: .character("x")))
        #expect(box.text == "123")
        #expect(editor.cursor == TextEditorPosition(line: 0, column: 1), "\(editor.cursor)")
    }
}
