//  🖥️ TUI — A Terminal UI framework for Swift
//  ListRowCarryTests.swift
//
//  A `.draggable` list row carried from the keyboard (A53-KEYBOARD-DRAG): the
//  list's pick-up chord carries the cursor row — the whole selection, where
//  it is one of several selected (DRAG-SELECTION) — among the destinations
//  that take it, its own list included, and Copy takes its payload.
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

private let pickUp = KeyEvent(key: .character("r"), ctrl: true)

private final class Board: @unchecked Sendable {
    var selection: Set<String>
    var moved: [String] = []
    var movedAt: Int?
    var reordered: [String] = []
    var reorderedAt: Int?

    init(selection: Set<String>) { self.selection = selection }
}

@MainActor
@Suite("A draggable list row carried from the keyboard")
struct ListRowCarryTests {
    /// Two lists side by side: "queue", whose rows are dragged and which takes
    /// its own rows back, and "backlog", which takes them.
    private func lists(_ board: Board) -> some View {
        let selection = Binding(get: { board.selection }, set: { board.selection = $0 })
        return HStack(alignment: .top) {
            List(selection: selection) {
                ForEach(["a", "b", "c", "d"], id: \.self) { Text($0).draggable($0) }
                    .dropDestination(for: String.self) { items, index in
                        board.reordered += items
                        board.reorderedAt = index
                    }
            }
            .frame(width: 10, height: 6)
            List {
                ForEach(["x", "y"], id: \.self) { Text($0) }
                    .dropDestination(for: String.self) { items, index in
                        board.moved += items
                        board.movedAt = index
                    }
            }
            .frame(width: 10, height: 6)
        }
    }

    @Test("Ctrl-R on a selected row carries the whole selection, Tab takes it to the other list, Return drops it")
    func carriesTheSelectionToAnotherList() {
        let board = Board(selection: ["a", "c"])
        let harness = InputChainHarness()
        let consumed = harness.play([pickUp, KeyEvent(key: .tab), KeyEvent(key: .enter)]) { lists(board) }
        #expect(consumed == [true, true, true])
        #expect(board.moved == ["a", "c"], "the selection, in the list's order")
        #expect(board.reordered.isEmpty)
        #expect(harness.tui.dragAndDropSession.active == nil)
    }

    @Test("A row that is not selected carries itself alone")
    func unselectedRowCarriesItself() {
        let board = Board(selection: ["c", "d"])
        let harness = InputChainHarness()
        harness.play([pickUp, KeyEvent(key: .tab), KeyEvent(key: .enter)]) { lists(board) }
        #expect(board.moved == ["a"])
    }

    @Test("At its own list, Return puts the row back until Down moves it, and then reorders")
    func reordersWithinItsOwnList() {
        let board = Board(selection: [])
        let harness = InputChainHarness()
        harness.play([pickUp]) { lists(board) }
        let session = harness.tui.dragAndDropSession
        #expect(session.active != nil, "picked up")
        #expect(session.carryLabels?.returnKey == "cancel move", "home, Return puts it back")
        harness.play([KeyEvent(key: .down), KeyEvent(key: .down), KeyEvent(key: .enter)]) { lists(board) }
        #expect(board.reordered == ["a"])
        if let index = board.reorderedAt { #expect(index > 1, "two rows down: \(index)") }
        #expect(board.moved.isEmpty)
    }

    @Test("Escape puts the carried row back")
    func escapePutsItBack() {
        let board = Board(selection: [])
        let harness = InputChainHarness()
        harness.play([pickUp, KeyEvent(key: .tab), KeyEvent(key: .escape)]) { lists(board) }
        #expect(board.moved.isEmpty && board.reordered.isEmpty)
        #expect(harness.tui.dragAndDropSession.active == nil)
    }

    /// A carry's Down moves the gap a row, however many lines the gap is tall:
    /// stepping the pointer a line at a time left it inside the gap for as many
    /// presses as rows were carried, and the keys did nothing.
    @Test("Down moves a tall landing gap one row")
    func downMovesATallGap() {
        let board = Board(selection: ["a", "c"])
        let harness = InputChainHarness()
        harness.play([pickUp, KeyEvent(key: .tab), KeyEvent(key: .down), KeyEvent(key: .enter)]) { lists(board) }
        #expect(board.moved == ["a", "c"])
        #expect(board.movedAt == 1, "after x: \(board.movedAt as Any)")
    }

    @Test("Copy on the list copies the cursor row's payload")
    func copyTakesTheCursorRow() {
        let clipboard = FakeClipboard()
        let typed = TypedClipboard()
        let harness = InputChainHarness {
            $0.clipboardAccess = clipboard.access
            $0.typedClipboard = typed
        }
        let board = Board(selection: [])
        let consumed = harness.play([KeyEvent(key: .down), KeyEvent(key: .character("c"), ctrl: true)]) {
            lists(board)
        }
        #expect(consumed == [true, true])
        #expect(clipboard.writes == ["b"])
    }

    /// As the pointer's drag carries (DRAG-SELECTION): no gesture of the mouse
    /// without one of the keyboard. The row off the list's window is drawn for
    /// the copy, as it is for a drag.
    @Test("Copy on a selected row copies the whole selection, in the list's order")
    func copyTakesTheSelection() {
        let clipboard = FakeClipboard()
        let typed = TypedClipboard()
        let harness = InputChainHarness {
            $0.clipboardAccess = clipboard.access
            $0.typedClipboard = typed
        }
        let names = (0..<40).map { "row\($0)" }
        let board = Board(selection: ["row30", "row0"])
        let selection = Binding(get: { board.selection }, set: { board.selection = $0 })
        let consumed = harness.play([KeyEvent(key: .character("c"), ctrl: true)]) {
            List(names, id: \.self, selection: selection) { Text($0).draggable($0) }.frame(width: 10, height: 6)
        }
        #expect(consumed == [true])
        #expect(clipboard.writes == ["row0\nrow30"])
        #expect(typed.values(as: String.self, ifClipboardHolds: "row0\nrow30") == ["row0", "row30"], "kept typed, for a paste")
    }

    @Test("Copy on a row that is not selected copies that row alone")
    func copyOutsideTheSelection() {
        let clipboard = FakeClipboard()
        let typed = TypedClipboard()
        let harness = InputChainHarness {
            $0.clipboardAccess = clipboard.access
            $0.typedClipboard = typed
        }
        let board = Board(selection: ["c", "d"])
        harness.play([KeyEvent(key: .character("c"), ctrl: true)]) { lists(board) }
        #expect(clipboard.writes == ["a"])
    }
}
