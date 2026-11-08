//  🖥️ TUI — A Terminal UI framework for Swift
//  TransliteratedFieldTests.swift
//
//  Under `TUI_PLAIN_TEXT=transliterate` a field's label is spelled in ASCII, as
//  every `Text` is, and its contents are not: they are what the person is
//  editing, the caret and the selection count their characters, and the
//  binding holds them as written. The folding at output still turns them into
//  ASCII, cell for cell.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUITextInput

@MainActor
@Suite("Text fields under transliteration")
struct TransliteratedFieldTests {
    private func drawn(_ view: some View) -> String {
        let context = makeRenderContext(width: 30, height: 3) { environment, _ in
            environment.transliteratesText = true
        }
        return renderToBuffer(view, context: context).lines.map(\.stripped).joined(separator: "\n")
    }

    @Test("A field's contents keep their own characters")
    func fieldContents() {
        let lines = drawn(TextField("Name", text: .constant("你好")))
        #expect(lines.contains("你好"), "\(lines)")
    }

    @Test("An editor's contents keep their own characters")
    func editorContents() {
        let lines = drawn(TextEditor(text: .constant("Привет")))
        #expect(lines.contains("Привет"), "\(lines)")
    }

    #if canImport(Darwin)
        @Test("A field's prompt, a Text, is spelled")
        func prompt() {
            let lines = drawn(TextField("Имя", text: .constant(""), prompt: Text(verbatim: "Имя")))
            #expect(lines.contains("Ima"), "\(lines)")
        }
    #endif
}
