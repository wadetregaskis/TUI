//  🖥️ TUI — A Terminal UI framework for Swift
//  StackContentWidthRowsVersionTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// A lazy stack's width over every row (`StackContentWidth.swift`) is kept
/// for a version of the rows (`DataVersion`), not compared with the rows: an
/// app that sorts or filters in its body hands the stack a new buffer every
/// frame, and every ask of a two-axis scroll view — several a frame — compared
/// all of it with the rows the record was taken over, which it never replaced.
/// The same fault, and the same fix, as a `Table`'s `.fit` columns
/// (`TableFitRowsVersionTests`).
///
/// Two things have to hold, and each test here holds one of them: the rows are
/// compared once a frame however many times the width is asked, and any
/// change to them, the same count with other content included, still misses.
@MainActor
@Suite("Lazy stack content width rows version")
struct StackContentWidthRowsVersionTests {
    /// How many times a row's `==` ran.
    private final class Compares: @unchecked Sendable {
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
            availableWidth: 40, availableHeight: 12, environment: environment, tuiContext: TUIContext()
        ).isolatingRenderCache()
    }

    /// A lazy stack of `rows` on both scroll axes, its horizontal bar drawn at
    /// rest: the bar's thumb is the width over every row.
    private func editor(_ rows: [Row]) -> some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { (row: Row) in Text(verbatim: row.name) }
            }
        }
        .scrollIndicatorPlacement(.besideContent)
    }

    /// Short rows, but a wide one far down the loop, past the rows drawn.
    private func rows(_ count: Int, compares: Compares = Compares()) -> [Row] {
        (0..<count).map {
            Row(id: $0, name: $0 == 250 ? String(repeating: "w", count: 60) : "ab", compares: compares)
        }
    }

    /// A copy of `rows` in a buffer of its own: what a body that sorts or
    /// filters hands the stack each frame. (`Array(rows)` would share it.)
    private func fresh(_ rows: [Row]) -> [Row] {
        rows.indices.map { rows[$0] }
    }

    /// Renders three frames of `rows`, the warm-up every memo has, and leaves
    /// the width kept.
    private func settle(_ rows: [Row], in context: RenderContext) {
        for frame in 0..<3 {
            if frame > 0 { context.renderCache?.beginRenderPass() }
            _ = renderToBuffer(editor(fresh(rows)), context: context)
        }
    }

    /// The scroll view asks for the width over every row several times a
    /// frame: compared with the rows the record was taken over, that was every
    /// row compared per ask. Now the frame's first ask compares them, and its
    /// later asks are handed the buffer the first one kept, which compares by
    /// identity. The residue is the drawn rows' own memos, a compare each.
    @Test("Rows built afresh each frame are compared once a frame")
    func freshRowsAreComparedOnce() {
        let context = context()
        let compares = Compares()
        let data = rows(300, compares: compares)
        settle(data, in: context)

        context.renderCache?.beginRenderPass()
        compares.count = 0
        _ = renderToBuffer(editor(fresh(data)), context: context)
        #expect(
            compares.count <= data.count + 40,
            "a settled frame compared \(compares.count) rows, of \(data.count)")

        // And handed the same buffer, the rows are not compared at all.
        let same = fresh(data)
        context.renderCache?.beginRenderPass()
        _ = renderToBuffer(editor(same), context: context)
        context.renderCache?.beginRenderPass()
        compares.count = 0
        _ = renderToBuffer(editor(same), context: context)
        #expect(compares.count <= 40, "the same buffer compared \(compares.count) rows")
    }

    /// A change the next frame brings, as data the stack is handed with no
    /// write: only the key can tell the kept width is stale. Each is made to
    /// rows the frame does not draw, whose width reaches the scroll view only
    /// through the kept one.
    enum Change: String, CaseIterable, Sendable {
        case edit, insert, remove, append, sameCountOtherContent
    }

    private func apply(_ change: Change, to rows: [Row]) -> [Row] {
        var changed = fresh(rows)
        let compares = rows[0].compares
        let wider = String(repeating: "W", count: 90)
        switch change {
        case .edit: changed[200].name = wider
        case .insert: changed.insert(Row(id: -1, name: wider, compares: compares), at: 200)
        case .remove: changed.remove(at: 250)
        case .append: changed.append(Row(id: rows.count, name: wider, compares: compares))
        case .sameCountOtherContent:
            changed = rows.map { Row(id: $0.id, name: $0.name + String(repeating: "x", count: 30), compares: compares) }
        }
        return changed
    }

    /// Every change moves the width over every row, so a frame served from a
    /// stale width draws a different horizontal bar — its thumb — from one
    /// drawn cold.
    @Test("A changed collection misses the kept width", arguments: Change.allCases)
    func changedRowsMiss(_ change: Change) {
        let context = context()
        let data = rows(300)
        settle(data, in: context)

        let changed = apply(change, to: data)
        context.renderCache?.beginRenderPass()
        let served = renderToBuffer(editor(changed), context: context)
        let cold = renderToBuffer(editor(fresh(changed)), context: self.context())
        // With their styling: stripped, a bar is its two arrows and blanks, and
        // the thumb that says how wide the content is is gone.
        let servedLines = served.lines
        let coldLines = cold.lines
        #expect(
            servedLines == coldLines,
            "\(change): the kept width outlived the rows it was taken over:\n\(servedLines.joined(separator: "\n"))\n---\n\(coldLines.joined(separator: "\n"))")
    }

    /// A reorder moves no width, so its oracle is the walk: rows that are not
    /// the rows the width was kept for are measured again. Counted by the
    /// rows' compares, not by their closure: a walked row's size is served by
    /// its memo, which is keyed by its element and compares it, so a walk of
    /// a reorder compares every row and builds none. Without the walk, the
    /// reordered rows differ from the kept ones at their first element.
    @Test("Reordered rows miss the kept width")
    func reorderedRowsMiss() {
        let context = context()
        let compares = Compares()
        let data = rows(300, compares: compares)
        settle(data, in: context)

        context.renderCache?.beginRenderPass()
        compares.count = 0
        _ = renderToBuffer(editor(Array(data.reversed())), context: context)
        #expect(compares.count >= data.count, "a reorder compared \(compares.count) rows, of \(data.count)")
    }
}
