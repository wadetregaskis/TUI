//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextEditorStyleTests.swift
//
//  `TextEditorStyle`: `.automatic` draws the editor on its field surface,
//  `.plain` without one, and a custom style's body in the editor's place.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

private struct NoteStyle: TextEditorStyle {
    func makeBody(configuration: Configuration) -> some View {
        Text("custom")
    }
}

@MainActor
@Suite("TextEditorStyle")
struct TextEditorStyleTests {
    /// Whether the first row's last cell — clear of the text and of the caret
    /// the focused editor draws on its first character — names a background.
    private func paintsField<V: View>(_ view: V) -> Bool {
        let line = renderToBuffer(view, context: makeRenderContext(width: 20, height: 3)).lines.first ?? ""
        var state = SGRState()
        var last = false
        for segment in line.ansiSegments() {
            switch segment {
            case .ansi(let sequence, true): state.apply(sequence)
            case .ansi: continue
            case .visible: last = state.namesBackground
            }
        }
        return last
    }

    @Test("The automatic style paints the field surface; the plain style does not")
    func surface() {
        let editor = TextEditor(text: .constant("hello"))
        #expect(paintsField(editor))
        #expect(paintsField(editor.textEditorStyle(.automatic)))
        #expect(!paintsField(editor.textEditorStyle(.plain)))
    }

    @Test("A custom style draws its body in the editor's place")
    func custom() {
        let drawn = renderToBuffer(
            TextEditor(text: .constant("hello")).textEditorStyle(NoteStyle()),
            context: makeRenderContext(width: 20, height: 3))
        #expect(drawn.lines.first?.stripped.hasPrefix("custom") == true)
    }
}
