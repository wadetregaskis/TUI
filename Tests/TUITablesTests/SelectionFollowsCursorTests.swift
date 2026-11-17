//  🖥️ TUI — A Terminal UI framework for Swift
//  SelectionFollowsCursorTests.swift
//
//  `.selectionFollowsCursor()` (the owner's APPFB-1, 2026-11-14): a key that
//  moves a list's or table's cursor selects the row it lands on, as macOS
//  does, where by default the cursor moves apart from the selection. One code
//  path in the handler every list and table keys through, so these tests reach
//  it from a `List`, a `Table` and a tree table, and check that the default is
//  unchanged.
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

private struct Node: Identifiable, Hashable, Sendable {
    let id: String
    var children: [Self]?
}

@Observable
@MainActor
private final class Selection {
    var single: String?
    var multiple: Set<String> = []
}

@MainActor
@Suite("Selection follows the cursor")
struct SelectionFollowsCursorTests {
    private let rows = ["alpha", "bravo", "charlie", "delta", "echo"].map(Row.init)

    private func list(_ selection: Selection, follows: Bool?) -> TestApp {
        let app = TestApp(width: 40, height: 12) {
            let list = List(selection: Binding(get: { selection.single }, set: { selection.single = $0 })) {
                ForEach(rows) { Text($0.id) }
            }
            if let follows {
                list.selectionFollowsCursor(follows)
            } else {
                list
            }
        }
        app.press(.tab)
        return app
    }

    private func table(_ selection: Selection) -> TestApp {
        let app = TestApp(width: 40, height: 12) {
            Table(rows, selection: Binding(get: { selection.single }, set: { selection.single = $0 })) {
                TableColumn("Name", value: \Row.id)
            }
            .selectionFollowsCursor()
        }
        app.press(.tab)
        return app
    }

    @Test("By default the arrows move a cursor and leave the selection alone")
    func defaultKeepsTheCursorApart() {
        let selection = Selection()
        let app = list(selection, follows: nil)
        app.press(.down)
        app.press(.down)
        #expect(selection.single == nil)
        app.press(.space)
        #expect(selection.single == "charlie")
    }

    @Test("A list's arrows, Home, End and paging keys select the row the cursor lands on")
    func listMovementSelects() {
        let selection = Selection()
        let app = list(selection, follows: true)
        // From nothing selected the first Down selects the first row, as on
        // macOS ("The first key from an empty selection", 2026-11-16).
        app.press(.down)
        #expect(selection.single == "alpha")
        app.press(.down)
        #expect(selection.single == "bravo")
        app.press(.end)
        #expect(selection.single == "echo")
        app.press(.up)
        #expect(selection.single == "delta")
        app.press(.home)
        #expect(selection.single == "alpha")
        app.press(.pageDown)
        #expect(selection.single == "echo")
    }

    @Test("`false` keeps the cursor apart below a `true`")
    func nearestWins() {
        let selection = Selection()
        let app = TestApp(width: 40, height: 12) {
            VStack {
                List(selection: Binding(get: { selection.single }, set: { selection.single = $0 })) {
                    ForEach(rows) { Text($0.id) }
                }
                .selectionFollowsCursor(false)
            }
            .selectionFollowsCursor()
        }
        app.press(.tab)
        app.press(.down)
        #expect(selection.single == nil)
    }

    @Test("Type select selects the row it finds")
    func typeSelectSelects() {
        let selection = Selection()
        let app = table(selection)
        app.press(.character("d"))
        app.advance(by: .milliseconds(20))
        #expect(selection.single == "delta")
    }

    @Test("A table's arrows select, and Space still toggles the cursor's row")
    func tableMovementSelectsAndSpaceToggles() {
        let selection = Selection()
        let app = table(selection)
        // From nothing selected the first Down selects the first row, as on
        // macOS ("The first key from an empty selection", 2026-11-16).
        app.press(.down)
        #expect(selection.single == "alpha")
        app.press(.down)
        #expect(selection.single == "bravo")
        // Space clearing it is the user's own act: the cursor stays placed,
        // and the next Down goes on from it (A-FIRSTKEY-3).
        app.press(.space)
        #expect(selection.single == nil)
        app.press(.down)
        #expect(selection.single == "charlie")
    }

    @Test("A multiple selection becomes the cursor's row alone; Space and Shift still build one")
    func multipleSelection() {
        let selection = Selection()
        let app = TestApp(width: 40, height: 12) {
            Table(rows, selection: Binding(get: { selection.multiple }, set: { selection.multiple = $0 })) {
                TableColumn("Name", value: \Row.id)
            }
            .selectionFollowsCursor()
        }
        app.press(.tab)
        // From nothing selected the first Down selects the first row, as on
        // macOS ("The first key from an empty selection", 2026-11-16).
        app.press(.down)
        #expect(selection.multiple == ["alpha"])
        app.press(.down)
        #expect(selection.multiple == ["bravo"])
        app.press(.down, modifiers: .shift)
        #expect(selection.multiple == ["bravo", "charlie"])
        app.press(.down)
        #expect(selection.multiple == ["delta"])
        app.press(.up, modifiers: .shift)
        #expect(selection.multiple == ["charlie", "delta"])
        // Ctrl-A selects them all, and a plain arrow then narrows it to one.
        app.press(.character("a"), modifiers: .control)
        #expect(selection.multiple.count == rows.count)
        app.press(.down)
        #expect(selection.multiple == ["delta"])
    }

    @Test("A tree table's Left onto the parent selects the parent")
    func treeLeftSelectsParent() {
        let selection = Selection()
        let tree = [Node(id: "root", children: [Node(id: "leaf")]), Node(id: "other")]
        let app = TestApp(width: 40, height: 12) {
            Table(tree, children: \.children, selection: Binding(get: { selection.single }, set: { selection.single = $0 })) {
                TableColumn("Name", value: \Node.id)
            }
            .selectionFollowsCursor()
        }
        app.press(.tab)
        // From nothing selected Down selects the first row, root ("The first
        // key from an empty selection", 2026-11-16), and Right opens it.
        app.press(.down)
        #expect(selection.single == "root")
        app.press(.right)  // opens root; the cursor stays on it
        app.press(.down)
        #expect(selection.single == "leaf")
        app.press(.left)
        #expect(selection.single == "root")
    }
}
