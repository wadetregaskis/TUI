//  🖥️ TUI — A Terminal UI framework for Swift
//  CursorPastTheLastRowTests.swift
//
//  The rows shrinking from outside under a cursor near the end of a `List` or
//  `Table` left the cursor past the last row: no row showed the focus, and
//  Space, Return and Delete did nothing until an arrow key brought it back. It
//  lands on the new last row, where a delete of the last row puts it.
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
    var all = (0..<8).map(Entry.init)
    var selection: Set<Int> = []
}

@MainActor
@Suite("A cursor the rows shrink away from lands on the last row")
struct CursorPastTheLastRowTests {
    @Test("In a Table, Space after the last rows go selects the new last row")
    func table() {
        let entries = Entries()
        let app = TestApp(width: 30, height: 12) {
            Table(entries.all, selection: Binding(get: { entries.selection }, set: { entries.selection = $0 })) {
                TableColumn("Name", value: \Entry.name)
            }
        }
        app.press(.tab)
        app.press(.end)
        entries.all.removeLast(3)
        app.advance(by: .milliseconds(20))
        app.press(.space)
        #expect(entries.selection == [4])
    }

    @Test("In a List, Space after the last rows go selects the new last row")
    func list() {
        let entries = Entries()
        let app = TestApp(width: 30, height: 12) {
            List(entries.all, selection: Binding(get: { entries.selection }, set: { entries.selection = $0 })) {
                Text($0.name)
            }
        }
        app.press(.tab)
        app.press(.end)
        entries.all.removeLast(3)
        app.advance(by: .milliseconds(20))
        app.press(.space)
        #expect(entries.selection == [4])
    }
}
