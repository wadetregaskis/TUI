//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHighlighterSPITests.swift
//
//  The highlighting seam as another package reaches it: through
//  `@_spi(TextEditorHighlighting) import TUITextInput` alone, with no
//  `@testable` (A-ATTRED-10 (b), lane H4′ of the highlighting design's §8.6).
//  A highlighter of the test's own, run by a real editor in a TestApp.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing
import TUITesting
@_spi(TextEditorHighlighting) import TUITextInput

/// Styles each line's first word as a `.keyword` and the rest as `.plain`:
/// the smallest highlighter, written as an adapter outside TUI would be.
private struct FirstWordHighlighter: TextEditorHighlighter {
    enum Token: Hashable, Sendable {
        case keyword, plain
    }

    func highlight(_ session: TextEditorHighlightSession<Token>) async {
        while let update = await session.nextUpdate() {
            let text = update.text
            let lines = update.visibleLines.clamped(to: 0..<text.lineCount)
            let tokens = lines.map { index in
                var tokens = TextEditorTokens<Token>()
                tokens.append(.keyword, at: 0)
                if let space = text.line(index).firstIndex(of: UInt8(ascii: " ")) {
                    tokens.append(.plain, at: text.line(index).distance(from: text.line(index).startIndex, to: space))
                }
                return tokens
            }
            session.publish(tokens, forLines: lines, of: text.version)
            do { try await session.checkpoint() } catch { return }
        }
    }
}

@MainActor
@Suite("The highlighting seam, through its SPI import")
struct TextEditorHighlighterSPITests {
    /// Pure red, as 24-bit colour sends it.
    static let red = "38;2;255;0;0"

    @Test("A highlighter given with the SPI modifier styles the editor's text", .timeLimit(.minutes(10)))
    func highlights() async throws {
        let app = TestApp(width: 30, height: 3) {
            TextEditor(text: .constant("func body\nlet value"))
                .textEditorHighlighter(FirstWordHighlighter()) { token in
                    var container = AttributeContainer()
                    if token == .keyword { container.foregroundColor = Color(red: 1, green: 0, blue: 0) }
                    return container
                }
        }
        try await app.wait(until: { app.screen.styledLines[0].contains(Self.red) })
        for (row, rest) in zip(app.screen.styledLines.prefix(2), ["body", "value"]) {
            // The red is the first word's alone: the second word is not. (Not
            // from the space on: a blank's ink is not drawn, so the frame
            // changes ink after it, not before.)
            let found = try #require(row.range(of: rest), "\(row.debugDescription)")
            #expect(row[..<found.lowerBound].contains(Self.red), "\(row.debugDescription)")
            #expect(!row[found.lowerBound...].contains(Self.red), "\(row.debugDescription)")
        }
        #expect(app.screen.lines.prefix(2) == ["func body", "let value"])
    }
}
