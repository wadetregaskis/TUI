//  🖥️ TUI — A Terminal UI framework for Swift
//  TableRowCarryTests.swift
//
//  A `.draggable` table row carried from the keyboard (A53-KEYBOARD-DRAG):
//  the table's pick-up chord carries the cursor row — the whole selection,
//  where it is one of several selected (DRAG-SELECTION) — to a destination
//  that takes it, and Copy takes its payload.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUILists
import TUITables
@testable import TUITestSupport

private let pickUp = KeyEvent(key: .character("r"), ctrl: true)

private struct Fruit: Identifiable {
    let id: String
    var name: String { id }
}

private final class Board: @unchecked Sendable {
    var selection: Set<String>
    var dropped: [String] = []

    init(selection: Set<String>) { self.selection = selection }
}

@MainActor
@Suite("A draggable table row carried from the keyboard")
struct TableRowCarryTests {
    /// A table of draggable rows above a list that takes them.
    private func board(_ board: Board) -> some View {
        let selection = Binding(get: { board.selection }, set: { board.selection = $0 })
        return VStack(alignment: .leading, spacing: 0) {
            Table(of: Fruit.self, selection: selection) {
                TableColumn("Name", value: \.name)
            } rows: {
                ForEach(["apple", "pear", "plum"].map(Fruit.init)) { item in
                    TableRow(item).draggable(item.name)
                }
            }
            .frame(height: 7)
            List {
                ForEach(["x", "y"], id: \.self) { Text($0) }
                    .dropDestination(for: String.self) { items, _ in board.dropped += items }
            }
            .frame(height: 4)
        }
    }

    @Test("Ctrl-R on a selected row carries the whole selection, Tab takes it to the list, Return drops it")
    func carriesTheSelectionToAList() {
        let board = Board(selection: ["plum", "apple"])
        let harness = InputChainHarness(width: 30, height: 14)
        let consumed = harness.play([pickUp, KeyEvent(key: .tab), KeyEvent(key: .enter)]) { self.board(board) }
        #expect(consumed == [true, true, true])
        #expect(board.dropped == ["apple", "plum"], "the selection, in the table's order")
        #expect(harness.tui.dragAndDropSession.active == nil)
    }

    @Test("A row that is not selected carries itself alone, and Escape puts it back")
    func unselectedRowCarriesItself() {
        let board = Board(selection: [])
        let harness = InputChainHarness(width: 30, height: 14)
        harness.play([pickUp, KeyEvent(key: .tab), KeyEvent(key: .escape)]) { self.board(board) }
        #expect(board.dropped.isEmpty, "put back")
        harness.play([pickUp, KeyEvent(key: .tab), KeyEvent(key: .enter)]) { self.board(board) }
        #expect(board.dropped == ["apple"])
    }

    @Test("Copy on the table copies the cursor row's payload")
    func copyTakesTheCursorRow() {
        let clipboard = FakeClipboard()
        let typed = TypedClipboard()
        let harness = InputChainHarness(width: 30, height: 14) {
            $0.clipboardAccess = clipboard.access
            $0.typedClipboard = typed
        }
        let board = Board(selection: [])
        let consumed = harness.play([KeyEvent(key: .down), KeyEvent(key: .character("c"), ctrl: true)]) {
            self.board(board)
        }
        #expect(consumed == [true, true])
        #expect(clipboard.writes == ["pear"])
    }

    @Test("Copy on a selected row copies the whole selection, in the table's order")
    func copyTakesTheSelection() {
        let clipboard = FakeClipboard()
        let typed = TypedClipboard()
        let harness = InputChainHarness(width: 30, height: 14) {
            $0.clipboardAccess = clipboard.access
            $0.typedClipboard = typed
        }
        let board = Board(selection: ["plum", "apple"])
        let consumed = harness.play([KeyEvent(key: .character("c"), ctrl: true)]) { self.board(board) }
        #expect(consumed == [true])
        #expect(clipboard.writes == ["apple\nplum"])
    }
}
