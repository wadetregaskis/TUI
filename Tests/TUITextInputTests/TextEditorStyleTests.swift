//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorStyleTests.swift
//
//  `TextEditorStyle`: `.automatic` draws the editor on its field surface,
//  `.plain` without one, and a custom style's body in the editor's place.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUITextInput

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

    /// The owner's ruling, 2026-10-16: the blank cell a border keeps either side
    /// of its content was a strip of the page between the line and the editor's
    /// field. SwiftUI's border sits on the view's edge with no inset at all.
    @Test("A border hugs an editor's field, through a frame; around text it keeps its blank cell")
    func borderHugsTheField() {
        let context = makeRenderContext(width: 20, height: 6)
        let editor = renderToBuffer(
            TextEditor(text: .constant("ab")).frame(height: 2).border(), context: context
        ).lines.map(\.stripped)
        #expect(editor.contains { $0.hasPrefix("│ab") }, "the editor's text starts at the line: \(editor)")
        let text = renderToBuffer(Text("ab").border(), context: context).lines.map(\.stripped)
        #expect(text.contains { $0.hasPrefix("│ ab") }, "text keeps its blank cell: \(text)")
    }

    @Test("A custom style draws its body in the editor's place")
    func custom() {
        let drawn = renderToBuffer(
            TextEditor(text: .constant("hello")).textEditorStyle(NoteStyle()),
            context: makeRenderContext(width: 20, height: 3))
        #expect(drawn.lines.first?.stripped.hasPrefix("custom") == true)
    }
}
