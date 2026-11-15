//  🖥️ TUI — A Terminal UI framework for Swift
//  CursorFollowsWrittenSelectionTests.swift
//
//  A selection the app writes moves a list's or table's cursor onto it, so
//  the next arrow goes on from there, as it does on macOS, where the cursor is
//  the selection — with `.selectionFollowsCursor()` and without it (tuitree's
//  feedback, Milestone 2 item 3). The list's own writes — Space toggling the
//  cursor's row off, say — leave the cursor where it is.
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

private struct Row: Identifiable, Hashable, Sendable {
    let id: String
}

@Observable
@MainActor
private final class Written {
    var single: String?
    var multiple: Set<String> = []
}

@MainActor
@Suite("The cursor follows a selection the app writes")
struct CursorFollowsWrittenSelectionTests {
    private let rows = ["alpha", "bravo", "charlie", "delta", "echo"].map(Row.init)

    /// A focused table whose `j` key selects "delta", as an app's Find
    /// selects a match.
    private func table(_ written: Written, follows: Bool) -> TestApp {
        let app = TestApp(width: 40, height: 12) {
            Table(rows, selection: Binding(get: { written.single }, set: { written.single = $0 })) {
                TableColumn("Name", value: \Row.id)
            }
            .selectionFollowsCursor(follows)
            .onKeyPress("j") {
                written.single = "delta"
                return .handled
            }
        }
        app.press(.tab)
        return app
    }

    /// A focused list with a multiple selection whose `j` key selects "delta"
    /// alone.
    private func multipleList(_ written: Written) -> TestApp {
        let app = TestApp(width: 40, height: 12) {
            List(selection: Binding(get: { written.multiple }, set: { written.multiple = $0 })) {
                ForEach(rows) { Text($0.id) }
            }
            .onKeyPress("j") {
                written.multiple = ["delta"]
                return .handled
            }
        }
        app.press(.tab)
        return app
    }

    @Test("Under .selectionFollowsCursor(), the next arrow selects the row after the one written")
    func followingTableGoesOnFromTheWrittenRow() {
        let written = Written()
        let app = table(written, follows: true)
        app.press(.character("j"))
        #expect(written.single == "delta")
        app.press(.down)
        #expect(written.single == "echo")
    }

    @Test("Without it, the cursor moves onto the row written, and Space after an arrow selects from there")
    func plainTableGoesOnFromTheWrittenRow() {
        let written = Written()
        let app = table(written, follows: false)
        app.press(.character("j"))
        app.press(.up)
        app.press(.space)
        #expect(written.single == "charlie")
    }

    @Test("A multiple selection written moves the cursor onto its row")
    func multipleSelectionWritten() {
        let written = Written()
        let app = multipleList(written)
        app.press(.character("j"))
        app.press(.down)
        app.press(.space)
        #expect(written.multiple == ["delta", "echo"])
    }

    @Test("The list's own write — Space toggling the cursor's row off — leaves the cursor where it is")
    func ownWriteLeavesTheCursor() {
        let written = Written()
        let app = multipleList(written)
        app.press(.down)
        app.press(.space)
        app.press(.down)
        app.press(.space)
        #expect(written.multiple == ["bravo", "charlie"])
        // Off again: the cursor stays on charlie, not on the selection left.
        app.press(.space)
        #expect(written.multiple == ["bravo"])
        app.press(.down)
        app.press(.space)
        #expect(written.multiple == ["bravo", "delta"])
    }
}
