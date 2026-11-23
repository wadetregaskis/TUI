//  🖥️ TUI — A Terminal UI framework for Swift
//  SoftHyphenWidthTests.swift
//
//  A soft hyphen, U+00AD, is one cell: every host measured advances it one
//  (Ghostty 1.4.0 and Apple Terminal 455.1, `advance_probe.py`), so a `Text`
//  holding one is measured and drawn at the cells the terminal gives it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("A soft hyphen takes the one cell terminals give it")
struct SoftHyphenWidthTests {
    private static let softHyphen: Unicode.Scalar = "\u{00AD}"

    @Test("U+00AD measures one cell, alone and between letters, by every width path")
    func measuresOneCell() {
        #expect(Self.softHyphen.loneTerminalWidth == 1)
        #expect(Character(Self.softHyphen).terminalWidth == 1)
        let text = "a\u{00AD}b"
        #expect(text.count == 3, "a soft hyphen is a grapheme of its own")
        #expect(text.strippedLength == 3)
        #expect(text.unicodeScalars.terminalRunWidth == 3)
        #expect(text.reduce(0) { $0 + $1.terminalWidth } == 3)
    }

    @Test("A Text holding one draws at three cells, and what follows lands after it")
    func textDrawsAtThreeCells() throws {
        let buffer = renderToBuffer(
            HStack(spacing: 0) {
                Text(verbatim: "a\u{00AD}b")
                Text(verbatim: "|")
            },
            context: makeRenderContext(width: 10, height: 1))
        #expect(buffer.width == 4)
        let line = try #require(buffer.lines.first)
        #expect(line.strippedLength == 4)
        #expect(line.contains("a\u{00AD}b"), "drawn as it is: \(line.debugDescription)")
    }
}
