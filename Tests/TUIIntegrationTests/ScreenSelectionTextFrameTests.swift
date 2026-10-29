//  🖥️ TUI — A Terminal UI framework for Swift
//  ScreenSelectionTextFrameTests.swift
//
//  A screen selection's highlight keeps to the text it crosses: each `Text`
//  files its frame, and the highlight is drawn on the frames, not on a padded
//  box's padding or the gap between two texts (the owner, 2026-10-28,
//  afternoon list #8). What is copied is unchanged.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

// MARK: - Through the app

@MainActor
@Suite("Screen selection: the highlight keeps to the text")
struct ScreenSelectionTextFrameTests {
    /// The contact card: texts of different widths, padded and bordered.
    struct Card: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("Ada Lovelace")
                Text("12 St James's Square")
                Text("ada@example.com")
            }
            .padding(.horizontal, 2)
            .border()
        }
    }

    struct SideBySide: View {
        var body: some View {
            HStack(spacing: 4) {
                Text("left")
                Text("right")
            }
            .padding(.horizontal, 2)
            .border()
        }
    }

    struct Wrapped: View {
        var body: some View {
            Text("alpha beta gamma delta")
                .frame(width: 12, alignment: .leading)
                .padding(.horizontal, 2)
                .border()
        }
    }

    struct Rows: View {
        var body: some View {
            List(["first row", "second row"], id: \.self) { name in
                Text(name).textSelection(.enabled)
            }
            .frame(height: 6)
        }
    }

    func harness(_ page: some View, log: SystemClipboardLog = SystemClipboardLog()) -> InputChainHarness {
        let harness = InputChainHarness(width: 40, height: 10)
        harness.tui.clipboardWriter = ClipboardWriter.stated(terminal: .unsupported, isLocal: true, log: log)
        harness.frame(page)
        harness.frame(page)
        return harness
    }

    /// Where `needle` is drawn: its first cell.
    func find(_ needle: String, in harness: InputChainHarness, _ page: some View) throws -> (x: Int, y: Int) {
        let lines = harness.frame(page).lines.map(\.stripped)
        let row = try #require(lines.firstIndex { $0.contains(needle) })
        let prefix = try #require(lines[row].range(of: needle)).lowerBound
        return (lines[row][..<prefix].count, row)
    }

    func drag(_ harness: InputChainHarness, from: (x: Int, y: Int), to: (x: Int, y: Int), page: some View) {
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: from.x, y: from.y))
        harness.frame(page)
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: to.x, y: to.y))
        harness.frame(page)
        harness.mouse(MouseEvent(button: .left, phase: .released, x: to.x, y: to.y))
        harness.frame(page)
    }

    /// The columns of row `y` the highlight is on.
    func highlighted(_ y: Int, in harness: InputChainHarness) -> [Int] {
        (0..<40).filter { harness.tui.screenSelection.highlights(ScreenSelection.Point(x: $0, y: y)) }
    }

    /// The columns of row `y` whose drawing the highlight changed: what is on
    /// screen, beside what ``highlighted(_:in:)`` answers.
    func repainted(_ y: Int, before: String, after: String) -> [Int] {
        func states(_ line: String) -> [SGRState] {
            var state = SGRState()
            var cells: [SGRState] = []
            for segment in line.ansiSegments() {
                switch segment {
                case .ansi(let sequence, _): state.apply(sequence)
                case .visible: cells.append(state)
                }
            }
            return cells
        }
        let old = states(before)
        let new = states(after)
        return (0..<min(old.count, new.count)).filter { old[$0] != new[$0] }
    }

    @Test("Over a padded card the highlight is the texts, not the padding or the blanks past them")
    func paddedCard() throws {
        let log = SystemClipboardLog()
        let page = Card()
        let harness = harness(page, log: log)
        let before = harness.frame(page).lines
        let name = try find("Ada Lovelace", in: harness, page)
        let street = try find("12 St", in: harness, page)
        let mail = try find("ada@example.com", in: harness, page)
        drag(harness, from: name, to: (mail.x + 14, mail.y), page: page)
        #expect(highlighted(name.y, in: harness) == Array(name.x..<(name.x + 12)))
        #expect(highlighted(street.y, in: harness) == Array(street.x..<(street.x + 20)))
        #expect(highlighted(mail.y, in: harness) == Array(mail.x..<(mail.x + 15)))
        // Drawn so: no padding cell, and no cell past a short text, is
        // repainted.
        let after = harness.frame(page).lines
        for row in [name.y, street.y, mail.y] {
            #expect(repainted(row, before: before[row], after: after[row]) == highlighted(row, in: harness))
        }
        // Copied as ever: the padding a row starts with is read with it.
        #expect(harness.tui.screenSelection.current?.text == "Ada Lovelace\n   12 St James's Square\n   ada@example.com")
        #expect(harness.press(KeyEvent(key: .character("c"), ctrl: true)))
        #expect(log.writes == ["Ada Lovelace\n   12 St James's Square\n   ada@example.com"])
    }

    @Test("Two texts side by side: each highlighted, the gap between them not, though it is copied")
    func sideBySide() throws {
        let page = SideBySide()
        let harness = harness(page)
        let left = try find("left", in: harness, page)
        let right = try find("right", in: harness, page)
        drag(harness, from: left, to: (right.x + 4, right.y), page: page)
        let words: [Int] = Array(left.x..<(left.x + 4)) + Array(right.x..<(right.x + 5))
        #expect(highlighted(left.y, in: harness) == words)
        #expect(harness.tui.screenSelection.current?.text == "left    right")
    }

    @Test("A wrapped text is highlighted as a block, to its trailing edge and no further")
    func wrapped() throws {
        let page = Wrapped()
        let harness = harness(page)
        let first = try find("alpha beta", in: harness, page)
        let second = try find("gamma delta", in: harness, page)
        try #require(first.x == second.x && second.y == first.y + 1, "precondition: it wraps at the frame")
        drag(harness, from: first, to: (second.x + 10, second.y), page: page)
        // The text's frame is its widest line, "gamma delta": the first line's
        // blank after "beta" is the text's; the frame's slack and the padding
        // are not.
        #expect(highlighted(first.y, in: harness) == Array(first.x..<(first.x + 11)))
        #expect(highlighted(second.y, in: harness) == Array(second.x..<(second.x + 11)))
        #expect(harness.tui.screenSelection.current?.text == "alpha beta\n   gamma delta")
    }

    @Test("A row served from the memo carries its text's frame")
    func memoServedRow() throws {
        let page = Rows()
        let harness = harness(page)
        let row = try find("first row", in: harness, page)
        drag(harness, from: row, to: (row.x + 20, row.y), page: page)
        try #require(harness.tui.screenSelection.current?.text == "first row")
        let served = harness.tui.renderCache.rowWork.servedDrawing
        harness.frame(page)
        try #require(harness.tui.renderCache.rowWork.servedDrawing > served, "precondition: the row was served")
        #expect(highlighted(row.y, in: harness) == Array(row.x..<(row.x + 9)))
    }
}

// MARK: - The rule

@Suite("Screen selection: what a row's highlight keeps to")
struct ScreenSelectionDrawnSpansTests {
    func spans(_ line: String, frames: [Range<Int>], pictures: [Range<Int>] = []) -> [String] {
        let cells = ScreenSelection.cells(of: line)
        return ScreenSelection.drawnSpans(of: 0..<cells.count, cells: cells, frames: frames, pictures: pictures)
            .map { span in String(span.compactMap { cells[$0] }) }
    }

    @Test("Frames exactly; drawing that is no text by its characters, bridged to its neighbours; walls never")
    func rule() {
        // A button's brackets and a text beside it, across a gap.
        #expect(spans("│ [ OK ]   Ada  │", frames: [11..<14]) == ["[ OK ]   Ada"])
        // Two texts: the gap between them is not bridged.
        #expect(spans("│ left    right │", frames: [2..<6, 10..<15]) == ["left", "right"])
        // A picture's cells are drawing, whatever their characters.
        #expect(spans("ab      ", frames: [0..<2], pictures: [2..<5]) == ["ab   "])
        #expect(spans("ab      ", frames: [0..<2]) == ["ab"])
    }

    @Test("A selection that crosses no frame is highlighted as it always was")
    func noFrame() {
        let lines = ["│  abc   │", "│        │"]
        let selection = ScreenSelection.Selection(
            anchor: .init(x: 1, y: 0), head: .init(x: 8, y: 1), clip: .init(x: 1, y: 0, width: 8, height: 2),
            shape: .stream, unit: .character, text: "")
        let spans = ScreenSelection.highlightedSpans(of: selection, frames: []) { ScreenSelection.cells(of: lines[$0]) }
        #expect(spans.map(\.row) == [0, 1])
        #expect(spans.map(\.spans) == [[1..<9], [1..<9]])
        // Crossing one, the blank row is not highlighted at all.
        let framed = ScreenSelection.highlightedSpans(of: selection, frames: [CellRect(x: 3, y: 0, width: 3, height: 1)]) {
            ScreenSelection.cells(of: lines[$0])
        }
        #expect(framed.map(\.row) == [0])
        #expect(framed.map(\.spans) == [[3..<6]])
    }
}
