//  🖥️ TUI — A Terminal UI framework for Swift
//  TableFitRowsVersionTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUILists
import TUITables
@testable import TUITestSupport
@testable import TUIView

/// A `.fit` column's render-cache entry is compared by a version of the rows
/// (`DataVersion`), not by the rows: an app that sorts or filters in its body
/// hands the table a new buffer every frame, and every ask of every `.fit`
/// column compared all of it, 7% of `Stress`'s 4,000-row `file-browser` frame.
///
/// Two things have to hold, and each test here holds one of them: the rows are
/// compared once a frame however many times the width is asked, and any
/// change to them, the same count with other content included, still misses.
/// No test writes between the frames that matter: a write sweeps the entry,
/// and the frame after it is then not the key's to answer.
@MainActor
@Suite("Table .fit rows version")
struct TableFitRowsVersionTests {
    /// How many times a row's `==` ran.
    private final class Compares: @unchecked Sendable {
        var count = 0
    }

    /// How many times the `.fit` column's closure ran: the rows a walk read,
    /// and the rows the frame drew.
    private final class Calls: @unchecked Sendable {
        var count = 0
    }

    /// A row that counts its comparisons, and compares as its fields do.
    private struct Row: Identifiable, Sendable, Equatable {
        let id: Int
        var name: String
        let compares: Compares

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.compares.count += 1
            return lhs.id == rhs.id && lhs.name == rhs.name
        }
    }

    private func context() -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        return RenderContext(
            availableWidth: 60, availableHeight: 12, environment: environment, tuiContext: TUIContext()
        ).isolatingRenderCache()
    }

    private func table(_ rows: [Row], calls: Calls = Calls()) -> some View {
        Table(rows, selection: Binding<Int?>.constant(nil)) {
            TableColumn("Name") { (row: Row) -> Text in
                calls.count += 1
                return Text(verbatim: row.name)
            }
            .width(.fit)
            TableColumn("Kind") { (row: Row) in Text(verbatim: row.name) }.width(.fit)
            TableColumn("ID") { (row: Row) in Text(verbatim: "\(row.id)") }
        }
        .scrollIndicatorPlacement(.besideContent)
    }

    private func rows(_ count: Int, compares: Compares = Compares()) -> [Row] {
        (0..<count).map { Row(id: $0, name: $0 == 3 ? "Wolfgang" : "ab", compares: compares) }
    }

    /// A copy of `rows` in a buffer of its own: what a body that sorts or
    /// filters hands the table each frame. (`Array(rows)` would share it.)
    private func fresh(_ rows: [Row]) -> [Row] {
        rows.indices.map { rows[$0] }
    }

    /// Renders three frames of `rows`, the warm-up every memo has (the
    /// table's first frame writes its own `@State`), and leaves the entry
    /// stored.
    private func settle(_ rows: [Row], in context: RenderContext) {
        for frame in 0..<3 {
            if frame > 0 { context.renderCache?.beginRenderPass() }
            _ = renderToBuffer(table(fresh(rows)), context: context)
        }
    }

    /// Two `.fit` columns, each asked by the measure and by the render: keyed
    /// by the rows, that was every row compared per ask. Now the frame's
    /// first ask compares them, and its later asks are handed the buffer the
    /// first one kept, which compares by identity. The residue is the drawn
    /// rows' own memos, a compare each.
    @Test("Rows built afresh each frame are compared once a frame")
    func freshRowsAreComparedOnce() {
        let context = context()
        let compares = Compares()
        let data = rows(300, compares: compares)
        settle(data, in: context)

        context.renderCache?.beginRenderPass()
        compares.count = 0
        _ = renderToBuffer(table(fresh(data)), context: context)
        #expect(
            compares.count <= data.count + 40,
            "a settled frame compared \(compares.count) rows, of \(data.count)")

        // And handed the same buffer, the rows are not compared at all.
        let same = fresh(data)
        context.renderCache?.beginRenderPass()
        _ = renderToBuffer(table(same), context: context)
        context.renderCache?.beginRenderPass()
        compares.count = 0
        _ = renderToBuffer(table(same), context: context)
        #expect(compares.count <= 40, "the same buffer compared \(compares.count) rows")
    }

    /// A change the next frame brings, as data the table is handed with no
    /// write: only the key can tell the kept width is stale.
    enum Change: String, CaseIterable, Sendable {
        case edit, insert, remove, append, sameCountOtherContent
    }

    private func apply(_ change: Change, to rows: [Row]) -> [Row] {
        var changed = fresh(rows)
        let compares = rows[0].compares
        switch change {
        case .edit: changed[100].name = "Bartholomew"
        case .insert: changed.insert(Row(id: -1, name: "Bartholomew", compares: compares), at: 0)
        case .remove: changed.remove(at: 3)
        case .append: changed.append(Row(id: rows.count, name: "Bartholomew", compares: compares))
        case .sameCountOtherContent:
            changed = rows.map { Row(id: $0.id, name: $0.name + "xyz", compares: compares) }
        }
        return changed
    }

    /// Every change moves the `.fit` width, so a frame served from a stale
    /// entry draws a different table from one drawn cold.
    @Test("A changed collection misses the kept width", arguments: Change.allCases)
    func changedRowsMiss(_ change: Change) {
        let context = context()
        let data = rows(200)
        settle(data, in: context)

        let changed = apply(change, to: data)
        context.renderCache?.beginRenderPass()
        let served = renderToBuffer(table(changed), context: context)
        let cold = renderToBuffer(table(fresh(changed)), context: self.context())
        let servedLines = served.lines.map(\.stripped)
        let coldLines = cold.lines.map(\.stripped)
        #expect(
            servedLines == coldLines,
            "\(change): the kept width outlived the rows it was taken over:\n\(servedLines.joined(separator: "\n"))\n---\n\(coldLines.joined(separator: "\n"))")
    }

    /// A reorder moves no width, so its oracle is the walk: rows that are not
    /// the rows the width was kept for are read again.
    @Test("Reordered rows miss the kept width")
    func reorderedRowsMiss() {
        let context = context()
        let data = rows(200)
        settle(data, in: context)

        let calls = Calls()
        context.renderCache?.beginRenderPass()
        _ = renderToBuffer(table(Array(data.reversed()), calls: calls), context: context)
        #expect(calls.count >= data.count, "a reorder read \(calls.count) cells, of \(data.count) rows")
    }
}
