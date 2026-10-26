//  🖥️ TUI — A Terminal UI framework for Swift
//  ListRequiredSelectionTests.swift
//
//  `List(selection: Binding<SelectionValue>)`, SwiftUI's single selection that
//  cannot be emptied (the semantic audit's item 76): which form a binding
//  picks, and that activating the selected row again keeps it selected.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIFoundation
@testable import TUILists
@testable import TUITestSupport

@MainActor
@Suite("List with a selection that cannot be emptied")
struct ListRequiredSelectionTests {
    private struct Item: Identifiable {
        let id: Int
    }

    /// The selection type a list was made with: `Int` for `Binding<Int?>` on
    /// the optional form, `Int?` had it landed on the required one.
    private func selectionType<S, C, F>(_: List<S, C, F>) -> S.Type { S.self }

    /// SwiftUI declares its required forms `@_disfavoredOverload`, so an
    /// optional binding keeps the optional form and a set keeps the
    /// multi-selection form — measured against SwiftUI's own overloads.
    @Test("An optional or set binding keeps its own form; only a plain value takes the required one")
    func overloadRanking() {
        let items = [Item(id: 1), Item(id: 2)]
        var optional: Int? = 1
        var several: Set<Int> = [1]
        var required = 1
        let optionalBinding = Binding(get: { optional }, set: { optional = $0 })
        let severalBinding = Binding(get: { several }, set: { several = $0 })
        let requiredBinding = Binding(get: { required }, set: { required = $0 })

        #expect(selectionType(List(items, selection: optionalBinding) { Text("\($0.id)") }) == Int.self)
        #expect(selectionType(List(items, selection: severalBinding) { Text("\($0.id)") }) == Int.self)
        #expect(selectionType(List(items, selection: requiredBinding) { Text("\($0.id)") }) == Int.self)
        #expect(selectionType(List(selection: optionalBinding) { Text("a").tag(1) }) == Int.self)
        #expect(selectionType(List(selection: severalBinding) { Text("a").tag(1) }) == Int.self)
        #expect(selectionType(List(selection: requiredBinding) { Text("a").tag(1) }) == Int.self)
        #expect(selectionType(List(0..<2, selection: optionalBinding) { Text("\($0)") }) == Int.self)
        #expect(selectionType(List(0..<2, selection: requiredBinding) { Text("\($0)") }) == Int.self)
        #expect(selectionType(List(items, id: \.id, selection: requiredBinding) { Text("\($0.id)") }) == Int.self)
    }

    /// TUI's single selection clears when the selected row is activated
    /// again; with a required selection that `nil` is dropped.
    @Test("Activating the selected row again keeps it selected; another row moves the selection")
    func cannotBeEmptied() {
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        env.applyRuntimeServices(from: tui)
        var selection = 1
        let view = List([Item(id: 0), Item(id: 1), Item(id: 2)], selection: Binding(get: { selection }, set: { selection = $0 })) {
            Text("item \($0.id)")
        }
        .frame(height: 8)
        func render() {
            tui.stateStorage.beginRenderPass()
            env.focusManager?.beginRenderPass()
            _ = renderToBuffer(view, context: RenderContext(availableWidth: 30, availableHeight: 10, environment: env, tuiContext: tui))
            env.focusManager?.endRenderPass()
            tui.stateStorage.endRenderPass()
        }
        render()
        render()
        guard let handler = env.focusManager?.currentFocused as? ItemListHandler<Int> else {
            Issue.record("the list took no focus")
            return
        }
        handler.focusedIndex = 1
        _ = handler.handleKeyEvent(KeyEvent(key: .space))
        #expect(selection == 1, "Space on the selected row: \(selection)")
        handler.focusedIndex = 2
        _ = handler.handleKeyEvent(KeyEvent(key: .space))
        #expect(selection == 2, "Space on another row: \(selection)")
    }
}
