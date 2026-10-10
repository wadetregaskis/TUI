//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableColumnHeadersTests.swift
//
//  `.tableColumnHeaders(.hidden)`: the header line goes, the rows take it, and
//  everything that finds a row by its line still finds the right one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("Table column headers")
struct TableColumnHeadersTests {

    private struct Row: Identifiable, Sendable {
        let id: Int
        let name: String
    }

    private static let rows = (0..<20).map { Row(id: $0, name: "row\($0)") }

    @MainActor
    private final class Harness {
        let tui = TUIContext()
        let dispatcher: MouseEventDispatcher
        let focusManager = FocusManager()
        var selection: Int?
        var sortOrder = [KeyPathComparator(\Row.name)]
        var buffer = FrameBuffer(lines: [])

        init() {
            dispatcher = tui.mouseEventDispatcher
            dispatcher.setActiveSupport(.full)
        }

        func render(headers: Visibility, height: Int = 8) {
            dispatcher.beginRenderPass()
            var env = EnvironmentValues()
            env.mouseEventDispatcher = dispatcher
            env.focusManager = focusManager
            let context = RenderContext(
                availableWidth: 30, availableHeight: height, environment: env, tuiContext: tui)
            let table = Table(
                Array(TableColumnHeadersTests.rows.prefix(4)),
                selection: Binding(get: { self.selection }, set: { self.selection = $0 }),
                sortOrder: Binding(get: { self.sortOrder }, set: { self.sortOrder = $0 })
            ) {
                TableColumn("Name", value: \Row.name)
            }
            .tableColumnHeaders(headers)
            buffer = renderToBuffer(table, context: context)
            dispatcher.setRegions(buffer.hitTestRegions)
        }

        func click(y: Int) {
            dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 5, y: y))
            dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 5, y: y))
        }
    }

    @Test("Hidden headers draw no header line, and the rows begin under the border")
    func hiddenDrawsNoHeader() {
        let harness = Harness()
        harness.render(headers: .visible)
        let shown = harness.buffer.lines.map(\.stripped)
        #expect(shown[1].contains("Name"))
        #expect(shown[2].contains("row0"))
        harness.render(headers: .hidden)
        let hidden = harness.buffer.lines.map(\.stripped)
        #expect(!hidden.contains { $0.contains("Name") })
        #expect(hidden[1].contains("row0"))
        #expect(hidden.count == shown.count - 1)
    }

    @Test("Automatic headers are shown")
    func automaticShows() {
        let harness = Harness()
        harness.render(headers: .automatic)
        #expect(harness.buffer.lines[1].stripped.contains("Name"))
    }

    @Test("With hidden headers, a click on a row's line selects that row")
    func clickFindsTheRow() {
        let harness = Harness()
        harness.render(headers: .hidden)
        harness.click(y: 2)
        #expect(harness.selection == 1)
        harness.render(headers: .visible)
        harness.click(y: 2)
        #expect(harness.selection == 0)
    }

    @Test("Hidden headers give a framed table's rows the header's line")
    func rowsTakeTheLine() {
        let many = Self.rows
        func lines(_ headers: Visibility) -> [String] {
            renderToBuffer(
                Table(many) { TableColumn("Name", value: \Row.name) }
                    .tableColumnHeaders(headers)
                    .frame(height: 8),
                context: makeRenderContext(width: 30, height: 8)
            ).lines.map(\.stripped)
        }
        let rowLines = { (lines: [String]) in lines.filter { $0.contains("row") }.count }
        #expect(rowLines(lines(.hidden)) == rowLines(lines(.visible)) + 1)
    }
}
