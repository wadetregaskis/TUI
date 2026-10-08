//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EditActionsTests.swift
//
//  `ForEach($items, editActions:)` — the ForEach editing its own collection.
//
//  Driven through a real `List` and the real mouse/key dispatchers rather than
//  by calling the synthesised closures: the point of naming an action is that
//  the LIST arms a gesture for it, and a set that filled in the closures while
//  the list never offered the gesture would pass any test that called them
//  directly.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitLists

@MainActor
@Suite("EditActions")
struct EditActionsTests {

    private struct Row: Identifiable, Equatable {
        let id: Int
        var name: String
    }

    @MainActor
    private final class Fixture {
        var rows: [Row]
        let tui = TUIContext()
        var env = EnvironmentValues()

        init(_ rows: [Row]) {
            self.rows = rows
            env.focusManager = FocusManager()
            env.scrollIndicatorStyle = .text
            env.applyRuntimeServices(from: tui)
            tui.mouseEventDispatcher.setActiveSupport(.full)
            tui.dragAndDropSession.dispatcher = tui.mouseEventDispatcher
        }

        var binding: Binding<[Row]> {
            Binding(get: { self.rows }, set: { self.rows = $0 })
        }

        @discardableResult
        func render(_ view: some View) -> FrameBuffer {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.dragAndDropSession.beginFrame()
            let context = RenderContext(
                availableWidth: 24, availableHeight: 10, environment: env, tuiContext: tui)
            let buffer = renderToBuffer(view, context: context)
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        /// The list's handler, reachable once the list has registered focus.
        var handler: ItemListHandler<Int>? {
            env.focusManager?.currentFocused as? ItemListHandler<Int>
        }
    }

    private func names(_ fixture: Fixture) -> [String] {
        fixture.rows.map(\.name)
    }

    @Test(".move fills in the reorder, and the list arms the gesture")
    func moveEdits() {
        let fixture = Fixture([Row(id: 1, name: "a"), Row(id: 2, name: "b"), Row(id: 3, name: "c")])
        fixture.render(
            List(selection: .constant(Int?.none)) {
                ForEach(fixture.binding, editActions: .move) { $row in Text(row.name) }
            }
            .frame(height: 8))

        guard let handler = fixture.handler else {
            Issue.record("the list registered focus")
            return
        }
        #expect(handler.onMove != nil, "the list was told the rows can move")
        #expect(handler.onDelete == nil, ".move alone does not arm deletion")

        handler.onMove?(IndexSet(integer: 0), 3)
        #expect(names(fixture) == ["b", "c", "a"])
    }

    @Test(".delete fills in the removal")
    func deleteEdits() {
        let fixture = Fixture([Row(id: 1, name: "a"), Row(id: 2, name: "b"), Row(id: 3, name: "c")])
        fixture.render(
            List(selection: .constant(Int?.none)) {
                ForEach(fixture.binding, editActions: .delete) { $row in Text(row.name) }
            }
            .frame(height: 8))

        guard let handler = fixture.handler else {
            Issue.record("the list registered focus")
            return
        }
        #expect(handler.onDelete != nil)
        #expect(handler.onMove == nil, ".delete alone does not arm reordering")

        handler.onDelete?(IndexSet(integer: 1))
        #expect(names(fixture) == ["a", "c"])
    }

    @Test(".all arms both")
    func allEdits() {
        let fixture = Fixture([Row(id: 1, name: "a"), Row(id: 2, name: "b")])
        fixture.render(
            List(selection: .constant(Int?.none)) {
                ForEach(fixture.binding, editActions: .all) { $row in Text(row.name) }
            }
            .frame(height: 8))

        guard let handler = fixture.handler else {
            Issue.record("the list registered focus")
            return
        }
        #expect(handler.onMove != nil)
        #expect(handler.onDelete != nil)
    }

    @Test("An empty set arms nothing")
    func noEdits() {
        let fixture = Fixture([Row(id: 1, name: "a"), Row(id: 2, name: "b")])
        fixture.render(
            List(selection: .constant(Int?.none)) {
                ForEach(fixture.binding, editActions: []) { $row in Text(row.name) }
            }
            .frame(height: 8))

        guard let handler = fixture.handler else {
            Issue.record("the list registered focus")
            return
        }
        #expect(handler.onMove == nil, "no gesture is armed for an action nobody named")
        #expect(handler.onDelete == nil)
    }

    @Test("The rows are still bindings, so a row can edit its own element")
    func rowsAreStillBindings() {
        let fixture = Fixture([Row(id: 1, name: "a"), Row(id: 2, name: "b")])
        var captured: [Binding<Row>] = []
        fixture.render(
            List(selection: .constant(Int?.none)) {
                ForEach(fixture.binding, editActions: .all) { row in
                    // Captured from inside the builder, which is where the
                    // per-row binding actually exists.
                    Text(row.wrappedValue.name)
                        .onGeometryChange(for: Int.self) { _ in 0 } action: { _ in
                            captured.append(row)
                        }
                }
            }
            .frame(height: 8))

        #expect(captured.count == 2)
        captured.first?.name.wrappedValue = "edited"
        #expect(names(fixture) == ["edited", "b"])
    }

    @Test("The id: form takes edit actions too")
    func keyPathIdentifiedForm() {
        let fixture = Fixture([Row(id: 1, name: "a"), Row(id: 2, name: "b")])
        fixture.render(
            List(selection: .constant(String?.none)) {
                ForEach(fixture.binding, id: \.name, editActions: .all) { $row in
                    Text(row.name)
                }
            }
            .frame(height: 8))

        let handler = fixture.env.focusManager?.currentFocused as? ItemListHandler<String>
        #expect(handler?.onMove != nil)
        #expect(handler?.onDelete != nil)
    }

    // MARK: - The loop's data

    @Test("The loop iterates an IndexedIdentifierCollection: the positions, each with its element's id")
    func dataIsIndexedIdentifiers() {
        let fixture = Fixture([Row(id: 7, name: "a"), Row(id: 9, name: "b"), Row(id: 4, name: "c")])
        let loop: ForEach<IndexedIdentifierCollection<[Row], Int>, Int, Text> =
            ForEach(fixture.binding, editActions: .all) { $row in Text(row.name) }
        #expect(loop.data.startIndex == 0 && loop.data.endIndex == 3)
        #expect(loop.data.map(\.index) == [0, 1, 2])
        #expect(loop.data.map(\.id) == [7, 9, 4])
        #expect(loop.data[loop.data.index(before: loop.data.endIndex)].id == 4)
        #expect(loop.data.index(after: 0) == 1)
        let byName: ForEach<IndexedIdentifierCollection<[Row], String>, String, Text> =
            ForEach(fixture.binding, id: \.name, editActions: .move) { $row in Text(row.name) }
        #expect(byName.data.map(\.id) == ["a", "b", "c"])
    }

    // MARK: - List(_:editActions:)

    @Test("List(_:editActions:rowContent:) edits the bound collection and arms both gestures")
    func listForm() {
        let fixture = Fixture([Row(id: 1, name: "a"), Row(id: 2, name: "b"), Row(id: 3, name: "c")])
        let lines = fixture.render(
            List(fixture.binding, editActions: .all) { $row in Text(row.name) }
                .frame(height: 8)
        ).lines.map(\.stripped)
        #expect(lines.contains { $0.contains("a") } && lines.contains { $0.contains("c") })
        guard let handler = fixture.handler else {
            Issue.record("the list registered focus")
            return
        }
        handler.onMove?(IndexSet(integer: 0), 3)
        #expect(names(fixture) == ["b", "c", "a"])
        handler.onDelete?(IndexSet(integer: 0))
        #expect(names(fixture) == ["c", "a"])
    }

    @Test("The selection forms bind the elements' ids", arguments: [false, true])
    func listSelectionForms(multiple: Bool) {
        let fixture = Fixture([Row(id: 1, name: "a"), Row(id: 2, name: "b")])
        var single: Int?
        var many: Set<Int> = []
        let view: AnyView =
            multiple
            ? AnyView(
                List(
                    fixture.binding, editActions: .move,
                    selection: Binding(get: { many }, set: { many = $0 })
                ) { $row in Text(row.name) })
            : AnyView(
                List(
                    fixture.binding, editActions: .delete,
                    selection: Binding(get: { single }, set: { single = $0 })
                ) { $row in Text(row.name) })
        fixture.render(view.frame(height: 8))
        fixture.render(view.frame(height: 8))
        guard let handler = fixture.handler else {
            Issue.record("the list registered focus")
            return
        }
        #expect((handler.onMove != nil) == multiple)
        #expect((handler.onDelete != nil) == !multiple)
        handler.focusedIndex = 1
        handler.toggleSelectionAtFocusedIndex()
        #expect(multiple ? many == [2] : single == 2)
    }

    @Test("The id: forms key the rows and the selection by the key path")
    func listKeyPathForms() {
        let fixture = Fixture([Row(id: 1, name: "a"), Row(id: 2, name: "b")])
        var single: String?
        let view = List(
            fixture.binding, id: \.name, editActions: .all,
            selection: Binding(get: { single }, set: { single = $0 })
        ) { $row in Text(row.name) }
        fixture.render(view.frame(height: 8))
        fixture.render(view.frame(height: 8))
        let handler = fixture.env.focusManager?.currentFocused as? ItemListHandler<String>
        #expect(handler?.onMove != nil && handler?.onDelete != nil)
        handler?.focusedIndex = 1
        handler?.toggleSelectionAtFocusedIndex()
        #expect(single == "b")
        var many: Set<String> = []
        _ = List(
            fixture.binding, id: \.name, editActions: .all,
            selection: Binding(get: { many }, set: { many = $0 })
        ) { $row in Text(row.name) }
        _ = List(fixture.binding, id: \.name, editActions: .all) { $row in Text(row.name) }
    }
}
