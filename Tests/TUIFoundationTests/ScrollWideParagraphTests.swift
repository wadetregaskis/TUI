//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollWideParagraphTests.swift
//
//  A horizontal `ScrollView` sizes its canvas from its content's ideal width,
//  asked up the natural-extent ladder. A `Text` answered it wrapped at the
//  ladder's budget, and a paragraph wider than the budget (4,096 cells) broke
//  at the last space before it and reported a width short of the budget,
//  which the ladder took for the text's own: the paragraph was drawn as two
//  lines, its tail under its head, where it should have scrolled on.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("A horizontal scroll view's wide paragraph")
struct ScrollWideParagraphTests {
    @Test("A paragraph wider than any budget stays one line, to scroll along")
    func wideParagraphIsOneLine() {
        let paragraph = (0..<1_000).map { "w\($0)" }.joined(separator: " ")
        #expect(paragraph.count > 4_096)
        let buffer = renderToBuffer(
            ScrollView(.horizontal) { Text(verbatim: paragraph) }.frame(width: 30, height: 4),
            context: makeRenderContext(width: 30, height: 4))
        let worded = buffer.lines.map(\.stripped).filter { $0.contains("w") }
        #expect(worded.count == 1, "\(worded)")
        #expect(worded.first?.hasPrefix("w0 w1 ") == true, "\(worded)")
    }
}
