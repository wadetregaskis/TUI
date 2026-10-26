//  🖥️ TUI — A Terminal UI framework for Swift
//  WordRuboutTests.swift
//
//  Ctrl-W is readline's `unix-word-rubout` in every text control: it kills
//  back over the blanks before the caret and the run of non-blanks before
//  them, keeps the kill for Ctrl-Y, and stays on the caret's line, as Ctrl-U
//  does (owner ruling O9, 2026-10-26: a text field's ⌃W comes before an app's
//  ⌘W).
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

private func ctrl(_ letter: Character) -> KeyEvent {
    KeyEvent(key: .character(letter), ctrl: true)
}

@MainActor
@Suite("Ctrl-W kills the word before the caret")
struct WordRuboutTests {

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

    private func makeEditor(_ initial: String, caret: TextEditorPosition) -> (TextEditorHandler, TextBox) {
        let box = TextBox(initial)
        let editor = TextEditorHandler(
            focusID: "editor", text: Binding(get: { box.text }, set: { box.text = $0 }))
        editor.clipboard = FakeClipboard().access
        editor.cursor = caret
        return (editor, box)
    }

    /// Words are what lies between blanks: punctuation is part of one.
    @Test(
        "The rubout start skips blanks, then the run of non-blanks before them",
        arguments: [
            ("cd /usr/local", 13, 0, 3),
            ("cd /usr/local  ", 15, 0, 3),
            ("one two", 4, 0, 0),
            ("one two", 0, 0, 0),
            ("   ", 3, 0, 0),
            ("ab\ncd ef", 8, 3, 6),
            ("ab\ncd", 3, 3, 3),
        ] as [(String, Int, Int, Int)])
    func ruboutStart(text: String, column: Int, lineStart: Int, expected: Int) {
        #expect(
            StandInEditingCommand.wordRuboutStart(in: Array(text), before: column, lineStart: lineStart) == expected)
    }

    @Test("In a field, Ctrl-W kills a path as one word, Ctrl-Y yanks it, and Ctrl-Z takes it back")
    func fieldKillsTheWord() {
        let (field, box) = makeField("cd /usr/local now", caret: 13)
        #expect(field.handleKeyEvent(ctrl("w")))
        #expect(box.text == "cd  now")
        #expect(field.cursorPosition == 3)
        #expect(field.killRing == "/usr/local")

        _ = field.handleKeyEvent(ctrl("y"))
        #expect(box.text == "cd /usr/local now", "Ctrl-Y did not yank Ctrl-W's kill")

        _ = field.handleKeyEvent(ctrl("z"))
        _ = field.handleKeyEvent(ctrl("z"))
        #expect(box.text == "cd /usr/local now", "the kill was not one step to take back")
        #expect(field.cursorPosition == 13)
    }

    @Test("Repeated Ctrl-W eats words back to the start, then kills nothing and keeps the key")
    func fieldRepeats() {
        let (field, box) = makeField("one two  three", caret: 14)
        _ = field.handleKeyEvent(ctrl("w"))
        #expect(box.text == "one two  ")
        _ = field.handleKeyEvent(ctrl("w"))
        #expect(box.text == "one ")
        _ = field.handleKeyEvent(ctrl("w"))
        #expect(box.text.isEmpty)
        #expect(field.handleKeyEvent(ctrl("w")), "the key passed on with nothing to kill")
        #expect(field.killRing == "one ", "an empty kill replaced the last one")
    }

    @Test("A SecureField deletes the word and keeps nothing for Ctrl-Y")
    func secureFieldKeepsNoKill() {
        let (field, box) = makeField("pass word", caret: 9, secure: true)
        #expect(field.handleKeyEvent(ctrl("w")))
        #expect(box.text == "pass ")
        #expect(field.killRing.isEmpty)
    }

    @Test("In a vertical field, Ctrl-W stays on the caret's line")
    func verticalFieldStaysOnItsLine() {
        let (field, box) = makeField("one\ntwo", caret: 7, wrapWidth: 20)
        _ = field.handleKeyEvent(ctrl("w"))
        #expect(box.text == "one\n")
        _ = field.handleKeyEvent(ctrl("w"))
        #expect(box.text == "one\n", "Ctrl-W at the start of a line took the line break")
    }

    @Test("In a TextEditor, Ctrl-W kills the word before the cursor on its line, and Ctrl-Y yanks it back")
    func editorKillsTheWord() {
        let (editor, box) = makeEditor("ab\ncd ef\ngh", caret: TextEditorPosition(line: 1, column: 5))
        #expect(editor.handleKeyEvent(ctrl("w")), "the editor passed Ctrl-W on")
        #expect(box.text == "ab\ncd \ngh")
        #expect(editor.cursor == TextEditorPosition(line: 1, column: 3))
        #expect(editor.killRing == "ef")

        _ = editor.handleKeyEvent(ctrl("w"))
        #expect(box.text == "ab\n\ngh")
        _ = editor.handleKeyEvent(ctrl("w"))
        #expect(box.text == "ab\n\ngh", "Ctrl-W at the start of a line joined it to the one above")

        _ = editor.handleKeyEvent(ctrl("z"))
        _ = editor.handleKeyEvent(ctrl("z"))
        #expect(box.text == "ab\ncd ef\ngh")
    }
}
