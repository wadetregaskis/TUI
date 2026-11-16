//  🖥️ TUI — A Terminal UI framework for Swift
//  TableFitRecordTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIFoundation
@testable import TUILists
import TUITables
@testable import TUITestSupport
@testable import TUIView

/// What a cell reads that is not its row: an `@Observable`, so a change to it
/// reaches the table only through the scope its `.fit` walk armed.
@MainActor @Observable
final class TableFitRecordModel {
    var note = ""
}

/// A `.fit` column's kept walk (`_TableFitRecord`): the write that brings a
/// row sweeps the render cache's entry, and the record it falls back to walks
/// only the rows that grew the collection (PERFCASE-F1). Every test here makes
/// that write — a clear of everything below the root, as an app's model write
/// is — before the frame that matters, and every width is checked against a
/// table drawn cold.
@MainActor
@Suite("Table .fit kept walk")
struct TableFitRecordTests {
    /// How many times the `.fit` column's closure ran: the rows a walk read,
    /// plus the rows the frame drew.
    private final class Calls: @unchecked Sendable {
        var count = 0
    }

    /// What the cells read besides the row: a write here changes what every
    /// cell draws with no row changing.
    private final class Format: @unchecked Sendable {
        var suffix = ""
    }

    private struct Row: Identifiable, Sendable, Equatable {
        let id: Int
        var name: String
    }

    private func context() -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        return RenderContext(
            availableWidth: 60, availableHeight: 12, environment: environment, tuiContext: TUIContext()
        ).isolatingRenderCache()
    }

    private func table(
        _ rows: [Row], calls: Calls = Calls(), format: Format = Format(), model: TableFitRecordModel? = nil
    ) -> some View {
        Table(rows, selection: Binding<Int?>.constant(nil)) {
            TableColumn("Name") { (row: Row) -> Text in
                calls.count += 1
                // Row 150 reads the model: a row no frame draws and no record names.
                let note = row.id == 150 ? model?.note ?? "" : ""
                return Text(verbatim: row.name + format.suffix + note)
            }
            .width(.fit)
            TableColumn("ID") { (row: Row) in Text(verbatim: "\(row.id)") }
        }
        .scrollIndicatorPlacement(.besideContent)
    }

    private func rows(_ count: Int) -> [Row] {
        (0..<count).map { Row(id: $0, name: $0 == 3 ? "Wolfgang" : "ab") }
    }

    /// Renders `view` as the next frame through `context`'s cache, after a
    /// write at the root when `written`, and answers what it drew.
    private func frame(_ view: some View, in context: RenderContext, written: Bool = true) -> [String] {
        if written { context.renderCache?.invalidateRender(for: context.identity) }
        context.renderCache?.beginRenderPass()
        return renderToBuffer(view, context: context).lines
    }

    /// What `rows` draw in a table that has kept nothing.
    private func cold(_ rows: [Row], format: Format = Format(), model: TableFitRecordModel? = nil) -> [String] {
        renderToBuffer(table(rows, format: format, model: model), context: context()).lines
    }

    /// A table settled over `rows`: three frames, the third the first a memo
    /// can serve (see `TableFitColumnMemoTests.settledFrameSkipsTheScan`).
    private func settled(_ rows: [Row], calls: Calls = Calls(), format: Format = Format(), model: TableFitRecordModel? = nil)
        -> RenderContext
    {
        let context = context()
        _ = renderToBuffer(table(rows, calls: calls, format: format, model: model), context: context)
        for _ in 0..<2 { _ = frame(table(rows, calls: calls, format: format, model: model), in: context) }
        return context
    }

    @Test("An appended row is the only row walked, and widens the column")
    func appendWalksOnlyTheNewRow() {
        var data = rows(200)
        let calls = Calls()
        let context = settled(data, calls: calls)
        data.append(Row(id: 200, name: "Bartholomew Longname"))
        calls.count = 0
        let drawn = frame(table(data, calls: calls), in: context)

        // The drawn rows, the record's widest row read again after the write,
        // and the new one — not the 200 before it.
        #expect(calls.count < 40, "walked \(calls.count) cells for one appended row")
        #expect(drawn == cold(data), "the extended width drew a different table")
    }

    @Test("A row edited wider, then narrower again, moves the column both ways")
    func editMovesTheWidth() {
        var data = rows(120)
        let context = settled(data)
        data[60].name = "Maximilian Augustus"
        #expect(frame(table(data), in: context) == cold(data), "the widened row")
        data[60].name = "ab"
        #expect(frame(table(data), in: context) == cold(data), "the narrowed row")
    }

    @Test("Removing the widest row narrows the column")
    func removingTheWidestNarrows() {
        var data = rows(120)
        let context = settled(data)
        let before = frame(table(data), in: context)
        data.remove(at: 3)
        let after = frame(table(data), in: context)
        #expect(after == cold(data))
        #expect(after != before, "the column kept the removed row's width")
    }

    @Test("Removing the widest row and appending a narrower one narrows the column")
    func removeThenAppendNarrows() {
        var data = rows(120)
        let context = settled(data)
        data.remove(at: 3)
        data.append(Row(id: 500, name: "abcd"))
        #expect(frame(table(data), in: context) == cold(data))
    }

    @Test("A write that changes what every cell draws, rows unchanged, is read again")
    func capturedChangeIsChallenged() {
        let data = rows(120)
        let format = Format()
        let context = settled(data, format: format)
        format.suffix = " (archived)"
        #expect(frame(table(data, format: format), in: context) == cold(data, format: format))
    }

    @Test("An @Observable a cell read, changed in a row nothing draws, widens the column")
    func observedChangeInAnUndrawnRow() {
        let data = rows(200)
        let model = TableFitRecordModel()
        let context = settled(data, model: model)
        model.note = " and a much longer note"
        // No write of the test's own: the change reaches the table only through
        // the scope its walk armed.
        let drawn = frame(table(data, model: model), in: context, written: false)
        #expect(drawn == cold(data, model: model))
    }

    @Test("A narrower and a wider table read no row again, and fit as a cold one does")
    func resizeReadsNothing() {
        var data = rows(200)
        data[100].name = "Maximilian Augustus"
        let calls = Calls()
        var context = settled(data, calls: calls)
        for width in [40, 72, 60] {
            context.availableWidth = width
            calls.count = 0
            let drawn = frame(table(data, calls: calls), in: context)
            var fresh = self.context()
            fresh.availableWidth = width
            #expect(drawn == renderToBuffer(table(data), context: fresh).lines, "at \(width)")
            #expect(calls.count < 40, "at \(width) the table read \(calls.count) cells")
        }
    }
}
