//  🖥️ TUI — A Terminal UI framework for Swift
//  ListCursorFollowsRowTests.swift
//
//  The focus cursor stays on its row when the rows change under it: a row
//  inserted or removed above it, a sort, a branch opened above it. The cursor
//  was a row index and stayed where it was, on another row — the one Space,
//  Return and Delete then acted on.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUIApp
@testable import TUICore
@testable import TUIFoundation
import TUILists
import TUITesting

@Observable
@MainActor
private final class Rows {
    var names = (0..<8).map { "Row \($0)" }
    var selection: Set<String> = []
}

@MainActor
@Suite("The focus cursor stays on its row as the rows change")
struct ListCursorFollowsRowTests {
    /// A list of `rows` with the cursor on "Row 3", at the list's top, where
    /// the top-row hold moves nothing.
    private func listOnRow3(_ rows: Rows, height: Int = 12) -> TestApp {
        let app = TestApp(width: 30, height: height) {
            List(rows.names, id: \.self, selection: Binding(get: { rows.selection }, set: { rows.selection = $0 })) {
                Text($0)
            }
        }
        app.press(.tab)
        app.press(.down, times: 3)
        return app
    }

    @Test("A row inserted above the cursor leaves it on its row")
    func insertAbove() {
        let rows = Rows()
        let app = listOnRow3(rows)
        rows.names.insert("New", at: 0)
        app.advance(by: .milliseconds(20))
        app.press(.space)
        #expect(rows.selection == ["Row 3"])
    }

    @Test("Rows removed above the cursor leave it on its row")
    func removeAbove() {
        let rows = Rows()
        let app = listOnRow3(rows)
        rows.names.removeFirst(2)
        app.advance(by: .milliseconds(20))
        app.press(.space)
        #expect(rows.selection == ["Row 3"])
    }

    @Test("A sort takes the cursor with its row")
    func sort() {
        let rows = Rows()
        let app = listOnRow3(rows)
        rows.names.reverse()
        app.advance(by: .milliseconds(20))
        app.press(.space)
        #expect(rows.selection == ["Row 3"])
        app.press(.down)
        app.press(.space)
        #expect(rows.selection == ["Row 3", "Row 2"], "Down goes on from the row's new place")
    }

    @Test("Delete takes the row below into the cursor's place, as before")
    func deleteStillLandsBelow() {
        let rows = Rows()
        let app = TestApp(width: 30, height: 12) {
            List(selection: Binding(get: { rows.selection }, set: { rows.selection = $0 })) {
                ForEach(rows.names, id: \.self) { Text($0) }
                    .onDelete { rows.names.remove(atOffsets: $0) }
            }
        }
        app.press(.tab)
        app.press(.down, times: 3)
        app.press(.delete)
        app.press(.delete)
        #expect(rows.names == ["Row 0", "Row 1", "Row 2", "Row 5", "Row 6", "Row 7"])
        app.press(.space)
        #expect(rows.selection == ["Row 5"])
    }

    @Test("A row removed from under the cursor leaves it on the row after")
    func cursorRowRemoved() {
        let rows = Rows()
        let app = listOnRow3(rows)
        rows.names.remove(at: 3)
        app.advance(by: .milliseconds(20))
        app.press(.space)
        #expect(rows.selection == ["Row 4"])
    }

    @Test("In a scrolled list a row inserted between the top row and the cursor leaves it on its row")
    func insertBelowTheTopRow() {
        let rows = Rows()
        rows.names = (0..<40).map { "Row \($0)" }
        let app = TestApp(width: 30, height: 8) {
            List(rows.names, id: \.self, selection: Binding(get: { rows.selection }, set: { rows.selection = $0 })) {
                Text($0)
            }
        }
        app.press(.tab)
        app.press(.down, times: 20)
        let top = app.screen.lines.first { $0.contains("Row") } ?? ""
        rows.names.insert("New", at: 18)
        app.advance(by: .milliseconds(20))
        app.press(.space)
        #expect(rows.selection == ["Row 20"])
        #expect(app.screen.lines.first { $0.contains("Row") } == top, "the top row keeps its line")
    }
}
