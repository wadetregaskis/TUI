//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableOutlineCacheTests.swift
//
//  A `Table(_:children:)` keeps its outline from pass to pass while its roots
//  and its open branches are the same (decisions B-FP2-5): a pass that changes
//  neither makes none, and one that changes either makes a new one that shows
//  the change.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTables
@testable import TUIkitTestSupport
@testable import TUIkitView

@MainActor
@Suite("A hierarchical table's outline, kept from pass to pass")
struct TableOutlineCacheTests {
    private struct File: Identifiable {
        let id: String
        var children: [Self]?
    }

    /// The same, its children computed: they can change under one array.
    private struct Computed: Identifiable {
        let id: String
        var children: [Self]? { id.hasPrefix("dir") ? [] : nil }
    }

    private final class Node: Identifiable {
        let id: String
        var children: [Node]?
        init(_ id: String, children: [Node]? = nil) {
            self.id = id
            self.children = children
        }
    }

    private static let files = [
        File(id: "dir", children: [File(id: "inner")]),
        File(id: "a"),
        File(id: "b"),
    ]

    @Test("The same roots and open branches give the same outline; new roots or a branch opened, a new one")
    func keptWhileUnchanged() {
        let cache = _TableOutlineCache<File>()
        let expansion = StateBox<Set<AnyHashable>>([])
        var rows = Self.files
        let first = cache.outline(of: _TableOutlineRoots(rows, children: \.children), expansion: expansion)
        #expect(cache.outline(of: _TableOutlineRoots(rows, children: \.children), expansion: expansion) === first)
        #expect(first.values.map(\.id) == ["dir", "a", "b"])

        expansion.value = [AnyHashable("dir")]
        let opened = cache.outline(of: _TableOutlineRoots(rows, children: \.children), expansion: expansion)
        #expect(opened !== first)
        #expect(opened.values.map(\.id) == ["dir", "inner", "a", "b"])
        #expect(opened.prefix(for: "inner") != opened.prefix(for: "a"), "the child a level in, the root leaf not")

        // Equal contents in another buffer: not known to be the same rows.
        rows[1] = File(id: "a")
        #expect(cache.outline(of: _TableOutlineRoots(rows, children: \.children), expansion: expansion) !== opened)
    }

    @Test("Children a computed property gives, or a class's, are made again every pass")
    func notKeptWhereTheyCanChangeUnseen() {
        let computed = _TableOutlineCache<Computed>()
        let computedRows = [Computed(id: "dir"), Computed(id: "a")]
        let expansion = StateBox<Set<AnyHashable>>([])
        let one = computed.outline(of: _TableOutlineRoots(computedRows, children: \.children), expansion: expansion)
        #expect(computed.outline(of: _TableOutlineRoots(computedRows, children: \.children), expansion: expansion) !== one)

        let classes = _TableOutlineCache<Node>()
        let nodes = [Node("dir", children: []), Node("a")]
        let two = classes.outline(of: _TableOutlineRoots(nodes, children: \.children), expansion: expansion)
        #expect(classes.outline(of: _TableOutlineRoots(nodes, children: \.children), expansion: expansion) !== two)
    }

    @Test("A root leaf draws as a leaf, a closed branch with its triangle, an open one's rows a level in")
    func drawn() {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(availableWidth: 30, availableHeight: 10, environment: environment, tuiContext: tui)
        var rows = Self.files
        func frame() -> [String] {
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            context.environment.focusManager?.beginRenderPass()
            let lines = renderToBuffer(
                Table(rows, children: \.children) { TableColumn("Name", value: \File.id) }, context: context
            ).lines.map(\.stripped)
            tui.stateStorage.endRenderPass()
            context.environment.focusManager?.endRenderPass()
            return lines
        }
        /// Where the word `id` starts on the line that has it as a word.
        func column(_ id: String, _ lines: [String]) -> Int? {
            for line in lines where line.split(separator: " ").contains(Substring(id)) {
                guard let range = line.range(of: " \(id)") else { continue }
                return line.distance(from: line.startIndex, to: range.lowerBound) + 1
            }
            return nil
        }
        var lines = frame()
        #expect(lines.contains { $0.contains("\(TerminalSymbols.disclosureCollapsed) dir") }, "\(lines)")
        #expect(column("a", lines) != nil && column("a", lines) == column("dir", lines), "a leaf's label lines up: \(lines)")
        _ = context.environment.focusManager?.dispatchKeyEvent(KeyEvent(key: .right))
        lines = frame()
        #expect(lines.contains { $0.contains("inner") }, "\(lines)")
        // New children under the open branch, in a new array: shown.
        rows[0].children = [File(id: "inner"), File(id: "added")]
        lines = frame()
        #expect(lines.contains { $0.contains("added") }, "\(lines)")
    }
}
