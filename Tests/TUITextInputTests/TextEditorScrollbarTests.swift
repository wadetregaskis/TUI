//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorScrollbarTests.swift
//
//  A TextEditor's scroll bar: where its thumb is and how long, at the
//  document's start, middle and end, wrapping and not, and that the bar is
//  drawn again only when what it is drawn from moves.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUITextInput

@MainActor
@Suite("TextEditor: its scroll bar")
struct TextEditorScrollbarTests {
    final class Box: @unchecked Sendable {
        var value: String
        init(_ value: String) { self.value = value }
    }

    struct Page: View {
        let text: Box
        let wraps: Bool
        var body: some View {
            TextEditor(text: Binding(get: { text.value }, set: { text.value = $0 }))
                .frame(width: 16, height: 10)
                .textEditorWrapsLines(wraps)
                .scrollIndicatorPlacement(.besideContent)
        }
    }

    /// Forty rows in a view ten tall: forty short lines, or, wrapping, twenty
    /// lines that each wrap into two rows at the fifteen cells beside the bar.
    static func document(wraps: Bool) -> String {
        wraps
            ? (0..<20).map { _ in "aaaa bbbb cccc dddd" }.joined(separator: "\n")
            : (0..<40).map { "line \($0)" }.joined(separator: "\n")
    }

    /// A focused editor 16 × 10 over `text`, drawn twice so it holds the focus.
    func editor(_ text: String, wraps: Bool) throws -> (InputChainHarness, Page, TextEditorHandler) {
        let harness = InputChainHarness(width: 40, height: 20)
        let page = Page(text: Box(text), wraps: wraps)
        harness.frame(page)
        harness.frame(page)
        let handler = try #require(harness.focusManager.currentFocused as? TextEditorHandler)
        return (harness, page, handler)
    }

    /// The rows the thumb covers: without colour a thumb's cell is a shade
    /// glyph and the track's a space, so the bar's column says where it is.
    func thumbRows(_ harness: InputChainHarness, _ page: Page) -> [Int] {
        let lines = withColorDepth(.noColor) { harness.frame(page).lines.prefix(10).map(\.stripped) }
        return lines.indices.filter { index in
            let line = Array(lines[index])
            return line.count >= 16 && line[15] != " "
        }
    }

    /// Puts the caret on `line` at `column` and draws a frame, so the scroll
    /// follows it.
    func caret(
        onLine line: Int, column: Int = 0, _ harness: InputChainHarness, _ page: Page, _ handler: TextEditorHandler
    ) {
        handler.moveCursor(toLine: line, column: column)
        harness.frame(page)
    }

    // Forty rows in ten: the thumb is a quarter of the track, 2.5 cells
    // (`ScrollbarRenderer.thumbSpan`: 20 of 80 eighths), travelling 60 eighths
    // over the 30 rows the view can scroll.

    @Test("At the start the thumb covers the bar's first rows", arguments: [false, true])
    func thumbAtStart(wraps: Bool) throws {
        let (harness, page, handler) = try editor(Self.document(wraps: wraps), wraps: wraps)
        caret(onLine: 0, harness, page, handler)
        // Eighths 0..<20: cells 0, 1 and half of 2.
        #expect(thumbRows(harness, page) == [0, 1, 2])
    }

    @Test("At the end the thumb covers the bar's last rows", arguments: [false, true])
    func thumbAtEnd(wraps: Bool) throws {
        let (harness, page, handler) = try editor(Self.document(wraps: wraps), wraps: wraps)
        caret(onLine: wraps ? 19 : 39, harness, page, handler)
        // Eighths 60..<80: half of cell 7, then 8 and 9.
        #expect(thumbRows(harness, page) == [7, 8, 9])
    }

    @Test("In the middle the thumb is where the scroll is", arguments: [false, true])
    func thumbInTheMiddle(wraps: Bool) throws {
        let (harness, page, handler) = try editor(Self.document(wraps: wraps), wraps: wraps)
        // Down to the end, then up to the 16th row, which the view's top row
        // becomes, 15 of the 30 it can scroll: wrapping, line 7's second row,
        // which starts at "dddd".
        caret(onLine: wraps ? 19 : 39, harness, page, handler)
        caret(onLine: wraps ? 7 : 15, column: wraps ? 15 : 0, harness, page, handler)
        // Eighths 30..<50: from the last quarter of cell 3 to the first of 6.
        #expect(thumbRows(harness, page) == [3, 4, 5, 6])
    }

    @Test("A document shorter than the view draws no bar, its text the full width", arguments: [false, true])
    func shortDocumentHasNoBar(wraps: Bool) throws {
        let (harness, page, handler) = try editor("one\ntwo\nthree", wraps: wraps)
        #expect(thumbRows(harness, page).isEmpty)
        if wraps {
            #expect(handler.wrappedRows()?.width == 16)
        } else {
            #expect(handler.sidewaysWidth == 16)
        }
    }

    @Test("Unmoved, the bar comes from the memo, alike; moved, it is drawn again")
    func memoAnswersUntilTheScrollMoves() throws {
        let (harness, page, handler) = try editor(Self.document(wraps: false), wraps: false)
        let first = harness.frame(page)
        let hits = handler.scrollbarMemoHits
        let second = harness.frame(page)
        #expect(handler.scrollbarMemoHits > hits, "the memo answered: \(handler.scrollbarMemoHits)")
        #expect(first.lines == second.lines)
        #expect(first.animatedCells.count == second.animatedCells.count)
        caret(onLine: 39, harness, page, handler)
        let hitsBefore = handler.scrollbarMemoHits
        let scrolled = harness.frame(page)
        // The frame the caret moved on drew the new bar; this one answers it.
        #expect(handler.scrollbarMemoHits == hitsBefore + 1)
        #expect(scrolled.lines != second.lines)
        #expect(thumbRows(harness, page) == [7, 8, 9])
    }

    @Test("A line added moves the extent, and the bar is drawn again for it")
    func extentInvalidates() throws {
        let box = Box(Self.document(wraps: false))
        let harness = InputChainHarness(width: 40, height: 20)
        let page = Page(text: box, wraps: false)
        harness.frame(page)
        harness.frame(page)
        #expect(thumbRows(harness, page) == [0, 1, 2])
        // Forty more lines: eighty rows in ten, a thumb of 10 eighths.
        box.value += "\n" + (40..<80).map { "line \($0)" }.joined(separator: "\n")
        #expect(thumbRows(harness, page) == [0, 1])
    }
}
