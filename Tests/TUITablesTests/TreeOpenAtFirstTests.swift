//  🖥️ TUI — A Terminal UI framework for Swift
//  TreeOpenAtFirstTests.swift
//
//  A tree table whose branches start open, the way SwiftUI offers one: a
//  custom `TableRowContent` that recurses over a tree of any depth, each
//  branch a `DisclosureTableRow(_:isExpanded:)` whose binding the app keeps.
//  The first app built on TUI (a `top`) asked for its process tree to start
//  open and found `Table(_:children:)` always starts closed, as SwiftUI's does
//  (measured: `Tools/SwiftUIProbes/Table keys, type select and expansion (APPFB)`).
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUIApp
@testable import TUICore
@testable import TUIFoundation
import TUITables
import TUITesting

private struct Node: Identifiable, Hashable, Sendable {
    let id: String
    var children: [Self]?
}

private let tree = [
    Node(id: "root", children: [
        Node(id: "alpha", children: [Node(id: "alpha-one"), Node(id: "alpha-two", children: [Node(id: "deep")])]),
        Node(id: "bravo"),
    ]),
    Node(id: "other", children: [Node(id: "other-one")]),
]

/// The branches the user has closed; every other one is open.
@Observable
@MainActor
private final class Closed {
    var ids: Set<String> = []

    func isExpanded(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !self.ids.contains(id) },
            set: { open in if open { self.ids.remove(id) } else { self.ids.insert(id) } })
    }
}

/// A tree of any depth: a custom row content naming itself in its own body.
private struct OpenRows: TableRowContent {
    let nodes: [Node]
    let closed: Closed

    var tableRowBody: some TableRowContent<Node> {
        ForEach(nodes) { node in
            if let children = node.children {
                DisclosureTableRow(node, isExpanded: closed.isExpanded(node.id)) {
                    Self(nodes: children, closed: closed)
                }
            } else {
                TableRow(node)
            }
        }
    }
}

@MainActor
@Suite("A tree table can start with its branches open")
struct TreeOpenAtFirstTests {
    private func app(_ closed: Closed) -> TestApp {
        TestApp(width: 40, height: 14) {
            Table(of: Node.self) {
                TableColumn("Name", value: \Node.id)
            } rows: {
                OpenRows(nodes: tree, closed: closed)
            }
        }
    }

    @Test("Every row of every depth shows at first")
    func everyRowShows() {
        let screen = app(Closed()).screen
        for name in ["root", "alpha", "alpha-one", "alpha-two", "deep", "bravo", "other", "other-one"] {
            #expect(screen.contains(name), "\(name) is missing:\n\(screen)")
        }
    }

    @Test("Left on an open branch closes it, through the app's binding")
    func leftCloses() {
        let closed = Closed()
        let app = app(closed)
        app.press(.tab)
        app.press(.down)  // root → alpha
        app.press(.left)
        #expect(closed.ids == ["alpha"])
        app.advance(by: .milliseconds(20))
        #expect(!app.screen.contains("alpha-one"), "\(app.screen)")
        #expect(app.screen.contains("bravo"))
    }
}
