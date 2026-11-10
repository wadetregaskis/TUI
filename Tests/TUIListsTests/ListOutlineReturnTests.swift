//  🖥️ TUI — A Terminal UI framework for Swift
//  ListOutlineReturnTests.swift
//
//  Return in a hierarchical `List` opens or closes a branch, and chooses a
//  leaf as it does a flat list's row. The leaf's Return did nothing: the tree's
//  disclosure stood in for the list's action, and a leaf has nothing to
//  disclose.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUICore
@testable import TUIFoundation
import TUILists
import TUITesting

private struct Node: Identifiable, Hashable, Sendable {
    let id: String
    var children: [Self]?
}

private let tree = [
    Node(id: "Sources", children: [Node(id: "Views", children: nil)]),
    Node(id: "README", children: nil),
]

@MainActor
private final class Chosen {
    var one: String?
    var many: Set<String> = []
}

@MainActor
@Suite("Return in a hierarchical List")
struct ListOutlineReturnTests {
    @Test("Return opens a branch and selects a leaf")
    func returnOnALeafSelectsIt() {
        let chosen = Chosen()
        let app = TestApp(width: 30, height: 8) {
            List(tree, children: \.children, selection: Binding(get: { chosen.one }, set: { chosen.one = $0 })) {
                Text($0.id)
            }
        }
        app.press(.tab)
        app.press(.enter)
        #expect(app.screen.contains("Views"), "Return opens the branch")
        #expect(chosen.one == nil, "and selects nothing")
        app.press(.down)
        app.press(.enter)
        #expect(chosen.one == "Views", "Return on a leaf selects it")
        app.press(.down)
        app.press(.enter)
        #expect(chosen.one == "README")
    }

    @Test("Return toggles a leaf in a multi-selection, as Space does")
    func returnOnALeafTogglesMultiSelection() {
        let chosen = Chosen()
        let app = TestApp(width: 30, height: 8) {
            List(tree, children: \.children, selection: Binding(get: { chosen.many }, set: { chosen.many = $0 })) {
                Text($0.id)
            }
        }
        app.press(.tab)
        app.press(.down)
        app.press(.enter)
        #expect(chosen.many == ["README"])
        app.press(.enter)
        #expect(chosen.many.isEmpty)
    }
}
