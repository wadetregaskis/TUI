//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableStyleTests.swift
//
//  `.tableStyle(_:)`: a bordered table, an inset one without the border, and
//  a custom style drawing through its body.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation

@MainActor
@Suite("Table styles")
struct TableStyleTests {

    private struct Row: Identifiable, Equatable {
        let id: Int
        let name: String
    }

    private static let rows = (0..<3).map { Row(id: $0, name: "row\($0)") }

    private func harness(height: Int = 10) -> (TUIContext, RenderContext) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        return (
            tui,
            RenderContext(
                availableWidth: 30, availableHeight: height, environment: environment,
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
        return buffer.lines.map(\.stripped)
    }

    private func table(selection: Box<Int?> = Box(nil)) -> Table<Row> {
        Table(Self.rows, selection: selection.binding) {
            TableColumn("Name", value: \Row.name)
        }
    }

    private func hasBorder(_ lines: [String]) -> Bool {
        lines.contains { $0.contains("╭") || $0.contains("│") || $0.contains("╰") }
    }

    @Test("A table is bordered by default, and .bordered draws the same")
    func borderedByDefault() {
        let (tui, context) = harness()
        let plain = frame(table(), tui: tui, context: context)
        #expect(hasBorder(plain), "\(plain)")
        let (tui2, context2) = harness()
        let bordered = frame(table().tableStyle(.bordered), tui: tui2, context: context2)
        #expect(bordered == plain)
        let (tui3, context3) = harness()
        let automatic = frame(table().tableStyle(.automatic), tui: tui3, context: context3)
        #expect(automatic == plain)
    }

    @Test(".inset draws the header and rows without the border, a cell in from the edge")
    func insetHasNoBorder() {
        let (tui, context) = harness()
        let lines = frame(table().tableStyle(.inset), tui: tui, context: context)
        #expect(!hasBorder(lines), "\(lines)")
        #expect(lines.first?.hasPrefix(" ") == true && lines.first?.contains("Name") == true, "\(lines)")
        #expect(lines.count >= 4 && lines[1].contains("row0"), "the rows follow the header: \(lines)")
    }

    @Test("An inset table measures as its header and rows, with no border lines")
    func insetMeasures() {
        let (tui, context) = harness(height: 20)
        let lines = frame(
            VStack(alignment: .leading, spacing: 0) {
                table().tableStyle(.inset)
                Text(verbatim: "after")
            },
            tui: tui, context: context)
        let after = lines.firstIndex { $0.contains("after") }
        #expect(after == 4, "header + three rows, then the text: \(lines)")
    }

    @Test("A click on an inset table's row selects that row")
    func insetClickSelects() throws {
        let (tui, context) = harness()
        let selection = Box<Int?>(nil)
        let view = table(selection: selection).tableStyle(.inset)
        let lines = frame(view, tui: tui, context: context)
        let row = try #require(lines.firstIndex { $0.contains("row2") })
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 5, y: row))
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 5, y: row))
        #expect(selection.value == 2)
    }

    @Test("A click on an inset table's header sorts by that column")
    func insetHeaderSorts() throws {
        let (tui, context) = harness()
        let order = Box([KeyPathComparator(\Row.name)])
        let view = Table(Self.rows, sortOrder: order.binding) {
            TableColumn("Name", value: \Row.name)
        }
        .tableStyle(.inset)
        let lines = frame(view, tui: tui, context: context)
        let header = try #require(lines.firstIndex { $0.contains("Name") })
        #expect(header == 0)
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: header))
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: header))
        #expect(order.value.first?.order == .reverse)
    }

    private struct Padded: TableStyle {
        func makeBody(configuration: Configuration) -> some View {
            InsetTableStyle().makeBody(configuration: configuration)
                .padding(.leading, 3)
        }
    }

    private struct Replaced: TableStyle {
        func makeBody(configuration: Configuration) -> some View {
            Text(verbatim: "no table here")
        }
    }

    @Test("A custom style composing a built-in one's body draws the table in it")
    func customComposes() throws {
        let (tui, context) = harness()
        let lines = frame(table().tableStyle(Padded()), tui: tui, context: context)
        #expect(!hasBorder(lines), "\(lines)")
        let (tui2, context2) = harness()
        let inset = frame(table().tableStyle(.inset), tui: tui2, context: context2)
        let plain = try #require(column(of: "row0", in: inset))
        #expect(column(of: "row0", in: lines) == plain + 3, "\(lines) vs \(inset)")
    }

    private func column(of needle: String, in lines: [String]) -> Int? {
        for line in lines {
            if let range = line.range(of: needle) {
                return line.distance(from: line.startIndex, to: range.lowerBound)
            }
        }
        return nil
    }

    @Test("A custom style's body is what draws")
    func customReplaces() {
        let (tui, context) = harness()
        let lines = frame(table().tableStyle(Replaced()), tui: tui, context: context)
        #expect(lines.contains { $0.contains("no table here") })
        #expect(!lines.contains { $0.contains("row0") })
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
