//  🖥️ TUI — A Terminal UI framework for Swift
//  SelectionModeChangeTests.swift
//
//  A list or table whose kind of selection changes at the same identity:
//  SwiftUI's edit-mode idiom, `List(selection: isEditing ? $picked : nil)`,
//  first draws a list with no binding and later hands it a `Set`. The list's
//  handler is made once and kept, and took its mode from the first frame, so
//  a list first drawn with `nil` stayed a single-selection list and never
//  selected anything (hunt item LISTS-3).
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
    let id: Int
    var name: String { "row-\(id)-" }
}

@Observable
@MainActor
private final class Editing {
    var isEditing = false
    var picked: Set<Int> = []
    var single: Int?

    var binding: Binding<Set<Int>>? {
        isEditing ? Binding(get: { self.picked }, set: { self.picked = $0 }) : nil
    }
}

@MainActor
@Suite("A list or table whose selection changes kind")
struct SelectionModeChangeTests {
    private let rows = (0..<5).map(Row.init)

    @Test("A list first drawn with no Set binding selects once it is given one")
    func listGivenASetLater() {
        let editing = Editing()
        let app = TestApp(width: 40, height: 10) {
            List(selection: editing.binding) {
                ForEach(rows) { Text(verbatim: $0.name) }
            }
        }
        app.press(.tab)
        editing.isEditing = true
        _ = app.screen  // the frame that hands the list its binding; the cursor is on row 0
        app.press(.space)
        #expect(editing.picked == [0])
        app.press(.down)
        app.press(.space)
        #expect(editing.picked == [0, 1], "a Set list toggles, it does not replace")
    }

    @Test("A list over data first drawn with no Set binding selects once it is given one")
    func listOverDataGivenASetLater() {
        let editing = Editing()
        let app = TestApp(width: 40, height: 10) {
            List(rows, selection: editing.binding) { Text(verbatim: $0.name) }
        }
        app.press(.tab)
        editing.isEditing = true
        _ = app.screen  // the frame that hands the list its binding; the cursor is on row 0
        app.press(.space)
        #expect(editing.picked == [0])
    }

    /// The Shift anchor the single list had is not the multiple one's: ⌃A and
    /// extend mode start afresh.
    @Test("The multiple selection's own keys are offered once the Set arrives")
    func multipleKeysOnceTheSetArrives() {
        let editing = Editing()
        let app = TestApp(width: 40, height: 10) {
            List(selection: editing.binding) {
                ForEach(rows) { Text(verbatim: $0.name) }
            }
        }
        app.press(.tab)
        editing.isEditing = true
        _ = app.screen  // the frame that hands the list its binding; the cursor is on row 0
        app.press(.character("a"), modifiers: .control)
        #expect(editing.picked == Set(0..<5))
    }

    /// `Table`'s selection bindings are never optional, so its twin is a table
    /// rebuilt at the same identity from the selectionless initialiser to the
    /// `Set` one.
    @Test("A table first drawn without a selection selects once it is given a Set")
    func tableGivenASetLater() {
        let editing = Editing()
        let app = TestApp(width: 40, height: 10) {
            let table: Table<Row> =
                if let binding = editing.binding {
                    Table(rows, selection: binding) { TableColumn("Name", value: \Row.name) }
                } else {
                    Table(rows) { TableColumn("Name", value: \Row.name) }
                }
            table
        }
        app.press(.tab)
        editing.isEditing = true
        _ = app.screen  // the frame that hands the list its binding; the cursor is on row 0
        app.press(.space)
        #expect(editing.picked == [0])
    }
}
