//  🖥️ TUI — A Terminal UI framework for Swift
//  RangeAnchorFollowsItsRowTests.swift
//
//  The anchor a Shift-arrow or Shift-click range is measured from stays on its
//  row when the rows change under it. It was a row INDEX, so a row inserted
//  above it moved it onto the row before, and the next Shift-Down selected a
//  row the user never chose; the cursor already followed its row by id
//  (`ItemListHandler+CursorRow.swift`), the anchor now does too. An anchor
//  whose row is gone stays where it was, on the row that took its place, as
//  the cursor does.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUIApp
@testable import TUICore
@testable import TUIFoundation
import TUILists
import TUITables
import TUITesting

private struct Entry: Identifiable, Hashable, Sendable {
    let id: Int
    var name: String { "Entry \(id)" }
}

@Observable
@MainActor
private final class Entries {
    var all = (1...6).map(Entry.init)
    var selection: Set<Int> = []
}

@MainActor
@Suite("A range's anchor follows its row when the rows change")
struct RangeAnchorFollowsItsRowTests {
    private func table(_ entries: Entries) -> TestApp {
        TestApp(width: 30, height: 14) {
            Table(entries.all, selection: Binding(get: { entries.selection }, set: { entries.selection = $0 })) {
                TableColumn("Name", value: \Entry.name)
            }
        }
    }

    /// Space on Entry 3 anchors there; a row arrives at the top; Shift-Down
    /// selects Entry 3 and Entry 4 — not Entry 2, which the stale index named.
    @Test("In a Table, a row inserted above the anchor leaves the range on the anchor's row")
    func tableInsertAbove() {
        let entries = Entries()
        let app = table(entries)
        app.press(.down, times: 2)
        app.press(.space)
        #expect(entries.selection == [3])
        entries.all.insert(Entry(id: 99), at: 0)
        app.advance(by: .milliseconds(20))
        app.press(.down, modifiers: .shift)
        #expect(entries.selection == [3, 4])
    }

    /// The anchor below the cursor, and a row inserted between them: only the
    /// anchor's index moved, so nothing the cursor follows saw the change.
    @Test("In a Table, a row inserted between the cursor and an anchor below it leaves the range on the anchor's row")
    func tableInsertBetween() {
        let entries = Entries()
        let app = table(entries)
        app.press(.down, times: 4)
        app.press(.space)
        app.press(.up, modifiers: .shift)
        #expect(entries.selection == [4, 5])
        entries.all.insert(Entry(id: 99), at: 4)
        app.advance(by: .milliseconds(20))
        app.press(.up, modifiers: .shift)
        #expect(entries.selection == [3, 4, 99, 5])
    }

    /// A sort reverses the rows: the cursor follows Entry 3 and the anchor
    /// Entry 2, so Shift-Down from Entry 3 (now above Entry 2) lands on the
    /// anchor and the range is that one row — not Entries 5 to 2, which the
    /// stale index named.
    @Test("In a Table, a sort carries the anchor with its row")
    func tableSorted() {
        let entries = Entries()
        let app = table(entries)
        app.press(.down)
        app.press(.space)
        app.press(.down, modifiers: .shift)
        #expect(entries.selection == [2, 3])
        entries.all.reverse()
        app.advance(by: .milliseconds(20))
        app.press(.down, modifiers: .shift)
        #expect(entries.selection == [2])
    }

    @Test("In a List, a row inserted above the anchor leaves the range on the anchor's row")
    func listInsertAbove() {
        let entries = Entries()
        let app = TestApp(width: 30, height: 14) {
            List(entries.all, selection: Binding(get: { entries.selection }, set: { entries.selection = $0 })) {
                Text($0.name)
            }
        }
        app.press(.down, times: 2)
        app.press(.space)
        #expect(entries.selection == [3])
        entries.all.insert(Entry(id: 99), at: 0)
        app.advance(by: .milliseconds(20))
        app.press(.down, modifiers: .shift)
        #expect(entries.selection == [3, 4])
    }
}
