//  🖥️ TUI — A Terminal UI framework for Swift
//  OutlineBindingTreeTests.swift
//
//  `OutlineGroup` and `List(_:children:)` over a binding to a tree, as SwiftUI
//  declares them: each row is handed a binding to its node, and a write
//  through it reaches the node wherever it is in the tree.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIFoundation
import TUILists
@testable import TUITestSupport

@MainActor
@Suite("An outline over a binding to a tree")
struct OutlineBindingTreeTests {
    private struct Node: Identifiable {
        let id: Int
        var name: String
        var children: [Self]?
    }

    /// Mutable, so the bindings have somewhere to write: `Sources` holds
    /// `TUI`, which holds `Views`; `README` is a leaf.
    private final class Tree {
        var roots = [
            Node(
                id: 1, name: "Sources",
                children: [Node(id: 2, name: "TUI", children: [Node(id: 3, name: "Views", children: nil)])]),
            Node(id: 4, name: "README", children: nil),
        ]
        var binding: Binding<[Node]> { Binding(get: { self.roots }, set: { self.roots = $0 }) }
    }

    /// The bindings the rows were handed, by node id, as their labels are built.
    @MainActor
    private final class Handed {
        var bindings: [Int: Binding<Node>] = [:]

        func label(_ node: Binding<Node>) -> Text {
            bindings[node.wrappedValue.id] = node
            return Text(verbatim: node.wrappedValue.name)
        }
    }

    private func harness() -> (TUIContext, RenderContext) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        return (tui, RenderContext(availableWidth: 40, availableHeight: 12, environment: environment, tuiContext: tui))
    }

    @discardableResult
    private func frame(_ view: some View, tui: TUIContext, context: RenderContext) -> [String] {
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        context.environment.focusManager?.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tui.stateStorage.endRenderPass()
        context.environment.focusManager?.endRenderPass()
        return buffer.lines.map(\.stripped)
    }

    @Test("Each row is handed a binding to its node, and a write reaches the node in the tree")
    func rowsWriteThroughToTheirNodes() throws {
        let tree = Tree()
        let handed = Handed()
        let view = VStack(alignment: .leading, spacing: 0) {
            OutlineGroup(tree.binding, children: \.children) { handed.label($0) }
        }
        let (tui, context) = harness()
        frame(view, tui: tui, context: context)
        let focus = try #require(context.environment.focusManager)
        #expect(focus.dispatchKeyEvent(KeyEvent(key: .right)), "Right opens the first branch")
        let opened = frame(view, tui: tui, context: context)
        #expect(opened.contains { $0.contains("TUI") }, "\(opened)")

        let child = try #require(handed.bindings[2], "the opened branch's child was built")
        child.wrappedValue.name = "Kit"
        #expect(tree.roots[0].children?[0].name == "Kit", "the write reached the child in the tree")
        let redrawn = frame(view, tui: tui, context: context)
        #expect(redrawn.contains { $0.contains("Kit") && !$0.contains("TUI") }, "\(redrawn)")
    }

    @Test("The root form outlines the one element a binding holds")
    func rootForm() {
        let tree = Tree()
        let root = Binding(get: { tree.roots[0] }, set: { tree.roots[0] = $0 })
        let view = VStack(alignment: .leading, spacing: 0) {
            OutlineGroup(root, id: \.id, children: \.children) { Text(verbatim: $0.wrappedValue.name) }
        }
        let (tui, context) = harness()
        let drawn = frame(view, tui: tui, context: context)
        #expect(drawn.contains { $0.contains("Sources") }, "\(drawn)")
        #expect(!drawn.contains { $0.contains("README") }, "only the root's tree: \(drawn)")
    }

    @Test("A List over a binding to a tree selects its nodes by id")
    func listSelectsNodes() throws {
        let tree = Tree()
        var selection: Int?
        let view = List(
            tree.binding, children: \.children, selection: Binding(get: { selection }, set: { selection = $0 })
        ) { node in
            Text(verbatim: node.wrappedValue.name)
        }
        .frame(height: 8)
        let (tui, context) = harness()
        frame(view, tui: tui, context: context)
        frame(view, tui: tui, context: context)
        let focus = try #require(context.environment.focusManager)
        #expect(focus.dispatchKeyEvent(KeyEvent(key: .down)))
        frame(view, tui: tui, context: context)
        // Space selects; Return would activate (disclose) an outline's row.
        #expect(focus.dispatchKeyEvent(KeyEvent(key: .space)))
        #expect(selection == 4, "README, the second root")
    }
}
