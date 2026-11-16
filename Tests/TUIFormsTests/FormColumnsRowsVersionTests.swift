//  🖥️ TUI — A Terminal UI framework for Swift
//  FormColumnsRowsVersionTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIForms
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// A windowed `.columns` form's kept widths are compared by a version of the
/// rows (`DataVersion`), not by the rows: an app that sorts or filters in its
/// body hands the form a new buffer every frame, and every time the form was
/// laid out — each measure, and the render — it compared all of it with the
/// rows it kept, which it never replaced. The same fault, and the same fix, as
/// a `Table`'s `.fit` columns (`TableFitRowsVersionTests`).
///
/// Two things have to hold, and each test here holds one of them: the rows are
/// compared once a frame however many times the form is laid out, and any
/// change to them, the same count with other content included, still misses.
@MainActor
@Suite("Windowed .columns form rows version")
struct FormColumnsRowsVersionTests {
    /// How many times a row's `==` ran.
    private final class Compares: @unchecked Sendable {
        var count = 0
    }

    /// How many rows the loop built: the rows a walk read, and the rows the
    /// frame drew.
    private final class Builds: @unchecked Sendable {
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

    /// A `.columns` form of `rows` in scroll content: past the lazy stack's
    /// threshold, so it builds only the rows on screen and keeps its label
    /// column, read from every row.
    private func form(_ rows: [Row], builds: Builds = Builds()) -> some View {
        ScrollView {
            Form {
                ForEach(rows) { row in
                    builds.count += 1
                    return LabeledContent(row.name, value: "v\(row.id)")
                }
            }
            .formStyle(.columns)
        }
        .scrollIndicatorPlacement(.besideContent)
    }

    /// Short labels, but a long one far down the loop, past the rows drawn.
    private func rows(_ count: Int, compares: Compares = Compares()) -> [Row] {
        (0..<count).map { Row(id: $0, name: $0 == 250 ? "a longer key" : "k\($0 % 5)", compares: compares) }
    }

    /// A copy of `rows` in a buffer of its own: what a body that sorts or
    /// filters hands the form each frame. (`Array(rows)` would share it.)
    private func fresh(_ rows: [Row]) -> [Row] {
        rows.indices.map { rows[$0] }
    }

    /// Renders three frames of `rows`, the warm-up every memo has, and leaves
    /// the widths kept.
    private func settle(_ rows: [Row], in context: RenderContext) {
        for frame in 0..<3 {
            if frame > 0 { context.renderCache?.beginRenderPass() }
            _ = renderToBuffer(form(fresh(rows)), context: context)
        }
    }

    /// The form is laid out by the scroll view's measures and by the render:
    /// compared with the rows it first kept, that was every row compared each
    /// time. Now the frame's first layout compares them, and its later ones
    /// are handed the buffer the first one kept, which compares by identity.
    /// The residue is the drawn rows' own memos, a compare each.
    @Test("Rows built afresh each frame are compared once a frame")
    func freshRowsAreComparedOnce() {
        let context = context()
        let compares = Compares()
        let data = rows(300, compares: compares)
        settle(data, in: context)

        context.renderCache?.beginRenderPass()
        compares.count = 0
        _ = renderToBuffer(form(fresh(data)), context: context)
        #expect(
            compares.count <= data.count + 40,
            "a settled frame compared \(compares.count) rows, of \(data.count)")

        // And handed the same buffer, the rows are not compared at all.
        let same = fresh(data)
        context.renderCache?.beginRenderPass()
        _ = renderToBuffer(form(same), context: context)
        context.renderCache?.beginRenderPass()
        compares.count = 0
        _ = renderToBuffer(form(same), context: context)
        #expect(compares.count <= 40, "the same buffer compared \(compares.count) rows")
    }

    /// A change the next frame brings, as data the form is handed with no
    /// write: only the key can tell the kept widths are stale. Each is made to
    /// rows the frame does not draw, whose labels reach the column only
    /// through the kept widths.
    enum Change: String, CaseIterable, Sendable {
        case edit, insert, remove, append, sameCountOtherContent
    }

    private func apply(_ change: Change, to rows: [Row]) -> [Row] {
        var changed = fresh(rows)
        let compares = rows[0].compares
        let longer = "a much, much longer key"
        switch change {
        case .edit: changed[200].name = longer
        case .insert: changed.insert(Row(id: -1, name: longer, compares: compares), at: 200)
        case .remove: changed.remove(at: 250)
        case .append: changed.append(Row(id: rows.count, name: longer, compares: compares))
        case .sameCountOtherContent:
            changed = rows.map { Row(id: $0.id, name: $0.name + "xyz", compares: compares) }
        }
        return changed
    }

    /// Every change moves the label column, so a frame served from stale
    /// widths draws a different form from one drawn cold.
    @Test("A changed collection misses the kept widths", arguments: Change.allCases)
    func changedRowsMiss(_ change: Change) {
        let context = context()
        let data = rows(300)
        settle(data, in: context)

        let changed = apply(change, to: data)
        context.renderCache?.beginRenderPass()
        let served = renderToBuffer(form(changed), context: context)
        let cold = renderToBuffer(form(fresh(changed)), context: self.context())
        let servedLines = served.lines.map(\.stripped)
        let coldLines = cold.lines.map(\.stripped)
        let picture = "\(servedLines.joined(separator: "\n"))\n---\n\(coldLines.joined(separator: "\n"))"
        #expect(servedLines == coldLines, "\(change): the kept widths outlived the rows they were read from:\n\(picture)")
    }

    /// A reorder moves no width, so its oracle is the walk: rows that are not
    /// the rows the widths were kept for are read again.
    @Test("Reordered rows miss the kept widths")
    func reorderedRowsMiss() {
        let context = context()
        let data = rows(300)
        settle(data, in: context)

        let builds = Builds()
        context.renderCache?.beginRenderPass()
        _ = renderToBuffer(form(Array(data.reversed()), builds: builds), context: context)
        #expect(builds.count >= data.count, "a reorder built \(builds.count) rows, of \(data.count)")
    }
}
