//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EditorLayoutTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Editor layout: the document split once per text")
struct EditorLayoutTests {
    final class Box: @unchecked Sendable {
        var value: String
        init(_ value: String) { self.value = value }
    }

    @Test("Lines, an empty text, and a trailing newline")
    func lines() {
        #expect(EditorLayout(text: "a\nbc").lines == [["a"], ["b", "c"]])
        #expect(EditorLayout(text: "").lines == [[]])
        #expect(EditorLayout(text: "a\n").lines == [["a"], []])
    }

    @Test("An untouched document is laid out once")
    func reusedWhileUnchanged() {
        let box = Box("one\ntwo")
        let handler = TextEditorHandler(
            focusID: "e", text: Binding(get: { box.value }, set: { box.value = $0 }))
        let first = handler.layout()
        #expect(handler.layout() === first)
        box.value = "three"
        #expect(handler.layout() !== first)
        #expect(handler.readLines() == [["t", "h", "r", "e", "e"]])
    }

    @Test("An edit hands its lines over with its text")
    func editKeepsItsLines() {
        let box = Box("ab\ncd")
        let handler = TextEditorHandler(
            focusID: "e", text: Binding(get: { box.value }, set: { box.value = $0 }))
        _ = handler.handleKeyEvent(KeyEvent(key: .end))
        _ = handler.handleKeyEvent(KeyEvent(key: .character("e")))
        let layout = handler.layout()
        #expect(layout.text == "ab\ncde")
        #expect(layout.lines == [["a", "b"], ["c", "d", "e"]])
        #expect(handler.layout() === layout)
    }

    @Test("A binding that keeps something else is laid out from what it keeps")
    func transformingBinding() {
        let box = Box("ab")
        let handler = TextEditorHandler(
            focusID: "e", text: Binding(get: { box.value }, set: { box.value = $0.uppercased() }))
        _ = handler.handleKeyEvent(KeyEvent(key: .end))
        _ = handler.handleKeyEvent(KeyEvent(key: .character("c")))
        #expect(handler.readLines() == [["A", "B", "C"]])
    }
}
