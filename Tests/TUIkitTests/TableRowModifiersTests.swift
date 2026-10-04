//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableRowModifiersTests.swift
//
//  Modifiers on table rows: `.selectionDisabled(_:)` refuses a row the
//  selection and draws it faint.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Table row modifiers")
struct TableRowModifiersTests {

    private struct Item: Identifiable, Equatable {
        let id: Int
        let name: String
        var children: [Self]?
    }

    private static let items = (0..<4).map { Item(id: $0, name: "item\($0)") }

    private func harness() -> (TUIContext, RenderContext) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        return (
            tui,
            RenderContext(
                availableWidth: 30, availableHeight: 12, environment: environment,
                tuiContext: tui)
        )
    }

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
        return buffer.lines
    }

    private func line(_ needle: String, _ lines: [String]) -> String {
        lines.first { $0.stripped.contains(needle) } ?? ""
    }

    private func isFaint(_ line: String) -> Bool {
        line.contains("\u{1B}[2m")
    }

    private func press(_ key: Key, _ context: RenderContext) {
        _ = context.environment.focusManager?.dispatchKeyEvent(KeyEvent(key: key))
    }

    private func table(selection: Box<Int?>, locked: @escaping (Item) -> Bool) -> some View {
        Table(of: Item.self, selection: selection.binding) {
            TableColumn("Name", value: \Item.name)
        } rows: {
            ForEach(Self.items) { item in
                TableRow(item).selectionDisabled(locked(item))
            }
        }
    }

    @Test("A row whose selection is disabled draws faint; its neighbours do not")
    func drawsFaint() {
        let (tui, context) = harness()
        let lines = frame(
            table(selection: Box(nil)) { $0.id == 2 }, tui: tui, context: context)
        #expect(isFaint(line("item2", lines)), "\(lines)")
        #expect(!isFaint(line("item1", lines)))
        #expect(!isFaint(line("item3", lines)))
    }

    @Test("A click on a row whose selection is disabled selects nothing")
    func clickRefused() throws {
        let (tui, context) = harness()
        let selection = Box<Int?>(nil)
        let view = table(selection: selection) { $0.id == 2 }
        let lines = frame(view, tui: tui, context: context).map(\.stripped)
        let row = try #require(lines.firstIndex { $0.contains("item2") })
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 6, y: row))
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 6, y: row))
        #expect(selection.value == nil)
        let other = try #require(lines.firstIndex { $0.contains("item3") })
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 6, y: other))
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 6, y: other))
        #expect(selection.value == 3, "the control: an ordinary row selects")
    }

    @Test("Down steps over a row whose selection is disabled")
    func cursorStepsOver() {
        let (tui, context) = harness()
        let selection = Box<Int?>(nil)
        let view = table(selection: selection) { $0.id == 1 }
        frame(view, tui: tui, context: context)
        press(.down, context)
        frame(view, tui: tui, context: context)
        press(.space, context)
        #expect(selection.value == 2)
    }

    @Test("The modifier nearest the row wins")
    func nearestWins() {
        let (tui, context) = harness()
        let view = Table(of: Item.self) {
            TableColumn("Name", value: \Item.name)
        } rows: {
            ForEach(Self.items) { item in
                TableRow(item).selectionDisabled(item.id != 1)
            }
            .selectionDisabled(false)
        }
        let lines = frame(view, tui: tui, context: context)
        #expect(isFaint(line("item2", lines)), "\(lines)")
        #expect(!isFaint(line("item1", lines)))
    }

    @Test("A modifier on a branch's content reaches the rows beneath it")
    func reachesATreesRows() {
        let (tui, context) = harness()
        let tree = [Item(id: 0, name: "top", children: [Item(id: 1, name: "inner")])]
        let view = Table(of: Item.self) {
            TableColumn("Name", value: \Item.name)
        } rows: {
            OutlineGroup(tree, children: \.children).selectionDisabled()
        }
        frame(view, tui: tui, context: context)
        press(.right, context)
        let lines = frame(view, tui: tui, context: context)
        #expect(isFaint(line("inner", lines)), "\(lines)")
    }

    /// The row memo keeps a row by its cells and its selection; a row that
    /// comes to refuse selection changes neither.
    @Test("A kept row redraws faint when its selection becomes disabled")
    func memoSeesTheDim() {
        let (tui, context) = harness()
        let locked = Box(false)
        let selection = Box<Int?>(nil)
        let view = { self.table(selection: selection) { $0.id == 2 && locked.value } }
        for _ in 0..<4 { frame(view(), tui: tui, context: context) }
        locked.value = true
        let lines = frame(view(), tui: tui, context: context)
        #expect(isFaint(line("item2", lines)), "\(lines)")
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
