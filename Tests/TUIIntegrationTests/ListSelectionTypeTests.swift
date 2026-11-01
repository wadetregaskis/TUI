//  🖥️ TUI — A Terminal UI framework for Swift
//  ListSelectionTypeTests.swift
//
//  A `List(data, selection:)` whose selection is not the rows' id type, as
//  SwiftUI declares it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
@testable import TUIAppTestSupport

import TUI
@testable import TUIApp
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport
@testable import TUIView

private struct Node: Identifiable, Hashable, Sendable {
    var id: String
    var kids: [Self]?
}

/// Each initializer SwiftUI declares without tying its selection to its rows' id
/// type, with a selection of another type. That these compile is the assertion
/// for most; the first few also run.
@MainActor
@Suite("List(data, selection:) takes a selection of any type, as SwiftUI's does")
struct ListSelectionTypeTests {
    private struct Page: App {
        let content: AnyView
        init() { self.init(content: AnyView(EmptyView())) }
        init(content: AnyView) { self.content = content }
        var body: some Scene { WindowGroup { content } }
    }

    @Test("A tag names the row when the id is another type")
    func dataFormWithTag() {
        var selected: Int?
        let binding = Binding(get: { selected }, set: { selected = $0 })
        let app = TestApp(
            Page(content: AnyView(
                List(["a", "b"], id: \.self, selection: binding) { Text($0).tag($0.count + 41) }
            )), width: 20, height: 6)
        app.frame(atNanos: 16_666_667)
        app.send(KeyEvent(key: .enter))
        app.frame(atNanos: 33_333_334)
        #expect(selected == 42)
    }

    @Test("Without a tag, a row whose id is another type draws and cannot be selected")
    func dataFormWithoutTag() {
        var selected: Node?
        let binding = Binding(get: { selected }, set: { selected = $0 })
        let app = TestApp(
            Page(content: AnyView(
                List([Node(id: "only")], selection: binding) { Text($0.id) }
            )), width: 20, height: 6)
        app.frame(atNanos: 16_666_667)
        app.send(KeyEvent(key: .enter))
        app.frame(atNanos: 33_333_334)
        #expect(selected == nil)
        #expect(app.screen.contains("only"))
    }

    @Test("A range's rows take a selection of any type")
    func rangeForm() {
        var selected: String?
        let binding = Binding(get: { selected }, set: { selected = $0 })
        let app = TestApp(
            Page(content: AnyView(
                List(0..<2, selection: binding) { Text("row \($0)").tag("\($0)") }
            )), width: 20, height: 6)
        app.frame(atNanos: 16_666_667)
        app.send(KeyEvent(key: .enter))
        app.frame(atNanos: 33_333_334)
        #expect(selected == "0")
    }

    @Test("Every form compiles with a selection unrelated to the rows' ids")
    func everyFormCompiles() {
        let nodes = [Node(id: "a", kids: nil)]
        var optional: Int?
        var set = Set<Int>()
        var required = 0
        var data = nodes
        let optionalBinding = Binding(get: { optional }, set: { optional = $0 })
        let setBinding = Binding(get: { set }, set: { set = $0 })
        let requiredBinding = Binding(get: { required }, set: { required = $0 })
        let dataBinding = Binding(get: { data }, set: { data = $0 })

        _ = List(nodes, selection: optionalBinding) { Text($0.id) }
        _ = List(nodes, selection: setBinding) { Text($0.id) }
        _ = List(nodes, selection: requiredBinding) { Text($0.id) }
        _ = List(nodes, id: \.id, selection: optionalBinding) { Text($0.id) }
        _ = List(nodes, id: \.id, selection: setBinding) { Text($0.id) }
        _ = List(nodes, id: \.id, selection: requiredBinding) { Text($0.id) }
        _ = List(0..<2, selection: optionalBinding) { Text("\($0)") }
        _ = List(0..<2, selection: setBinding) { Text("\($0)") }
        _ = List(0..<2, selection: requiredBinding) { Text("\($0)") }

        _ = List(nodes, children: \.kids, selection: optionalBinding) { Text($0.id) }
        _ = List(nodes, children: \.kids, selection: setBinding) { Text($0.id) }
        _ = List(nodes, children: \.kids, selection: requiredBinding) { Text($0.id) }
        _ = List(nodes, id: \.id, children: \.kids, selection: optionalBinding) { Text($0.id) }
        _ = List(nodes, id: \.id, children: \.kids, selection: setBinding) { Text($0.id) }
        _ = List(nodes, id: \.id, children: \.kids, selection: requiredBinding) { Text($0.id) }

        _ = List(dataBinding, children: \.kids, selection: optionalBinding) { Text($0.wrappedValue.id) }
        _ = List(dataBinding, children: \.kids, selection: setBinding) { Text($0.wrappedValue.id) }
        _ = List(dataBinding, children: \.kids, selection: requiredBinding) { Text($0.wrappedValue.id) }
        _ = List(dataBinding, id: \.id, children: \.kids, selection: optionalBinding) { Text($0.wrappedValue.id) }
        _ = List(dataBinding, id: \.id, children: \.kids, selection: setBinding) { Text($0.wrappedValue.id) }
        _ = List(dataBinding, id: \.id, children: \.kids, selection: requiredBinding) { Text($0.wrappedValue.id) }

        _ = List(dataBinding, editActions: .all, selection: optionalBinding) { Text($0.wrappedValue.id) }
        _ = List(dataBinding, editActions: .all, selection: setBinding) { Text($0.wrappedValue.id) }
        _ = List(dataBinding, editActions: .all, selection: requiredBinding) { Text($0.wrappedValue.id) }
        _ = List(dataBinding, id: \.id, editActions: .all, selection: optionalBinding) { Text($0.wrappedValue.id) }
        _ = List(dataBinding, id: \.id, editActions: .all, selection: setBinding) { Text($0.wrappedValue.id) }
        _ = List(dataBinding, id: \.id, editActions: .all, selection: requiredBinding) { Text($0.wrappedValue.id) }
    }
}
