//  🖥️ TUI — A Terminal UI framework for Swift
//  AlertLongMessageTests.swift
//
//  An alert reads its message's words by drawing the message views on a canvas
//  of their own, and the panel wraps them again at its own width and scrolls
//  them. That canvas was a fixed 4,096 cells square: a paragraph wider than it
//  was broken where it ended, and lines past its 4,096th were lost, though the
//  panel would have scrolled to them. The message is now drawn at its natural
//  size.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUIPresentation
@testable import TUITestSupport

@MainActor
@Suite("An alert's long message")
struct AlertLongMessageTests {
    /// The words the alert reads from `message`.
    private func read(_ message: String) -> String {
        AlertPresentationModifier(
            content: EmptyView(), isPresented: .constant(true), title: "Title",
            message: Text(verbatim: message), actions: EmptyView()
        ).renderedMessage(context: makeRenderContext(width: 60, height: 12))
    }

    @Test("Every line of a message is kept, however many there are, for the panel to scroll to")
    func everyLineKept() {
        let lines = read((0..<4_100).map { "line \($0)" }.joined(separator: "\n"))
            .split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 4_100)
        #expect(lines.last == "line 4099")
    }

    @Test("A paragraph wider than any canvas is not broken before the panel wraps it")
    func wideParagraphStaysWhole() {
        let paragraph = (0..<1_000).map { "w\($0)" }.joined(separator: " ")
        #expect(paragraph.count > 4_096)
        #expect(read(paragraph) == paragraph)
    }
}
