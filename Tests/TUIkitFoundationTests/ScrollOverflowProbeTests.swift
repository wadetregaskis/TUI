//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollOverflowProbeTests.swift
//
//  The scrollbar's first round asks only whether a scroll view's content is
//  taller than its viewport. For content that is, by its type, an eager
//  column, it asks with the overflow mark (`RenderContext.asksOverflow`), and
//  the column stops measuring once its rows pass the viewport. These pin
//  that it stops, that it answers as the ladder does all the same, that its
//  partial answer is never served to a full measure, and the cases that must
//  not stop.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

/// Counts the measures its rows answer; a size the memo serves is not one.
/// `@unchecked`: driven on the main actor.
private final class RowMeasures: @unchecked Sendable {
    var count = 0
}

/// A row of a stated size that counts its own measures. Natural, as a line of
/// text is, so the pass's memo serves it to any budget that holds it.
private struct SizedRow: View, Layoutable {
    let width: Int
    let height: Int
    let measures: RowMeasures
    var body: Never { fatalError("SizedRow renders via Renderable") }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measures.count += 1
        return ViewSize.fixed(width, height).declaringNaturalSize()
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer(lines: Array(repeating: String(repeating: "x", count: width), count: height))
    }
}

/// A one-line row that reads the scroll viewport, as an image fitted to it
/// does. No memo keeps a measure beneath such a read, so every walk of a
/// column holding it measures it again.
private struct ViewportReadingRow: View, Layoutable {
    let measures: RowMeasures
    var body: Never { fatalError("ViewportReadingRow renders via Renderable") }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measures.count += 1
        _ = context.environment.scrollViewportSize
        return ViewSize.fixed(4, 1).declaringNaturalSize()
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer(lines: ["xxxx"])
    }
}

/// A view of the app's own whose body is a column: measured as its body is.
private struct ColumnOfRows: View {
    let heights: [Int]
    var spacing = 0
    let measures: RowMeasures

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(heights.enumerated()), id: \.offset) { row in
                SizedRow(width: 4, height: row.element, measures: measures)
            }
        }
    }
}

/// A view of the app's own whose body is another of the app's own.
private struct WrappedColumn: View {
    let column: ColumnOfRows
    var body: some View { column }
}

@MainActor
@Suite("An eager column asked only whether it overflows stops a line past the viewport")
struct ScrollOverflowProbeTests {
    private static let width = 30

    /// The render loop's shape — an isolated cache with the volatile-read
    /// tracker that turns the measure memo on — in a pass of its own.
    private func liveContext() -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        let storage = StateStorage()
        environment.stateStorage = storage
        environment.installVolatileReadTracker(VolatileReadTracker())
        var context = RenderContext(
            availableWidth: Self.width, availableHeight: 20, environment: environment, tuiContext: TUIContext()
        ).isolatingRenderCache()
        context.stateStorage = storage
        context.renderCache?.beginRenderPass()
        return context
    }

    private func core<Content: View>(_ content: Content) -> _ScrollViewCore<Content> {
        _ScrollViewCore(axes: .vertical, content: content, explicitFocusID: nil, isDisabled: false)
    }

    /// The first round's question and the ladder's, each in a pass of its own,
    /// and how many row measures the first round's took.
    private func ask<Content: View>(
        _ content: Content, viewportHeight: Int, measures: RowMeasures
    ) -> (shortcut: Bool, ladder: Bool, rowsMeasured: Int) {
        let scroll = core(content)
        let before = measures.count
        let shortcut = scroll.contentOverflowsCanvas(
            contentWidth: Self.width, viewportHeight: viewportHeight, context: liveContext())
        let rowsMeasured = measures.count - before
        let ladder =
            scroll.contentExtents(
                contentWidth: Self.width, viewportHeight: viewportHeight, horizontal: false, context: liveContext()
            ).height > viewportHeight
        return (shortcut, ladder, rowsMeasured)
    }

    /// Thirty rows of a line, asked at viewports around their height: the
    /// column stops once its rows reach a line past the viewport, and says
    /// what the ladder says. Asked at the ladder's first rung, as before the
    /// mark, it measured all thirty at every height.
    @Test("A column of thirty lines stops a line past the viewport", arguments: [0, 1, 5, 19, 28, 29, 30, 31, 60])
    func stopsALinePastTheViewport(viewportHeight: Int) {
        let measures = RowMeasures()
        let found = ask(
            ColumnOfRows(heights: Array(repeating: 1, count: 30), measures: measures),
            viewportHeight: viewportHeight, measures: measures)
        #expect(found.shortcut == found.ladder, "the shortcut said \(found.shortcut), the ladder \(found.ladder)")
        #expect(found.shortcut == (viewportHeight < 30))
        #expect(
            found.rowsMeasured == min(30, viewportHeight + 1),
            "\(found.rowsMeasured) rows measured to ask whether thirty overflow \(viewportHeight) lines")
    }

    /// The gaps count as they do in the whole column — one per row that
    /// occupies any line, after the first.
    @Test("Gaps between the rows count toward the line past the viewport", arguments: [0, 4, 9, 20, 31, 32, 33, 39])
    func gapsCount(viewportHeight: Int) {
        let heights = [2, 0, 1, 3, 1, 2, 1, 1, 2, 1, 1, 1, 1, 2, 1]
        let measures = RowMeasures()
        let found = ask(
            ColumnOfRows(heights: heights, spacing: 1, measures: measures),
            viewportHeight: viewportHeight, measures: measures)
        // 20 lines of rows, and 13 gaps between the 14 rows that have any.
        #expect(found.shortcut == found.ladder, "the shortcut said \(found.shortcut), the ladder \(found.ladder)")
        #expect(found.shortcut == (viewportHeight < 33))
        // The rows it takes for the lines so far and a gap after every
        // occupied row but the first to reach a line past the viewport.
        var expected = heights.count
        var lines = 0
        var occupied = 0
        for (index, height) in heights.enumerated() {
            lines += height
            if height > 0 { occupied += 1 }
            if lines + max(0, occupied - 1) > viewportHeight {
                expected = index + 1
                break
            }
        }
        #expect(found.rowsMeasured == expected, "\(found.rowsMeasured) rows measured, not \(expected)")
    }

    /// A view of the app's own measures as its body does, so a column behind
    /// one, or behind two, stops as a bare one does.
    @Test("A column behind views of the app's own stops too")
    func columnBehindAppViewsStops() {
        let measures = RowMeasures()
        let column = ColumnOfRows(heights: Array(repeating: 1, count: 30), measures: measures)
        #expect(ask(column, viewportHeight: 9, measures: measures).rowsMeasured == 10)
        let wrapped = ask(WrappedColumn(column: column), viewportHeight: 9, measures: measures)
        #expect(wrapped.shortcut && wrapped.ladder)
        #expect(wrapped.rowsMeasured == 10, "\(wrapped.rowsMeasured) rows measured behind two views")
    }

    /// The mark goes only where nothing can read the width a stopped column
    /// answers with: a `VStack` and the app's own views over one. Anything
    /// else in between — padding, a row, a type-erased view, a lazy stack,
    /// which ignores the mark but would have its answers keyed apart by it —
    /// is asked as before.
    @Test("The mark goes to an eager column and the app's own views over one, and nowhere else")
    func markGoesOnlyToEagerColumns() {
        let measures = RowMeasures()
        let column = ColumnOfRows(heights: [1, 1], measures: measures)
        #expect(measuresAsEagerColumn(type(of: VStack { Text("a") })))
        #expect(measuresAsEagerColumn(ColumnOfRows.self))
        #expect(measuresAsEagerColumn(WrappedColumn.self))
        #expect(!measuresAsEagerColumn(type(of: column.padding(1))))
        #expect(!measuresAsEagerColumn(type(of: LazyVStack { Text("a") })))
        #expect(!measuresAsEagerColumn(type(of: HStack { column })))
        #expect(!measuresAsEagerColumn(AnyView.self))
        #expect(!measuresAsEagerColumn(Text.self))
        let long = ColumnOfRows(heights: Array(repeating: 1, count: 30), measures: measures)
        let padded = ask(long.padding(1), viewportHeight: 5, measures: measures)
        #expect(padded.shortcut && padded.ladder)
        #expect(padded.rowsMeasured == 30, "a padded column was stopped: \(padded.rowsMeasured) rows")
    }

    /// The memo half. A stopped column's answer is the budget for its height,
    /// as the whole column's is, but the width of the rows it measured. Kept
    /// under the key a full measure looks up, at the same proposal and budget,
    /// it would be that measure's answer: here a column four wide where the
    /// whole one is twenty-five, because its wide row lies past the stop.
    @Test("A full measure after a stopped probe at the same proposal is the whole column's answer")
    func stoppedAnswerNeverServesAFullMeasure() {
        let measures = RowMeasures()
        let rows = (0..<12).map { $0 == 9 ? 25 : 4 }
        let content = VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { row in
                SizedRow(width: row.element, height: 1, measures: measures)
            }
        }
        let scroll = core(content)
        let viewportHeight = 3
        let context = liveContext()
        #expect(scroll.contentOverflowsCanvas(contentWidth: Self.width, viewportHeight: viewportHeight, context: context))
        #expect(measures.count == viewportHeight + 1, "precondition: the probe stopped: \(measures.count) rows")
        // The probe's own canvas, at its own proposal and budget, unmarked.
        func canvas(_ context: RenderContext) -> RenderContext {
            var canvas = scroll.contentCanvasContext(
                contentWidth: Self.width, viewportHeight: viewportHeight, horizontal: false, context: context
            ).askingIdealWidth(false)
            canvas.availableWidth = Self.width
            canvas.availableHeight = viewportHeight + 1
            return canvas
        }
        let proposal = ProposedSize(width: Self.width, height: nil)
        let measured = measureChild(content, proposal: proposal, context: canvas(context))
        let fresh = measureChild(content, proposal: proposal, context: canvas(liveContext()))
        #expect(measured.width == 25, "the full measure was served the stopped column's width: \(measured)")
        #expect(measured == fresh, "the full measure, \(measured), is not a fresh one, \(fresh)")
    }

    /// A column that fits never reaches the line past the viewport, so it
    /// measures every row, and answers from that one walk, as the unmarked ask
    /// did. These rows read the viewport, so no memo keeps them and a second
    /// walk measures each again. The first scrollbar round asks this on a frame
    /// whose content stopped overflowing; a text-style view under a scroll
    /// target behaviour asks it on every layout (`contentOverflowsWindow`).
    @Test("A column that fits is walked once", arguments: [10, 11, 40])
    func fittingColumnIsWalkedOnce(viewportHeight: Int) {
        let measures = RowMeasures()
        let content = VStack(spacing: 0) {
            ForEach(0..<10, id: \.self) { _ in ViewportReadingRow(measures: measures) }
        }
        let scroll = core(content)
        let firstRound = scroll.contentOverflowsCanvas(
            contentWidth: Self.width, viewportHeight: viewportHeight, context: liveContext())
        #expect(!firstRound, "precondition: ten lines fit \(viewportHeight)")
        #expect(measures.count == 10, "the first round measured \(measures.count) rows for ten that fit")
        measures.count = 0
        let window = scroll.contentOverflowsWindow(
            viewport: CellSize(width: Self.width, height: viewportHeight), context: liveContext())
        #expect(!window, "precondition: ten lines fit \(viewportHeight)")
        #expect(measures.count == 10, "the content-margins probe measured \(measures.count) rows for ten that fit")
    }

    /// The same for rows the pass's memo keeps: a second walk is a lookup per
    /// row, which hashes the row's value. A fitting column asked with the mark
    /// looks up exactly what the unmarked ask at the ladder's first rung does.
    @Test("A column that fits looks its rows up as often as the unmarked ask")
    func fittingColumnLooksUpAsTheRungDoes() {
        let measures = RowMeasures()
        let column = ColumnOfRows(heights: Array(repeating: 1, count: 10), measures: measures)
        let scroll = core(column)
        let viewportHeight = 12
        func lookups(_ ask: (RenderContext) -> Void) -> Int {
            let context = liveContext()
            func total() -> Int {
                guard let totals = context.renderCache?.measureMemoTotals else { return 0 }
                return totals.hits + totals.misses
            }
            let before = total()
            ask(context)
            return total() - before
        }
        let marked = lookups { context in
            #expect(
                !scroll.contentOverflowsCanvas(
                    contentWidth: Self.width, viewportHeight: viewportHeight, context: context))
        }
        let unmarked = lookups { context in
            var canvas = scroll.contentCanvasContext(
                contentWidth: Self.width, viewportHeight: viewportHeight, horizontal: false, context: context
            ).askingIdealWidth(false)
            canvas.availableWidth = Self.width
            canvas.availableHeight = naturalExtentStartingBudget(forVisible: viewportHeight)
            _ = measureChild(column, proposal: ProposedSize(width: Self.width, height: nil), context: canvas)
        }
        #expect(marked == unmarked, "\(marked) lookups under the mark, \(unmarked) without it")
        #expect(measures.count == 20, "each ask measured its ten rows once: \(measures.count)")
    }

    /// A NEGATIVE spacing subtracts a line per gap, so the rows measured so
    /// far say nothing about the total: a five-line row pulled up by the
    /// three after it is a column two lines tall. Stopped at the five lines,
    /// it reserved a bar for content that fits.
    @Test("A column with negative spacing is never stopped early")
    func negativeSpacingNeverStops() {
        let measures = RowMeasures()
        let found = ask(
            ColumnOfRows(heights: [5, 1, 1, 1], spacing: -2, measures: measures), viewportHeight: 3,
            measures: measures)
        #expect(!found.ladder, "precondition: the column is two lines and fits")
        #expect(found.shortcut == found.ladder, "the shortcut said \(found.shortcut), the ladder \(found.ladder)")
        #expect(found.rowsMeasured == 4, "\(found.rowsMeasured) rows measured, not all four")
    }
}
