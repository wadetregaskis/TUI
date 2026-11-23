//  🖥️ TUI — A Terminal UI framework for Swift
//  TableAnalyticMeasureTests.swift
//
//  Table's single-line measure path is analytic (O(columns), no row
//  rendering); the render path builds the real rows. The two must agree on
//  the table's dimensions for EVERY configuration — this sweep holds them
//  equal across row counts (empty/fitting/overflowing), terminal sizes,
//  scrollbar visibilities, and column-width mixes, including `.fit` columns
//  whose values saturate the interior (the early-out path).
//
//  The sweeps place the indicators `.besideContent`, the shapes they were
//  written for. Under the default, `.overContent`, a table renders once,
//  takes the focus while it does, and is then measured holding it: beside
//  its rows from the measure on, so the render before it drew a different
//  shape. That is the frame the focus arrives on, not a measure disagreeing
//  with its render.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUILists
import TUITables
@testable import TUITestSupport

private struct MeasureRow: Identifiable {
    let id: Int
    let name: String
    let detail: String
}

@MainActor
@Suite("Table analytic measure equivalence")
struct TableAnalyticMeasureTests {

    private func rows(_ count: Int, wide: Bool = false) -> [MeasureRow] {
        (0..<count).map { index in
            MeasureRow(
                id: index,
                name: wide
                    ? "row-\(index) " + String(repeating: "x", count: 90)
                    : "row-\(index)",
                detail: "detail \(index)")
        }
    }

    /// Every column mix exercised by the sweep, as erased table builders.
    private func tables(
        data: [MeasureRow]
    ) -> [(label: String, table: AnyView)] {
        [
            (
                "flexible+fixed",
                AnyView(
                    Table(data, selection: .constant(Int?.none)) {
                        TableColumn("Name", value: \MeasureRow.name)
                        TableColumn("Detail", value: \MeasureRow.detail).width(10)
                    })
            ),
            (
                "fit",
                AnyView(
                    Table(data, selection: .constant(Int?.none)) {
                        TableColumn("Name", value: \MeasureRow.name).width(.fit)
                        TableColumn("Detail", value: \MeasureRow.detail).width(.fit)
                    })
            ),
            (
                "ratio",
                AnyView(
                    Table(data, selection: .constant(Int?.none)) {
                        TableColumn("Name", value: \MeasureRow.name).width(.ratio(0.6))
                        TableColumn("Detail", value: \MeasureRow.detail).width(.ratio(0.4))
                    })
            ),
        ]
    }

    @Test(
        "Analytic measure equals rendered size across the configuration matrix",
        arguments: [0, 1, 3, 12, 40, 150], [ScrollIndicatorVisibility.automatic, .visible, .hidden])
    func analyticMatchesRender(rowCount: Int, barVisibility: ScrollIndicatorVisibility) {
        for (width, height) in [(20, 8), (40, 12), (80, 24), (120, 43)] {
            for wide in [false, true] {
                let data = rows(rowCount, wide: wide)
                for (label, table) in tables(data: data) {
                    let context = makeRenderContext(width: width, height: height) { env, _ in
                        env.verticalScrollIndicatorVisibility = barVisibility
                        env.horizontalScrollIndicatorVisibility = barVisibility
                        env.scrollIndicatorPlacement = .besideContent
                    }

                    // The render ground truth, at the exact context shape the
                    // old render-based measure used (natural width).
                    var renderContext = context
                    renderContext.hasExplicitWidth = false
                    let buffer = renderToBuffer(table, context: renderContext)

                    let measured = measureChild(
                        table,
                        proposal: ProposedViewSize(width: width, height: height),
                        context: context)

                    #expect(
                        measured.width == buffer.width && measured.height == buffer.height,
                        """
                        \(label) rows=\(rowCount) wide=\(wide) \(width)x\(height) \
                        bar=\(barVisibility): measured \(measured.width)x\(measured.height) \
                        vs rendered \(buffer.width)x\(buffer.height)
                        """)
                }
            }
        }
    }

    @Test("The declined shape — overflowing with no bar — still measures equal")
    func declinedShapeStillMatches() {
        let data = rows(8, wide: true)
        let table = Table(data, selection: .constant(Int?.none)) {
            TableColumn("Name", value: \MeasureRow.name).lineLimit(3)
            TableColumn("Detail", value: \MeasureRow.detail)
        }
        let context = makeRenderContext(width: 40, height: 16)
        var renderContext = context
        renderContext.hasExplicitWidth = false
        let buffer = renderToBuffer(table, context: renderContext)
        let measured = measureChild(
            table, proposal: ProposedViewSize(width: 40, height: 16), context: context)
        #expect(measured.width == buffer.width && measured.height == buffer.height)
    }

    /// The multi-line counterpart of the sweep above.
    ///
    /// `analyticMultiLineSize` answers the bar-drawn and rows-fit shapes and
    /// returns `nil` for the third, so the render decides that one.
    /// Which of the two answered is invisible from out here, and that is the
    /// point: the sweep asserts the outer contract — measured == rendered —
    /// over a matrix that straddles the boundary in every direction (rows that
    /// fit and rows that overflow; every scrollbar visibility; short and tall
    /// terminals; wide values that wrap and narrow ones that don't; one
    /// multi-line column and several).
    ///
    /// The boundary is exactly where a fast path is dangerous — a table that
    /// fits at one width overflows at another, and the measure must not be the
    /// one to disagree.
    private func multiLineTables(
        data: [MeasureRow]
    ) -> [(label: String, table: AnyView)] {
        [
            (
                "one multi-line column",
                AnyView(
                    Table(data, selection: .constant(Int?.none)) {
                        TableColumn("Name", value: \MeasureRow.name).lineLimit(3)
                        TableColumn("Detail", value: \MeasureRow.detail)
                    })
            ),
            (
                "two multi-line columns",
                AnyView(
                    Table(data, selection: .constant(Int?.none)) {
                        TableColumn("Name", value: \MeasureRow.name).lineLimit(4)
                        TableColumn("Detail", value: \MeasureRow.detail).lineLimit(2)
                    })
            ),
            (
                "multi-line + fixed",
                AnyView(
                    Table(data, selection: .constant(Int?.none)) {
                        TableColumn("Name", value: \MeasureRow.name).lineLimit(3)
                            .width(12)
                        TableColumn("Detail", value: \MeasureRow.detail).width(.fit)
                    })
            ),
        ]
    }

    @Test(
        "Multi-line measure equals rendered size across the configuration matrix",
        arguments: [1, 2, 5, 20, 90], [ScrollIndicatorVisibility.automatic, .visible, .hidden])
    func multiLineMatchesRender(rowCount: Int, barVisibility: ScrollIndicatorVisibility) {
        for (width, height) in [(24, 9), (40, 12), (80, 24), (120, 43)] {
            for wide in [false, true] {
                let data = rows(rowCount, wide: wide)
                for (label, table) in multiLineTables(data: data) {
                    let context = makeRenderContext(width: width, height: height) { env, _ in
                        env.verticalScrollIndicatorVisibility = barVisibility
                        env.horizontalScrollIndicatorVisibility = barVisibility
                        env.scrollIndicatorPlacement = .besideContent
                    }
                    var renderContext = context
                    renderContext.hasExplicitWidth = false
                    let buffer = renderToBuffer(table, context: renderContext)
                    let measured = measureChild(
                        table,
                        proposal: ProposedViewSize(width: width, height: height),
                        context: context)

                    #expect(
                        measured.width == buffer.width && measured.height == buffer.height,
                        """
                        \(label) rows=\(rowCount) wide=\(wide) \(width)x\(height) \
                        bar=\(barVisibility): measured \(measured.width)x\(measured.height) \
                        vs rendered \(buffer.width)x\(buffer.height)
                        """)
                }
            }
        }
    }

    /// Which composer a table of the bar sweep below draws its rows with.
    enum BarLayout: CaseIterable, Sendable {
        case singleLine, multiLine, sectioned
    }

    /// A table of the bar sweep: `rowCount` rows on either composer, or in two
    /// sections (a sectioned table always takes the multi-line one).
    private func barTable(_ layout: BarLayout, data: [MeasureRow]) -> AnyView {
        switch layout {
        case .singleLine:
            return AnyView(
                Table(data, selection: .constant(Int?.none)) {
                    TableColumn("Name", value: \MeasureRow.name)
                    TableColumn("Detail", value: \MeasureRow.detail).width(10)
                })
        case .multiLine:
            return AnyView(
                Table(data, selection: .constant(Int?.none)) {
                    TableColumn("Name", value: \MeasureRow.name).lineLimit(3)
                    TableColumn("Detail", value: \MeasureRow.detail).width(10)
                })
        case .sectioned:
            let half = data.count / 2
            return AnyView(
                Table(of: MeasureRow.self, selection: .constant(Int?.none)) {
                    TableColumn("Name", value: \MeasureRow.name)
                    TableColumn("Detail", value: \MeasureRow.detail).width(10)
                } rows: {
                    Section("Fruits") { ForEach(Array(data[..<half])) { TableRow($0) } }
                    Section("Vegetables") { ForEach(Array(data[half...])) { TableRow($0) } }
                })
        }
    }

    /// TABLES-9: the bar was measured as one cell, and on the multi-line
    /// composer without the cells the rows keep clear of it — hidden while a
    /// header line, padded to the interior, set the width.
    @Test(
        "With a bar beside the rows, the measure equals the render at either bar width, headers shown or hidden",
        arguments: BarLayout.allCases, [Visibility.visible, .hidden])
    func barWidthsMatchRender(layout: BarLayout, headers: Visibility) {
        for barWidth in [1, 2] {
            for spacing in [0, 1, 2] {
                for (width, height) in [(30, 8), (60, 12)] {
                    let table = barTable(layout, data: rows(40))
                        .scrollIndicators(.visible)
                        .scrollbarWidth(barWidth)
                        .scrollbarSpacing(spacing)
                        .tableColumnHeaders(headers)
                    let context = makeRenderContext(width: width, height: height) { env, _ in
                        env.scrollIndicatorPlacement = .besideContent
                    }
                    var renderContext = context
                    renderContext.hasExplicitWidth = false
                    let buffer = renderToBuffer(table, context: renderContext)
                    let measured = measureChild(
                        table, proposal: ProposedViewSize(width: width, height: height), context: context)
                    #expect(
                        measured.width == buffer.width && measured.height == buffer.height,
                        """
                        \(layout) headers=\(headers) bar=\(barWidth) spacing=\(spacing) \(width)x\(height): \
                        measured \(measured.width)x\(measured.height) vs rendered \(buffer.width)x\(buffer.height)
                        \(buffer.lines.map(\.stripped).joined(separator: "\n"))
                        """)
                }
            }
        }
    }

    /// TABLES-2: a section header's lines joined the rows unpadded, so the
    /// bar's cell was drawn straight after the header's text.
    @Test(
        "A sectioned table's bar stands in one column on header lines and row lines alike",
        arguments: [1, 2], [Visibility.visible, .hidden])
    func sectionHeaderLinesReachTheBar(barWidth: Int, headers: Visibility) {
        // Twelve rows in a six-line table, the hunter's frame.
        let table = barTable(.sectioned, data: rows(12))
            .scrollIndicators(.visible)
            .scrollbarWidth(barWidth)
            .tableColumnHeaders(headers)
        let context = makeRenderContext(width: 30, height: 6) { env, _ in
            env.scrollIndicatorPlacement = .besideContent
        }
        let buffer = renderToBuffer(table, context: context)
        let lines = buffer.lines.map(\.stripped)
        let dump = lines.joined(separator: "\n")
        #expect(lines.contains { $0.contains("Fruits") }, "a header is on screen:\n\(dump)")
        // Every line as wide as the next, and the bar's top arrow — on the
        // header's line, the first the rows draw — in the column its bottom
        // arrow is in, on a row's line. Unpadded, the header's line put it
        // straight after "Fruits".
        #expect(Set(lines.map(\.count)).count == 1, "lines of one width:\n\(dump)")
        let header = lines.first { $0.contains("Fruits") }.map(Array.init) ?? []
        let last = lines.dropLast().last.map(Array.init) ?? []
        let up = header.firstIndex { "▲◢".contains($0) }
        let down = last.firstIndex { "▼◥".contains($0) }
        #expect(up != nil && up == down, "the bar stands in one column:\n\(dump)")
    }

    @Test("A tall budget — the extent ladder's case — still measures exactly")
    func laddersTallBudgetsMatchTheRender() {
        // `measureNaturalExtent` probes with budgets far past the content, and
        // that is precisely where the analytic path answers. Every rung must
        // agree with what rendering at that budget would produce.
        let data = rows(40, wide: true)
        for budget in [64, 256, 4096, 16_384] {
            for (label, table) in multiLineTables(data: data) {
                let context = makeRenderContext(width: 60, height: budget) { env, _ in
                    env.scrollIndicatorPlacement = .besideContent
                }
                var renderContext = context
                renderContext.hasExplicitWidth = false
                let buffer = renderToBuffer(table, context: renderContext)
                let measured = measureChild(
                    table, proposal: ProposedViewSize(width: 60, height: budget), context: context)
                #expect(
                    measured.width == buffer.width && measured.height == buffer.height,
                    """
                    \(label) budget=\(budget): measured \(measured.width)x\(measured.height) \
                    vs rendered \(buffer.width)x\(buffer.height)
                    """)
            }
        }
    }
}
