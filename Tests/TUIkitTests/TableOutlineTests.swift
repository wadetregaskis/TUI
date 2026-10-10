//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableOutlineTests.swift
//
//  Hierarchical tables: `Table(_:children:)`, `OutlineGroup` and
//  `DisclosureTableRow` rows — the tree drawn in the first column, and the
//  keys and clicks that open and close it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("Hierarchical tables")
struct TableOutlineTests {

    private struct File: Identifiable, Equatable {
        let id: String
        var children: [Self]?
    }

    private static let tree = [
        File(
            id: "Sources",
            children: [
                File(id: "TUIkit", children: [File(id: "Views")]),
                File(id: "Core"),
            ]),
        File(id: "README"),
    ]

    private func harness() -> (TUIContext, RenderContext) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        return (
            tui,
            RenderContext(
                availableWidth: 40, availableHeight: 14, environment: environment,
                tuiContext: tui)
        )
    }

    /// One whole frame, the way the run loop does it.
    @discardableResult
    private func frame(_ view: some View, tui: TUIContext, context: RenderContext) -> [String] {
        tui.mouseEventDispatcher.beginRenderPass()
        tui.keyEventDispatcher.clearHandlers()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        context.environment.focusManager?.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        let composited = buffer.compositingOverlays(
            maxWidth: context.availableWidth, maxHeight: context.availableHeight,
            palette: context.environment.palette)
        tui.mouseEventDispatcher.setRegions(composited.hitTestRegions)
        tui.stateStorage.endRenderPass()
        context.environment.focusManager?.endRenderPass()
        return buffer.lines.map(\.stripped)
    }

    private func column(of needle: String, in lines: [String]) -> Int? {
        for line in lines {
            if let range = line.range(of: needle) {
                return line.distance(from: line.startIndex, to: range.lowerBound)
            }
        }
        return nil
    }

    private func shows(_ needle: String, _ lines: [String]) -> Bool {
        lines.contains { $0.contains(needle) }
    }

    private func table() -> some View {
        Table(Self.tree, children: \.children) {
            TableColumn("Name", value: \File.id)
        }
    }

    private func press(_ key: Key, alt: Bool = false, _ context: RenderContext) {
        _ = context.environment.focusManager?.dispatchKeyEvent(KeyEvent(key: key, alt: alt))
    }

    // MARK: - Drawing

    @Test("A closed tree shows its roots, a triangle on each branch, and the labels in one column")
    func closedTree() throws {
        let (tui, context) = harness()
        let lines = frame(table(), tui: tui, context: context)
        #expect(shows("\(TerminalSymbols.disclosureCollapsed) Sources", lines), "\(lines)")
        #expect(!shows("TUIkit", lines), "a closed branch hides its rows: \(lines)")
        let label = try #require(column(of: "Sources", in: lines))
        #expect(column(of: "README", in: lines) == label, "a leaf's label lines up with a branch's")
    }

    @Test("Opening a branch shows its rows beneath it, a level further in")
    func openedBranchIndents() throws {
        let (tui, context) = harness()
        let view = table()
        frame(view, tui: tui, context: context)
        press(.right, context)
        let lines = frame(view, tui: tui, context: context)
        #expect(shows("\(TerminalSymbols.disclosureExpanded) Sources", lines), "\(lines)")
        let parent = try #require(column(of: "Sources", in: lines))
        #expect(column(of: "TUIkit", in: lines) == parent + DisclosureMetrics.triangleColumnWidth)
        #expect(column(of: "Core", in: lines) == parent + DisclosureMetrics.triangleColumnWidth)
        let order = ["Sources", "TUIkit", "Core", "README"].compactMap { name in
            lines.firstIndex { $0.contains(name) }
        }
        #expect(order == order.sorted() && order.count == 4, "children come between: \(lines)")
        #expect(!shows("Views", lines), "only one level opened: \(lines)")
    }

    @Test("Left closes the branch Right opened")
    func leftCloses() {
        let (tui, context) = harness()
        let view = table()
        frame(view, tui: tui, context: context)
        press(.right, context)
        frame(view, tui: tui, context: context)
        press(.left, context)
        let lines = frame(view, tui: tui, context: context)
        #expect(!shows("TUIkit", lines), "\(lines)")
        #expect(shows("\(TerminalSymbols.disclosureCollapsed) Sources", lines), "\(lines)")
    }

    @Test("Option-Right opens the whole subtree")
    func optionRightOpensEverything() {
        let (tui, context) = harness()
        let view = table()
        frame(view, tui: tui, context: context)
        press(.right, alt: true, context)
        let lines = frame(view, tui: tui, context: context)
        #expect(shows("Views", lines), "two levels down: \(lines)")
    }

    @Test("Left on a row with nothing to close moves to the row it sits under")
    func leftWalksOut() {
        let (tui, context) = harness()
        let view = Table(Self.tree, children: \.children, selection: .constant(String?.none)) {
            TableColumn("Name", value: \File.id)
        }
        frame(view, tui: tui, context: context)
        press(.right, context)
        frame(view, tui: tui, context: context)
        press(.down, context)
        frame(view, tui: tui, context: context)
        press(.down, context)  // on "Core", a leaf
        frame(view, tui: tui, context: context)
        press(.left, context)  // out to "Sources"
        frame(view, tui: tui, context: context)
        press(.left, context)  // and that closes it
        let lines = frame(view, tui: tui, context: context)
        #expect(!shows("Core", lines), "\(lines)")
    }

    /// After frames that let the table keep its rows, the table's own
    /// expansion still turns the triangle.
    @Test("A kept row redraws its triangle when its branch opens")
    func memoSeesTheTriangle() {
        let (tui, context) = harness()
        let view = table()
        for _ in 0..<4 { frame(view, tui: tui, context: context) }
        press(.right, context)
        let lines = frame(view, tui: tui, context: context)
        #expect(shows("\(TerminalSymbols.disclosureExpanded) Sources", lines), "\(lines)")
    }

    @Test("A view cell in the first column lays out after the triangle")
    func viewCell() {
        let (tui, context) = harness()
        let view = Table(Self.tree, children: \.children) {
            TableColumn("Name") { (file: File) in
                HStack(spacing: 1) {
                    Text(verbatim: file.id)
                    Text(verbatim: "!")
                }
            }
        }
        let lines = frame(view, tui: tui, context: context)
        #expect(shows("\(TerminalSymbols.disclosureCollapsed) Sources !", lines), "\(lines)")
    }

    // MARK: - The mouse

    private func click(_ x: Int, _ y: Int, _ tui: TUIContext) {
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))
    }

    @Test("A click on a triangle opens its branch and selects nothing")
    func triangleClick() throws {
        let (tui, context) = harness()
        let selection = Box<String?>(nil)
        let view = Table(Self.tree, children: \.children, selection: selection.binding) {
            TableColumn("Name", value: \File.id)
        }
        let first = frame(view, tui: tui, context: context)
        let row = try #require(first.firstIndex { $0.contains("Sources") })
        let triangle = try #require(column(of: TerminalSymbols.disclosureCollapsed, in: first))
        click(triangle, row, tui)
        let lines = frame(view, tui: tui, context: context)
        #expect(shows("TUIkit", lines), "\(lines)")
        #expect(selection.value == nil)
    }

    @Test("A click on a branch's label selects it and leaves it closed")
    func labelClick() throws {
        let (tui, context) = harness()
        let selection = Box<String?>(nil)
        let view = Table(Self.tree, children: \.children, selection: selection.binding) {
            TableColumn("Name", value: \File.id)
        }
        let first = frame(view, tui: tui, context: context)
        let row = try #require(first.firstIndex { $0.contains("Sources") })
        let label = try #require(column(of: "Sources", in: first))
        click(label + 2, row, tui)
        let lines = frame(view, tui: tui, context: context)
        #expect(!shows("TUIkit", lines), "\(lines)")
        #expect(selection.value == "Sources")
    }

    // MARK: - Row content

    @Test("An OutlineGroup among a table's rows draws its tree")
    func outlineGroupRows() {
        let (tui, context) = harness()
        let view = Table(of: File.self) {
            TableColumn("Name", value: \File.id)
        } rows: {
            TableRow(File(id: "Top"))
            OutlineGroup(Self.tree, children: \.children)
        }
        frame(view, tui: tui, context: context)
        press(.down, context)
        frame(view, tui: tui, context: context)
        press(.right, context)
        let lines = frame(view, tui: tui, context: context)
        #expect(shows("Top", lines))
        #expect(shows("\(TerminalSymbols.disclosureExpanded) Sources", lines), "\(lines)")
        #expect(shows("TUIkit", lines), "\(lines)")
    }

    @Test("A DisclosureTableRow follows its binding, and Right writes it")
    func disclosureRowBinding() {
        let (tui, context) = harness()
        let isExpanded = Box(false)
        let view = Table(of: File.self) {
            TableColumn("Name", value: \File.id)
        } rows: {
            DisclosureTableRow(File(id: "Folder"), isExpanded: isExpanded.binding) {
                TableRow(File(id: "Inside"))
            }
            TableRow(File(id: "Loose"))
        }
        var lines = frame(view, tui: tui, context: context)
        #expect(!shows("Inside", lines), "\(lines)")
        press(.right, context)
        #expect(isExpanded.value)
        lines = frame(view, tui: tui, context: context)
        #expect(shows("Inside", lines), "\(lines)")
        isExpanded.value = false
        lines = frame(view, tui: tui, context: context)
        #expect(!shows("Inside", lines), "the binding closes it too: \(lines)")
    }

    /// The row memo keeps a row whose value is unchanged; a triangle turned by
    /// a binding the table does not own changes no value and writes no state
    /// of the table's, so only the cells can tell.
    @Test("A kept row redraws its triangle when its binding turns it")
    func memoSeesABindingsTriangle() {
        let (tui, context) = harness()
        let isExpanded = Box(false)
        let view = Table(of: File.self) {
            TableColumn("Name", value: \File.id)
        } rows: {
            TableRow(File(id: "Loose"))
            DisclosureTableRow(File(id: "Folder"), isExpanded: isExpanded.binding) {
                TableRow(File(id: "Inside"))
            }
        }
        for _ in 0..<4 { frame(view, tui: tui, context: context) }
        isExpanded.value = true
        let lines = frame(view, tui: tui, context: context)
        #expect(shows("\(TerminalSymbols.disclosureExpanded) Folder", lines), "\(lines)")
    }
}

/// A value a test's binding reads and writes.
@MainActor
private final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
    var binding: Binding<Value> {
        Binding(get: { self.value }, set: { self.value = $0 })
    }
}
