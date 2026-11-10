//  🖥️ TUI — A Terminal UI framework for Swift
//  MiddleTruncationWideTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

/// A middle truncation splits the kept cells between the two ends. A wide
/// character cannot be split, so the start can keep a cell fewer than its
/// half; that cell goes to the end, rather than being left blank.
@MainActor
@Suite("A middle truncation of wide text fills its width")
struct MiddleTruncationWideTests {

    @Test("A cell the start cannot use goes to the end")
    func spareCellGoesToTheEnd() {
        #expect("日本語テキスト".truncatedToWidth(7, mode: .middle) == "日…スト")
        #expect("日本語テキスト".truncatedToWidth(3, mode: .middle) == "…ト")
        #expect("日本語テキスト".truncatedToWidth(5, mode: .middle) == "日…ト")
    }

    @Test("Narrow text is cut as before")
    func narrowUnchanged() {
        #expect("Supercalifragilistic".truncatedToWidth(11, mode: .middle) == "Super…istic")
    }

    @Test("Text draws the filled middle cut")
    func textDrawsIt() {
        let text = Text("日本語テキスト").truncationMode(.middle).lineLimit(1)
        let drawn = renderToBuffer(text, context: makeBareRenderContext(width: 7, height: 3)).lines.map(\.stripped)
        #expect(drawn == ["日…スト"])
    }
}
