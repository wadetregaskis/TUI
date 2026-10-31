//  🖥️ TUI — A Terminal UI framework for Swift
//  ListDropGapHeightTests.swift
//
//  The landing gap a drag of several rows opens in a list: as tall as the rows
//  it would land, so what the drop does is what the list shows, whether they
//  came from elsewhere or from this list's own selection.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUILists
@testable import TUITestSupport

private final class Board: @unchecked Sendable {
    var selection: Set<String> = []
    var landed: [(index: Int, items: [String])] = []
}

@MainActor
@Suite("A list's landing gap for several rows", .serialized)
struct ListDropGapHeightTests {
    /// A list of `rows` with a selection, its rows `.draggable` where asked,
    /// taking a drop anywhere among them.
    private func list(_ rows: [String], _ board: Board, draggable: Bool = false, height: Int = 12) -> some View {
        let selection = Binding(get: { board.selection }, set: { board.selection = $0 })
        return List(selection: selection) {
            ForEach(rows, id: \.self) { row in
                if draggable { Text(row).draggable(row) } else { Text(row) }
            }
            .dropDestination(for: String.self) { items, index in board.landed.append((index, items)) }
        }
        .frame(width: 20, height: height)
    }

    /// A drawn line without the list's walls and padding.
    private func body(_ line: String) -> String {
        line.stripped.filter { !"│╭╮╰╯─".contains($0) }.trimmingCharacters(in: .whitespaces)
    }

    /// Starts a drag of `items` from elsewhere with the pointer at line `y`.
    private func hover(_ items: [String], y: Int, harness: InputChainHarness, _ build: () -> some View) -> [String] {
        let session = harness.tui.dragAndDropSession
        session.lastAbsoluteEvent = MouseEvent(button: .left, phase: .dragged, x: 2, y: y)
        if session.active == nil {
            session.begin(payload: DragItems(items: items), preview: FrameBuffer(text: items[0]))
        } else {
            session.dragMoved()
        }
        harness.frame(build())
        return harness.frame(build()).lines.map(body)
    }

    private func line(of row: String, in lines: [String]) -> Int? { lines.firstIndex(of: row) }

    @Test("Three rows dragged in from elsewhere open a gap three lines tall, and land there")
    func foreignDragOpensATallGap() {
        let board = Board()
        let harness = InputChainHarness(width: 30, height: 14)
        let rows = ["a", "b", "c", "d", "e"]
        func build() -> some View { list(rows, board) }
        let resting = harness.frame(build()).lines.map(body)
        let top = line(of: "c", in: resting) ?? -1
        #expect(top > 0, "\(resting)")

        let open = hover(["x", "y", "z"], y: top, harness: harness, build)
        #expect(line(of: "c", in: open) == top + 3, "\(open)")
        #expect(Array(open[top..<(top + 3)]) == ["", "", ""], "the gap holds nothing: \(open)")
        #expect(line(of: "b", in: open) == top - 1, "\(open)")

        // Anywhere in the gap holds it; on the row after it, it moves past that row.
        #expect(hover(["x", "y", "z"], y: top + 2, harness: harness, build) == open, "the gap is where the pointer is")
        let lower = hover(["x", "y", "z"], y: top + 3, harness: harness, build)
        #expect(line(of: "c", in: lower) == top, "\(lower)")
        #expect(line(of: "d", in: lower) == top + 4, "\(lower)")

        _ = harness.tui.dragAndDropSession.performDrop()
        #expect(board.landed.map(\.index) == [3], "after c")
        #expect(board.landed.first?.items == ["x", "y", "z"])
    }

    @Test("One row still opens one line")
    func oneRowOpensOneLine() {
        let board = Board()
        let harness = InputChainHarness(width: 30, height: 14)
        func build() -> some View { list(["a", "b", "c"], board) }
        let resting = harness.frame(build()).lines.map(body)
        let top = line(of: "b", in: resting) ?? -1
        harness.tui.dragAndDropSession.lastAbsoluteEvent = MouseEvent(button: .left, phase: .dragged, x: 2, y: top)
        harness.tui.dragAndDropSession.begin(payload: "x", preview: FrameBuffer(text: "x"))
        harness.frame(build())
        let open = harness.frame(build()).lines.map(body)
        #expect(line(of: "b", in: open) == top + 1, "\(open)")
    }

    /// The list says how many rows the taller gap pushed off, and scrolls to
    /// them: the gap's lines are in its extent, as one line's has been.
    @Test("A gap that pushes rows off says so, and the end of the list can still be reached")
    func aFullListCountsTheWholeGap() {
        let board = Board()
        let harness = InputChainHarness(width: 30, height: 14) { $0.scrollIndicatorStyle = .text }
        let rows = ["a", "b", "c", "d", "e", "f"]
        // Six rows and two walls: exactly full, with no line to spare.
        func build() -> some View { list(rows, board, height: 8) }
        let resting = harness.frame(build()).lines.map(body)
        #expect(resting.contains("f"), "\(resting)")
        #expect(!resting.contains { $0.contains("more") }, "\(resting)")

        let open = hover(["x", "y", "z"], y: 1, harness: harness, build)
        let drawn = rows.filter(open.contains)
        let below = open.first { $0.contains("below") }
        #expect(below?.contains("\(rows.count - drawn.count) rows") == true, "every row off the list is counted: \(open)")

        // The drag's navigators scroll what it is over: the end is in reach.
        harness.press(KeyEvent(key: .end))
        harness.frame(build())
        let bottom = harness.frame(build()).lines.map(body)
        #expect(bottom.contains("f"), "the last row can be brought into view: \(bottom)")
    }

    /// A gap that took the whole list would leave no row to aim at: the pointer
    /// would rest on the gap, which holds where it is.
    @Test("However many rows are dragged in, the gap leaves rows to aim at")
    func aGapLeavesRowsToAimAt() {
        let board = Board()
        let harness = InputChainHarness(width: 30, height: 14) { $0.scrollIndicatorStyle = .text }
        let rows = (0..<20).map { "r\($0)" }
        func build() -> some View { list(rows, board, height: 8) }
        harness.frame(build())
        let carried = (0..<50).map { "x\($0)" }
        let open = hover(carried, y: 1, harness: harness, build)
        #expect(open.filter(rows.contains).count >= 2, "\(open)")
    }

    /// Own selection: every selected row leaves the drawing, not only the first,
    /// and the one gap makes up the lines they gave, so nothing moves but them.
    @Test("A selection dragged within its own list leaves one gap, and the list keeps its length")
    func ownSelectionLeavesOneTallGap() {
        let board = Board()
        board.selection = ["b", "d"]
        let harness = InputChainHarness(width: 30, height: 14)
        let rows = ["a", "b", "c", "d", "e", "f"]
        func build() -> some View { list(rows, board, draggable: true) }
        let drawn = harness.frame(build()).lines
        let resting = drawn.map(body)
        let startB = line(of: "●b", in: resting) ?? -1
        let rowB = drawn[startB].stripped
        let columnB = rowB.distance(from: rowB.startIndex, to: rowB.firstIndex(of: "b") ?? rowB.startIndex)
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: columnB, y: startB))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: columnB + 1, y: startB + 1))
        harness.frame(build())
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: columnB + 2, y: startB + 1))
        let gathered = harness.frame(build()).lines.map(body)
        // Onto e's line, which is e again with both rows gone and the gap in
        // their place: the gap moves past it.
        let lineOfE = line(of: "e", in: resting) ?? -1
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: columnB, y: lineOfE))
        harness.frame(build())
        let open = harness.frame(build()).lines.map(body)
        let first = line(of: "a", in: open) ?? -1
        #expect(Array(open[first..<(first + 6)]) == ["a", "c", "e", "", "", "f"], "\(gathered) then \(open)")

        harness.mouse(MouseEvent(button: .left, phase: .released, x: columnB, y: lineOfE))
        harness.frame(build())
        #expect(board.landed.map(\.index) == [5], "before f, in the list's own numbering")
        #expect(board.landed.first?.items == ["b", "d"])
    }
}
