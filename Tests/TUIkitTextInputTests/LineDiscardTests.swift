//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LineDiscardTests.swift
//
//  Ctrl-U is readline's `unix-line-discard` in every text control: it kills
//  from the caret to the start of the caret's line. A field's Ctrl-U erased
//  all of it, wherever the caret was, and kept nothing for Ctrl-Y; a
//  `TextEditor` did not bind it at all (owner, 2026-10-23, #15).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitTextInput

/// The string a control is bound to.
private final class TextBox: @unchecked Sendable {
    var text: String
    init(_ text: String) { self.text = text }
}

private func ctrl(_ letter: Character) -> KeyEvent {
    KeyEvent(key: .character(letter), ctrl: true)
}

@MainActor
@Suite("Ctrl-U kills to the start of the line")
struct LineDiscardTests {

    /// A field over `initial` with its caret at `caret` and nothing selected.
    private func makeField(
        _ initial: String, caret: Int, secure: Bool = false, wrapWidth: Int? = nil
    ) -> (TextFieldHandler, TextBox) {
        let box = TextBox(initial)
        let handler = TextFieldHandler(
            focusID: "field", text: Binding(get: { box.text }, set: { box.text = $0 }), cursorPosition: caret)
        handler.isSecure = secure
        handler.wrapWidth = wrapWidth
        handler.clipboard = FakeClipboard().access
        return (handler, box)
    }

    /// An editor over `initial` with its caret at `caret`.
    private func makeEditor(_ initial: String, caret: TextEditorPosition) -> (TextEditorHandler, TextBox) {
        let box = TextBox(initial)
        let editor = TextEditorHandler(
            focusID: "editor", text: Binding(get: { box.text }, set: { box.text = $0 }))
        editor.clipboard = FakeClipboard().access
        editor.cursor = caret
        return (editor, box)
    }

    @Test("In a field, Ctrl-U kills the text before the caret, Ctrl-Y yanks it, and Ctrl-Z takes it back")
    func fieldKillsBeforeCaret() {
        let (field, box) = makeField("the quick brown fox", caret: 10)
        #expect(field.handleKeyEvent(ctrl("u")))
        #expect(box.text == "brown fox", "the text after the caret went too, or nothing went")
        #expect(field.cursorPosition == 0)
        #expect(field.killRing == "the quick ")

        _ = field.handleKeyEvent(KeyEvent(key: .end))
        #expect(field.handleKeyEvent(ctrl("y")))
        #expect(box.text == "brown foxthe quick ", "Ctrl-Y did not yank Ctrl-U's kill")

        _ = field.handleKeyEvent(ctrl("z"))
        _ = field.handleKeyEvent(ctrl("z"))
        #expect(box.text == "the quick brown fox", "the kill was not one step to take back")
        #expect(field.cursorPosition == 10)
    }

    @Test("At a field's start, Ctrl-U kills nothing and keeps the last kill")
    func fieldAtStartKillsNothing() {
        let (field, box) = makeField("abcd", caret: 2)
        _ = field.handleKeyEvent(ctrl("u"))
        #expect(field.killRing == "ab")
        #expect(field.handleKeyEvent(ctrl("u")), "the key passed on with nothing to kill")
        #expect(box.text == "cd")
        #expect(field.killRing == "ab", "an empty kill replaced the last one")
    }

    @Test("A field's selection goes before Ctrl-U kills from the caret")
    func fieldDropsSelection() {
        let (field, box) = makeField("abcdef", caret: 4)
        field.selectionAnchor = 6
        _ = field.handleKeyEvent(ctrl("u"))
        #expect(box.text == "ef", "Ctrl-U deleted the selection, or killed from its other end")
        #expect(field.selectionAnchor == nil)
    }

    @Test("A SecureField deletes before the caret and keeps nothing for Ctrl-Y")
    func secureFieldKeepsNoKill() {
        let (field, box) = makeField("hunter2", caret: 6, secure: true)
        #expect(field.handleKeyEvent(ctrl("u")))
        #expect(box.text == "2", "the kill happened, so the checks below are not vacuous")
        #expect(field.killRing.isEmpty, "the field kept the killed part: \(field.killRing)")
        _ = field.handleKeyEvent(ctrl("y"))
        #expect(box.text == "2", "Ctrl-Y yanked the killed part back")
    }

    @Test("In a vertical field, Ctrl-U kills to the start of the caret's line and never takes its line break")
    func verticalFieldKillsItsLine() {
        let (field, box) = makeField("one\ntwo three", caret: 8, wrapWidth: 20)
        _ = field.handleKeyEvent(ctrl("u"))
        #expect(box.text == "one\nthree")
        #expect(field.cursorPosition == 4)
        #expect(field.killRing == "two ")
        _ = field.handleKeyEvent(ctrl("u"))
        #expect(box.text == "one\nthree", "Ctrl-U at the start of a line took the line break")
    }

    @Test("In a TextEditor, Ctrl-U kills to the start of the logical line, and Ctrl-Y yanks it back")
    func editorKillsItsLine() {
        let (editor, box) = makeEditor("ab\ncd ef\ngh", caret: TextEditorPosition(line: 1, column: 3))
        #expect(editor.handleKeyEvent(ctrl("u")), "the editor passed Ctrl-U on")
        #expect(box.text == "ab\nef\ngh")
        #expect(editor.cursor == TextEditorPosition(line: 1, column: 0))
        #expect(editor.killRing == "cd ")

        #expect(editor.handleKeyEvent(ctrl("u")))
        #expect(box.text == "ab\nef\ngh", "Ctrl-U at the start of a line joined it to the one above")

        _ = editor.handleKeyEvent(ctrl("y"))
        #expect(box.text == "ab\ncd ef\ngh")
        _ = editor.handleKeyEvent(ctrl("z"))
        _ = editor.handleKeyEvent(ctrl("z"))
        #expect(box.text == "ab\ncd ef\ngh")
        #expect(editor.cursor == TextEditorPosition(line: 1, column: 3), "the kill was not one step to take back")
    }

    @Test("A TextEditor's selection goes before Ctrl-U kills from the caret")
    func editorDropsSelection() {
        let (editor, box) = makeEditor("abcdef", caret: TextEditorPosition(line: 0, column: 4))
        editor.selectionAnchor = TextEditorPosition(line: 0, column: 6)
        _ = editor.handleKeyEvent(ctrl("u"))
        #expect(box.text == "ef")
        #expect(editor.selectionAnchor == nil)
    }
}
