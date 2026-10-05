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

    /// The measure runs before the render hands the handler this frame's
    /// binding, so a measure that read the handler's binding sized the editor
    /// for the PREVIOUS document. A binding that is not a live reference — a
    /// `.constant`, `$notes[selected]` — holds what its frame was built with.
    @Test("The editor is measured for the text its binding holds now, not the text it last drew")
    func measuresTheCurrentText() {
        for wraps in [true, false] {
            let tui = TUIContext()
            var environment = EnvironmentValues()
            environment.focusManager = FocusManager()
            environment.applyRuntimeServices(from: tui)
            let context = RenderContext(
                availableWidth: 30, availableHeight: 12, environment: environment, tuiContext: tui)
            func pass<T>(_ body: () -> T) -> T {
                tui.stateStorage.beginRenderPass()
                tui.renderCache.beginRenderPass()
                defer { tui.stateStorage.endRenderPass() }
                return body()
            }
            func editor(_ text: String) -> some View {
                TextEditor(text: .constant(text)).textEditorWrapsLines(wraps)
            }
            // The first frame makes the handler, holding the one-line text.
            _ = pass { renderToBuffer(editor("a"), context: context) }
            let size = pass {
                measureChild(
                    editor("1\n2\n3\n4\n5\n6"), proposal: ProposedSize(width: 30, height: nil), context: context)
            }
            #expect(size.height == 6, "wrapping: \(wraps)")
        }
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
