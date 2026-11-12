//  🖥️ TUI — A Terminal UI framework for Swift
//  TextFieldLongPromptTests.swift
//
//  A field reads its prompt's words by drawing the prompt `Text` in a context
//  of its own. That context was a fixed canvas — 4,096 cells square for a
//  vertical field, 100 cells by one line for a field on one line — so a
//  paragraph wider than it was broken where the canvas ended, and lines past
//  it were lost. The prompt is now drawn at its natural size.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUITextInput

@MainActor
@Suite("A field's long prompt")
struct TextFieldLongPromptTests {
    /// `count` words, each distinct, one space apart.
    private func words(_ count: Int) -> String {
        (0..<count).map { "w\($0)" }.joined(separator: " ")
    }

    @Test("A vertical field's prompt paragraph wider than any canvas is not broken early")
    func wideParagraphStaysWhole() {
        let paragraph = words(1_000)
        #expect(paragraph.count > 4_096)
        let read = TextFieldContentRenderer.promptParagraphs(Text(verbatim: paragraph), spelling: .asWritten)
        #expect(read == paragraph, "broken at \(read.firstIndex(of: "\n").map { read.distance(from: read.startIndex, to: $0) } ?? -1)")
    }

    @Test("A vertical field's prompt keeps every paragraph however many there are")
    func everyParagraphKept() {
        let paragraphs = (0..<4_100).map { "line \($0)" }.joined(separator: "\n")
        let read = TextFieldContentRenderer.promptParagraphs(Text(verbatim: paragraphs), spelling: .asWritten)
        let lines = read.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 4_100)
        #expect(lines.last == "line 4099")
    }

    @Test("A field on one line wider than 100 columns shows as much of its prompt as fits")
    func singleLinePromptFillsAWideField() {
        let prompt = words(40)
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        let context = RenderContext(
            availableWidth: 240, availableHeight: 1, environment: environment, tuiContext: TUIContext(),
            identity: ViewIdentity(path: "wide")
        ).isolatingRenderCache()
        let line = renderToBuffer(
            TextField("Name", text: .constant(""), prompt: Text(verbatim: prompt)).frame(width: 240),
            context: context
        ).lines[0].stripped
        #expect(line.contains(prompt), ">>\(line)<<")
    }
}
