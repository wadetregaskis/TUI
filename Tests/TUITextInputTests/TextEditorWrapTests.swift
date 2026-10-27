//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorWrapTests.swift
//
//  A wrapping TextEditor, against what a SwiftUI TextEditor (an NSTextView)
//  does with the same text, measured on macOS 15.8: the rows it wraps into,
//  and where each key and click puts the caret.
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
@Suite("TextEditor: wrapping")
struct TextEditorWrapTests {
    final class Box: @unchecked Sendable {
        var value: String
        init(_ value: String) { self.value = value }
    }

    /// The probe's paragraph: it wraps into four rows at the probe's width.
    static let paragraph = "aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii jjjj kkkk llll"
    static let document = paragraph + "\nshort\n" + paragraph

    struct Page: View {
        let text: Box
        let width: Int
        let height: Int
        var wraps = true
        var affinity = TextSelectionAffinity.automatic
        var body: some View {
            TextEditor(text: Binding(get: { text.value }, set: { text.value = $0 }))
                .frame(width: width, height: height)
                .textEditorWrapsLines(wraps)
                .textSelectionAffinity(affinity)
        }
    }

    /// A harness drawing `text` in an editor `width` × `height`, focused.
    func editor(
        _ text: String = document, width: Int = 16, height: Int = 12, wraps: Bool = true,
        affinity: TextSelectionAffinity = .automatic
    ) throws -> (InputChainHarness, Page, TextEditorHandler) {
        let harness = InputChainHarness(width: 40, height: 20)
        let page = Page(text: Box(text), width: width, height: height, wraps: wraps, affinity: affinity)
        harness.frame(page)
        harness.frame(page)
        let handler = try #require(harness.focusManager.currentFocused as? TextEditorHandler)
        return (harness, page, handler)
    }

    func caret(_ handler: TextEditorHandler) -> [Int] { [handler.cursorLine, handler.cursorColumn] }

    func press(_ harness: InputChainHarness, _ page: Page, _ event: KeyEvent) {
        harness.press(event)
        harness.frame(page)
    }

    @Test("It wraps where an NSTextView does: after a run of spaces, which hangs")
    func rows() throws {
        let (harness, page, _) = try editor()
        let drawn = harness.frame(page).lines.map { $0.stripped.trimmingTrailingSpaces() }
        #expect(Array(drawn.prefix(9)) == [
            "aaaa bbbb cccc", "dddd eeee ffff", "gggg hhhh iiii", "jjjj kkkk llll", "short",
            "aaaa bbbb cccc", "dddd eeee ffff", "gggg hhhh iiii", "jjjj kkkk llll",
        ])
    }

    @Test("Down moves a row at a time, keeping the column through a short line")
    func downByRows() throws {
        let (harness, page, handler) = try editor()
        handler.moveCursor(toLine: 0, column: 7)
        var visited: [[Int]] = []
        for _ in 0..<5 {
            press(harness, page, KeyEvent(key: .down))
            visited.append(caret(handler))
        }
        // Offsets 22, 37, 52, 65 and 73 in the probe.
        #expect(visited == [[0, 22], [0, 37], [0, 52], [1, 5], [2, 7]])
    }

    /// D4X-FULLER: under `.automatic` the caret keeps the lean the macOS text
    /// system gives it — upstream after an edit, downstream after an arrow key
    /// (`CaretLean`).
    @Test("An edit that leaves the caret where a row wrapped leans it upstream; an arrow key, downstream")
    func caretLeanPerCaret() throws {
        let (harness, page, handler) = try editor("aaaa bbbb cccc", width: 6)
        handler.moveCursor(toLine: 0, column: 6)
        press(harness, page, KeyEvent(key: .backspace))
        #expect(caret(handler) == [0, 5], "at the wrap after \"aaaa \"")
        #expect(handler.caretAffinity == .upstream)
        press(harness, page, KeyEvent(key: .left))
        press(harness, page, KeyEvent(key: .right))
        #expect(caret(handler) == [0, 5])
        #expect(handler.caretAffinity == .downstream)
    }

    /// Upstream, the start of a wrapped row is drawn at the end of the row
    /// before it. Down put the caret there and read its row back upstream —
    /// the row it came from — so every later Down came back to the same place.
    @Test("Upstream, Down and Up move a row at a time, and a click lands on the row clicked")
    func upstreamRows() throws {
        let (harness, page, handler) = try editor("aaaa bbbb cccc", width: 6, affinity: .upstream)
        handler.moveCursor(toLine: 0, column: 0)
        var visited: [[Int]] = []
        for key in [KeyEvent(key: .down), KeyEvent(key: .down), KeyEvent(key: .up)] {
            press(harness, page, key)
            visited.append(caret(handler))
        }
        // Each row's first caret upstream is after its first character.
        #expect(visited == [[0, 6], [0, 11], [0, 6]])
        handler.moveCursor(toLine: 0, column: 0)
        press(harness, page, KeyEvent(key: .character("n"), ctrl: true))
        press(harness, page, KeyEvent(key: .character("n"), ctrl: true))
        #expect(caret(handler) == [0, 11])
        // A click at the start of the second row is on the second row.
        let drawn = harness.frame(page)
        let rowY = try #require(drawn.lines.firstIndex { $0.stripped.hasPrefix("bbbb") })
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 0, y: rowY))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 0, y: rowY))
        harness.frame(page)
        #expect(handler.caretRow(in: try #require(handler.wrappedRows())) == 1)
    }

    /// Upstream a caret cannot be on a wrapped row's first character — its
    /// start is drawn at the end of the row before — but a selection's end
    /// can: a drag that starts or ends on that cell takes the character.
    @Test("Upstream, a drag from or to a wrapped row's first cell selects its first character")
    func upstreamDragAtRowStart() throws {
        let (harness, page, handler) = try editor("aaaa bbbb cccc", width: 6, affinity: .upstream)
        let rowY = try #require(harness.frame(page).lines.firstIndex { $0.stripped.hasPrefix("bbbb") })
        func drag(from: Int, to: Int) throws -> String {
            harness.mouse(MouseEvent(button: .left, phase: .pressed, x: from, y: rowY))
            harness.frame(page)
            harness.mouse(MouseEvent(button: .left, phase: .dragged, x: to, y: rowY))
            harness.frame(page)
            harness.mouse(MouseEvent(button: .left, phase: .released, x: to, y: rowY))
            harness.frame(page)
            return handler.selectedText(try #require(handler.selectionRange))
        }
        #expect(try drag(from: 0, to: 4) == "bbbb")
        #expect(try drag(from: 4, to: 0) == "bbbb")
        // A plain click there still puts the caret on the row, after the
        // character (B-D4X-16).
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 0, y: rowY))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 0, y: rowY))
        harness.frame(page)
        #expect(caret(handler) == [0, 6])
    }

    /// A drag's head on a wrapped row's first character is on that row, not
    /// the row before (whose end the same offset is to an upstream caret):
    /// read there, the editor scrolled up a row under the pointer each time
    /// the drag came back to the top row's first cell.
    @Test("Upstream, a drag head on the top row's first cell scrolls nothing")
    func upstreamHeadOnTopRowStart() throws {
        let (harness, page, handler) = try editor("aaaa bbbb cccc dddd eeee", width: 6, height: 3, affinity: .upstream)
        handler.moveCursor(toLine: 0, column: 24)
        let rows = harness.frame(page).lines.map(\.stripped)
        try #require(zip(rows, ["cccc", "dddd", "eeee"]).allSatisfy { $0.hasPrefix($1) })
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 2, y: 1))
        harness.frame(page)
        for x in [0, 1, 0] {
            harness.mouse(MouseEvent(button: .left, phase: .dragged, x: x, y: 0))
            #expect(harness.frame(page).lines.first?.stripped.hasPrefix("cccc") == true)
        }
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 0, y: 0))
        #expect(harness.frame(page).lines.first?.stripped.hasPrefix("cccc") == true)
        #expect(handler.selectedText(try #require(handler.selectionRange)) == "cccc dd")
        // A Shift-click there is a selection's end too. The click before it
        // comes a second after the drag's press, a cell from it, so that it
        // is not a double-click, which would select a word.
        harness.now += 1_000_000_000
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 2, y: 2))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 2, y: 2))
        harness.frame(page)
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 0, y: 0, shift: true))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 0, y: 0, shift: true))
        #expect(harness.frame(page).lines.first?.stripped.hasPrefix("cccc") == true)
        #expect(handler.selectedText(try #require(handler.selectionRange)) == "cccc dddd ee")
    }

    /// Shift+Down from a drag's head on a wrapped row's first character
    /// moves the caret to the next row, as from any head on that row, and
    /// extends the selection there, as a vertical field's Shift+Down does.
    @Test("Upstream, Shift+Down from a drag head on a row's first cell moves the caret a row and extends the selection")
    func upstreamShiftDownFromRowStartHead() throws {
        let (harness, page, handler) = try editor("aa bbbbb ccccc ddddd", width: 6, affinity: .upstream)
        let rowY = try #require(harness.frame(page).lines.firstIndex { $0.stripped.hasPrefix("ccccc") })
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 3, y: rowY))
        harness.frame(page)
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 0, y: rowY))
        harness.frame(page)
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 0, y: rowY))
        harness.frame(page)
        try #require(caret(handler) == [0, 9])
        try #require(handler.selectionRange != nil)
        press(harness, page, KeyEvent(key: .down, shift: true))
        let rows = try #require(handler.wrappedRows())
        #expect(handler.caretRow(in: rows) == 3)
        #expect(caret(handler) == [0, 16])
        #expect(handler.selectionRange?.end == TextEditorPosition(line: 0, column: 16))
    }

    /// A drag that comes back onto its press leaves no selection, and its
    /// head is a caret, read by the editor's affinity like every caret:
    /// upstream, on a wrapped row's first cell, where a click there puts it,
    /// after the first character. Review round 2 of the follow-ups: it stayed
    /// at the row's start, drawn at the row's first cell, where no upstream
    /// caret is, and Up moved from that row.
    @Test("Upstream, a drag back onto its press on a row's first cell leaves the caret where a click puts it")
    func upstreamCollapsedDragIsACaret() throws {
        let (harness, page, handler) = try editor("aa bbbbb ccccc ddddd", width: 6, affinity: .upstream)
        let rowY = try #require(harness.frame(page).lines.firstIndex { $0.stripped.hasPrefix("ccccc") })
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 0, y: rowY))
        harness.frame(page)
        let clicked = caret(handler)
        try #require(clicked == [0, 10], "a click on the row's first cell is after its first character")
        for x in [1, 0] {
            harness.mouse(MouseEvent(button: .left, phase: .dragged, x: x, y: rowY))
            harness.frame(page)
        }
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 0, y: rowY))
        harness.frame(page)
        #expect(handler.selectionRange == nil)
        #expect(caret(handler) == clicked)
        #expect(handler.rowStartHead == nil)
    }

    @Test("Up from the first row goes to the start, and Down from the last to the end")
    func pastTheEnds() throws {
        let (harness, page, handler) = try editor()
        handler.moveCursor(toLine: 0, column: 3)
        press(harness, page, KeyEvent(key: .up))
        #expect(caret(handler) == [0, 0])
        handler.moveCursor(toLine: 2, column: Self.paragraph.count - 3)
        press(harness, page, KeyEvent(key: .down))
        #expect(caret(handler) == [2, Self.paragraph.count])
    }

    @Test("Ctrl-A and Ctrl-E keep the paragraph; Ctrl-P and Ctrl-N move a row")
    func emacsChords() throws {
        let (harness, page, handler) = try editor()
        let cases: [(Character, [Int])] = [("a", [0, 0]), ("e", [0, 59]), ("p", [0, 5]), ("n", [0, 35])]
        for (letter, expected) in cases {
            handler.moveCursor(toLine: 0, column: 20)
            press(harness, page, KeyEvent(key: .character(letter), ctrl: true))
            #expect(caret(handler) == expected, "Ctrl-\(letter)")
        }
    }

    @Test("Page Down moves a screen of rows, less one")
    func pageDown() throws {
        let (harness, page, handler) = try editor(height: 4)
        handler.moveCursor(toLine: 0, column: 2)
        press(harness, page, KeyEvent(key: .pageDown))
        // Three rows down from the first: the paragraph's fourth row.
        #expect(caret(handler) == [0, 47])
    }

    @Test("A click past a row's text lands before its hanging space, and on a later row on its character")
    func clicks() throws {
        let (harness, page, handler) = try editor()
        let lines = harness.frame(page).lines.map(\.stripped)
        let top = try #require(lines.firstIndex { $0.hasPrefix("aaaa") })
        let left = try #require(lines[top].range(of: "aaaa")).lowerBound.utf16Offset(in: lines[top])
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: left + 15, y: top))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: left + 15, y: top))
        #expect(caret(handler) == [0, 14])
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: left + 2, y: top + 1))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: left + 2, y: top + 1))
        #expect(caret(handler) == [0, 17])
    }

    @Test("A short editor scrolls by rows to keep the caret's row in view")
    func scrollsByRows() throws {
        let (harness, page, handler) = try editor(height: 3)
        handler.moveCursor(toLine: 1, column: 2)
        let drawn = harness.frame(page).lines.map { $0.stripped }
        #expect(drawn.contains { $0.hasPrefix("short") })
        #expect(!drawn.contains { $0.hasPrefix("aaaa bbbb") })
        #expect(handler.scrollLine == 0 && handler.scrollRowInLine == 2)
    }

    @Test("The scroll bar counts rows, and the text wraps a cell narrower beside it")
    func scrollBarCountsRows() throws {
        // Nine rows at fifteen cells; in a view five tall the bar takes a
        // column, and the text, laid out again at fourteen, takes more rows.
        let (_, _, handler) = try editor(width: 15, height: 5)
        let rows = try #require(handler.wrappedRows())
        #expect(rows.width == 14)
        #expect(rows.rowCount > 9)
    }

    @Test("A selection across a wrap is drawn on both rows")
    func selectionAcrossAWrap() throws {
        let (harness, page, handler) = try editor()
        handler.moveCursor(toLine: 0, column: 12)
        handler.startOrExtendSelection()
        handler.moveCursor(toLine: 0, column: 17)
        let drawn = harness.frame(page).lines
        let palette = harness.context.environment.palette
        let background = palette.fieldBackground.resolve(with: palette)
        let selection = TextFieldContentRenderer.selectionColors(palette: palette, background: background)
            .resolved(with: palette)
        let field = String(
            ANSIRenderer.backgroundCode(for: selection.isReversed ? selection.foreground : selection.background)
                .dropFirst(2).dropLast())
        #expect(drawn[0].contains(field))
        #expect(drawn[1].contains(field))
        #expect(!drawn[2].contains(field))
    }

    @Test("A tab after a wrap reaches its stop from the row's start")
    func tabsAfterAWrap() throws {
        let (harness, page, _) = try editor("aaaa bbbb cc\td", width: 10)
        let drawn = harness.frame(page).lines.map(\.stripped)
        // Row 1 is "cc", the tab to column 4, then "d".
        #expect(drawn[1].hasPrefix("cc  d"))
    }

    @Test(".textEditorWrapsLines(false) keeps a long line on one row and scrolls sideways")
    func sideways() throws {
        let (harness, page, handler) = try editor(wraps: false)
        #expect(handler.wrappedRows() == nil)
        handler.moveCursor(toLine: 0, column: 40)
        let drawn = harness.frame(page).lines.map(\.stripped)
        #expect(handler.scrollColumn > 0)
        #expect(!drawn[0].hasPrefix("aaaa"))
        // Three lines, three rows.
        #expect(drawn.count == 12 && drawn[3].trimmingTrailingSpaces().isEmpty)
    }

    @Test("The wheel scrolls the text and leaves the caret, until a key brings the view back to it")
    func wheelScrolls() throws {
        let (harness, page, handler) = try editor(height: 4)
        func top() throws -> Int {
            harness.frame(page)
            return handler.topRow(in: try #require(handler.wrappedRows()))
        }
        let last = try #require(handler.wrappedRows()).rowCount - 4
        #expect(try top() == 0)
        harness.mouse(MouseEvent(button: .scrollDown, phase: .scrolled, x: 2, y: 1))
        #expect(try top() == min(3, last))
        harness.mouse(MouseEvent(button: .scrollDown, phase: .scrolled, x: 2, y: 1))
        harness.mouse(MouseEvent(button: .scrollDown, phase: .scrolled, x: 2, y: 1))
        // No further than the last screenful; the caret has not moved.
        #expect(try top() == last)
        #expect(caret(handler) == [0, 0])
        harness.mouse(MouseEvent(button: .scrollUp, phase: .scrolled, x: 2, y: 1))
        #expect(try top() == last - 3)
        // A key brings the view back to the caret.
        press(harness, page, KeyEvent(key: .right))
        #expect(try top() == 0)

        // Scrolling sideways, by lines.
        let (lines, linesPage, lineHandler) = try editor(height: 2, wraps: false)
        lines.mouse(MouseEvent(button: .scrollDown, phase: .scrolled, x: 2, y: 1))
        lines.frame(linesPage)
        #expect(lineHandler.scrollLine == 1)
        #expect(caret(lineHandler) == [0, 0])
    }
}

private extension String {
    func trimmingTrailingSpaces() -> String {
        var text = self
        while text.last == " " { text.removeLast() }
        return text
    }
}
