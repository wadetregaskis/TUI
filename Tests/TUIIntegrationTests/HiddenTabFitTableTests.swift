//  🖥️ TUI — A Terminal UI framework for Swift
//  HiddenTabFitTableTests.swift
//
//  A `Table` with `.fit` columns in a tab that is not shown: what a switch to
//  it costs, and that the widths it draws with follow rows that changed while
//  it was hidden (PERFCASE-F2).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

@MainActor
@Suite("A hidden tab's .fit table")
struct HiddenTabFitTableTests {
    /// How many times the `.fit` column's closure ran.
    private final class Calls: @unchecked Sendable {
        var count = 0
    }

    private struct Row: Identifiable, Sendable, Equatable {
        let id: Int
        var name: String
    }

    private func context() -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        return RenderContext(
            availableWidth: 60, availableHeight: 16, environment: environment, tuiContext: TUIContext()
        ).isolatingRenderCache()
    }

    private func page(_ rows: [Row], tab: Int, calls: Calls = Calls()) -> some View {
        TabView(selection: .constant(tab)) {
            Tab("List", value: 0) { Text(verbatim: "the list") }
            Tab("Table", value: 1) {
                Table(rows, selection: Binding<Int?>.constant(nil)) {
                    TableColumn("Name") { (row: Row) -> Text in
                        calls.count += 1
                        return Text(verbatim: row.name)
                    }
                    .width(.fit)
                    TableColumn("ID") { (row: Row) in Text(verbatim: "\(row.id)") }
                }
            }
        }
    }

    /// The next frame through `context`'s cache, after a write at the root —
    /// the selection's, which a tab switch is.
    private func frame(_ view: some View, in context: RenderContext) -> [String] {
        context.renderCache?.invalidateRender(for: context.identity)
        context.renderCache?.beginRenderPass()
        return renderToBuffer(view, context: context).lines.map(\.stripped)
    }

    /// Where the "ID" column starts in the table's header, which is where the
    /// `.fit` column's width puts it.
    private func idColumn(_ lines: [String]) -> Int? {
        guard let header = lines.first(where: { $0.contains("Name") && $0.contains("ID") }),
            let range = header.range(of: "ID")
        else { return nil }
        return header.distance(from: header.startIndex, to: range.lowerBound)
    }

    private func rows(_ count: Int) -> [Row] {
        (0..<count).map { Row(id: $0, name: $0 == 3 ? "Wolfgang" : "ab") }
    }

    @Test("Switching back to a tab whose rows did not change reads no row again")
    func switchBackReadsNothing() {
        let data = rows(300)
        let calls = Calls()
        let context = context()
        _ = renderToBuffer(page(data, tab: 0, calls: calls), context: context)
        for tab in [0, 1, 0] { _ = frame(page(data, tab: tab, calls: calls), in: context) }
        calls.count = 0
        let drawn = frame(page(data, tab: 1, calls: calls), in: context)

        // The rows the frame draws and the record's widest row: not 300.
        #expect(calls.count < 40, "the switch read \(calls.count) cells")
        #expect(idColumn(drawn) == idColumn(renderToBuffer(page(data, tab: 1), context: self.context()).lines.map(\.stripped)))
    }

    @Test("Rows changed while the tab was hidden draw at their own widths")
    func changeWhileHiddenIsSeen() {
        var data = rows(300)
        let context = context()
        _ = renderToBuffer(page(data, tab: 0), context: context)
        for tab in [1, 0] { _ = frame(page(data, tab: tab), in: context) }
        // Hidden: a wider row appended, then the widest one removed.
        data.append(Row(id: 300, name: "Bartholomew Longname"))
        _ = frame(page(data, tab: 0), in: context)
        let widened = frame(page(data, tab: 1), in: context)
        let cold = { (rows: [Row]) in
            self.idColumn(renderToBuffer(self.page(rows, tab: 1), context: self.context()).lines.map(\.stripped))
        }
        #expect(idColumn(widened) == cold(data), "the appended row")

        _ = frame(page(data, tab: 0), in: context)
        data.removeLast()
        _ = frame(page(data, tab: 0), in: context)
        let narrowed = frame(page(data, tab: 1), in: context)
        #expect(idColumn(narrowed) == cold(data), "the removed row")
        #expect(idColumn(narrowed) != idColumn(widened))
    }
}
