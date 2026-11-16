//  🖥️ TUI — A Terminal UI framework for Swift
//  TableOutlineRowsTwinTests.swift
//
//  What a table's outline answers about its rows — each row's indentation and
//  triangle, the row it sits under, the branches an Option-key opens or closes,
//  the traits a row modifier gave one row — read through the table: selection
//  by id, type select, a `.fit` column, the keys. The same answers before and
//  after the outline kept its rows by position rather than in dictionaries by
//  id; and the same from a tree of row content as from `Table(_:children:)`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITables
import TUITesting
@testable import TUIView

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
    Node(id: "last"),
]

/// The branches the user has closed; every other one is open. And the row
/// the table selects.
@Observable
@MainActor
private final class Model {
    var closed: Set<String> = []
    var selection: String?

    func isExpanded(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !self.closed.contains(id) },
            set: { open in if open { self.closed.remove(id) } else { self.closed.insert(id) } })
    }
}

/// A tree of any depth as row content, `bravo` refusing selection.
private struct Rows: TableRowContent {
    let nodes: [Node]
    let model: Model

    var tableRowBody: some TableRowContent<Node> {
        ForEach(nodes) { node in
            if let children = node.children {
                DisclosureTableRow(node, isExpanded: model.isExpanded(node.id)) {
                    Self(nodes: children, model: model)
                }
            } else {
                TableRow(node).selectionDisabled(node.id == "bravo")
            }
        }
    }
}

@MainActor
@Suite("A table's outline of row content answers by row")
struct TableOutlineRowsTwinTests {
    private func app(_ model: Model) -> TestApp {
        TestApp(width: 40, height: 14) {
            Table(of: Node.self, selection: Binding(get: { model.selection }, set: { model.selection = $0 })) {
                TableColumn("Name", value: \Node.id).width(.fit)
                TableColumn("Kind") { (node: Node) in Text(node.children == nil ? "leaf" : "branch") }
            } rows: {
                Rows(nodes: tree, model: model)
            }
            .selectionFollowsCursor()
        }
    }

    @Test("Down selects nested rows by id, and Left walks from a leaf to the row it sits under")
    func selectionAndParent() {
        let model = Model()
        let app = app(model)
        app.press(.tab)
        app.press(.down, times: 4)  // root, alpha, alpha-one, alpha-two, deep
        #expect(model.selection == "deep")
        app.press(.left)
        #expect(model.selection == "alpha-two", "the row deep sits under")
        app.press(.left)
        #expect(model.closed == ["alpha-two"], "Left on an open branch closes it")
        app.advance(by: .milliseconds(20))
        #expect(!app.screen.contains("deep"))
    }

    @Test("Type select finds a row by its words, not its indentation or triangle")
    func typeSelect() {
        let model = Model()
        let app = app(model)
        app.press(.tab)
        app.type("de")
        #expect(model.selection == "deep")
        app.advance(by: .seconds(2))
        app.type("other-o")
        #expect(model.selection == "other-one")
    }

    @Test("A .fit first column is as wide as its deepest row's indentation and words")
    func fitColumn() throws {
        let screen = app(Model()).screen
        let deep = try #require(screen.location(of: "deep"))
        let kind = try #require(screen.line(containing: "deep")?.range(of: "leaf"))
        let line = try #require(screen.line(containing: "deep"))
        #expect(line.distance(from: line.startIndex, to: kind.lowerBound) > deep.x + "deep".count)
        let root = try #require(screen.location(of: "root"))
        #expect(deep.x - root.x == 3 * _TableOutline<Node>.indentStep)
    }

    @Test("Option-Left closes every branch beneath a row, through each one's binding")
    func optionLeftClosesTheSubtree() {
        let model = Model()
        let app = app(model)
        app.press(.tab)
        app.press(.left, modifiers: .option)
        #expect(model.closed == ["root", "alpha", "alpha-two"])
        app.advance(by: .milliseconds(20))
        #expect(app.screen.contains("other-one"))
        #expect(!app.screen.contains("alpha"))
    }

    @Test("Each row's traits stay at its row: a row modifier on one row, after rows with none")
    func traitsByRow() throws {
        let model = Model()
        let outline = _TableOutline(
            tree: tableRows(of: Rows(nodes: tree, model: model)).branch,
            expansion: _TableOutlineExpansion(StateBox([])))
        let traits = try #require(outline.traits)
        #expect(traits.count == outline.values.count)
        let disabled = outline.values.indices.filter { traits[$0].selectionDisabled == true }
        #expect(disabled.map { outline.values[$0].id } == ["bravo"])
    }

    @Test("The same tree as row content and as Table(_:children:) gives the same answers by row")
    func rowContentAndRootsAgree() {
        let model = Model()
        let open: Set<AnyHashable> = ["root", "alpha", "alpha-two", "other"]
        let box = StateBox<Set<AnyHashable>>(open)
        let expansion = _TableOutlineExpansion<Node>(box)
        let rows: _TableOutline<Node> = _TableOutline(
            tree: tableRows(of: Rows(nodes: tree, model: model)).branch, expansion: expansion)
        let roots: _TableOutline<Node> = _TableOutlineCache<Node>().outline(
            of: _TableOutlineRoots(tree, children: \Node.children), expansion: expansion)
        #expect(rows.values.map(\Node.id) == roots.values.map(\Node.id))
        for node in rows.values {
            let id: String = node.id
            #expect(rows.prefix(for: id) == roots.prefix(for: id), Comment(rawValue: id))
            #expect(rows.triangleColumns(for: id) == roots.triangleColumns(for: id), Comment(rawValue: id))
            #expect(rows.parentRowID(of: AnyHashable(node.id)) == roots.parentRowID(of: AnyHashable(node.id)))
        }
        #expect(rows.parentRowID(of: AnyHashable("deep")) == AnyHashable("alpha-two"))
        #expect(rows.parentRowID(of: AnyHashable("root")) == nil)
        #expect(rows.triangleColumns(for: "last") == nil)
        #expect(rows.prefix(for: "nowhere") == rows.prefix(for: "last"), "a row not shown draws as a root leaf")
        #expect(roots.setExpanded(AnyHashable("other"), to: false, includingDescendants: false))
        #expect(!box.value.contains(AnyHashable("other")))
        #expect(!roots.setExpanded(AnyHashable("last"), to: true, includingDescendants: false), "a leaf opens nothing")
    }
}
