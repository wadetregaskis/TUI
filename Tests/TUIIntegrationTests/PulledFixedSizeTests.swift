//  🖥️ TUI — A Terminal UI framework for Swift
//  PulledFixedSizeTests.swift
//
//  SCROLL-FIT P5 (design 2f, B-SCROLLFIT-8):
//  `.fixedSize` measures its content
//  down the scroll view's ladder rather than once at the ladder's first rung,
//  so content taller than that rung is its own height rather than the height
//  it is offered. In scroll content such a table is pulled — only the rows on
//  screen are built — and draws what the same table drawn whole draws; outside
//  a scroll view there is no viewport to pull against, and it is drawn whole.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting

/// Counts cells built, and keeps the content height the scroll view reports.
@MainActor private final class FixedSizeProbe {
    var built = 0
    var contentHeight = 0
}

private struct Entry: Identifiable {
    let id: Int
}

/// A title and a table under `.fixedSize(horizontal: false, vertical: true)`
/// in a scroll view, a button below them — or the twin: the
/// same table drawn whole, framed to its full height.
private struct FixedSizeTablePage: View {
    let entries: [Entry]
    let probe: FixedSizeProbe
    var pulled = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("title")
                    if pulled { table } else { table.frame(height: entries.count + 3) }
                }
                .fixedSize(horizontal: false, vertical: true)
                Button("below") {}
            }
        }
        .onScrollGeometryChange(
            for: Int.self, of: { $0.contentSize.height }, action: { _, height in probe.contentHeight = height })
    }

    private var table: some View {
        Table(entries) {
            TableColumn("Row") { (entry: Entry) in
                probe.built += 1
                return Text(verbatim: "r\(entry.id)")
            }
        }
    }
}

@MainActor
@Suite("SCROLL-FIT P5: .fixedSize climbs the ladder; in scroll content its table is pulled")
struct PulledFixedSizeTests {
    private static func app(_ count: Int, probe: FixedSizeProbe = FixedSizeProbe(), pulled: Bool = true) -> TestApp {
        TestApp(width: 30, height: 12) {
            FixedSizeTablePage(entries: (0..<count).map(Entry.init), probe: probe, pulled: pulled)
                .environment(\.scrollChainingDelay, .zero)
        }
    }

    /// The screen's lines without the scroll view's bar.
    private static func content(_ app: TestApp) -> [String] {
        app.screen.lines.map { String(($0 + String(repeating: " ", count: 30)).prefix(28)) }
    }

    // MARK: - In scroll content

    /// Its header pinned over the top line while its rows are under it
    /// (SCROLL-FIT P6, `PulledTableTwin`).
    @Test("The table draws what the same table drawn whole draws: top, wheeled, cursor moved, at the end and home")
    func drawsWhatTheWholeTableDraws() {
        let pulled = Self.app(300)
        let whole = Self.app(300, pulled: false)
        let header = Self.content(pulled)[2]
        func check(_ step: String) {
            #expect(
                PulledTableTwin.matches(Self.content(pulled), Self.content(whole), header: header),
                "\(step):\n\(pulled.screen)\n---\n\(whole.screen)")
        }
        check("top")
        for step in 1...4 {
            pulled.scroll(.down, by: 2, at: CellPoint(x: 5, y: 5))
            whole.scroll(.down, by: 2, at: CellPoint(x: 5, y: 5))
            check("wheel \(step)")
        }
        pulled.scroll(.down, by: 30, at: CellPoint(x: 5, y: 5))
        whole.scroll(.down, by: 30, at: CellPoint(x: 5, y: 5))
        check("wheel burst")
        _ = pulled.press(.tab)
        _ = whole.press(.tab)
        check("tab")
        for step in 1...14 {
            _ = pulled.press(.down)
            _ = whole.press(.down)
            check("down \(step)")
        }
        _ = pulled.press(.end)
        _ = whole.press(.end)
        check("end")
        _ = pulled.press(.home)
        _ = whole.press(.home)
        check("home")
    }

    /// The cells built on the first frame, three wheel steps, two cursor
    /// pages and End.
    private static func builtPerStep(rows: Int) -> (built: [Int], contentHeight: Int) {
        let probe = FixedSizeProbe()
        let app = app(rows, probe: probe)
        _ = app.screen
        var counts = [probe.built]
        func step(_ action: () -> Void) {
            probe.built = 0
            action()
            counts.append(probe.built)
        }
        for _ in 0..<3 { step { app.scroll(.down, by: 3, at: CellPoint(x: 5, y: 5)) } }
        _ = app.press(.tab)
        for _ in 0..<2 { step { _ = app.press(.pageDown) } }
        step { _ = app.press(.end) }
        return (counts, probe.contentHeight)
    }

    /// The content is the title, the table's rows, header and borders, and
    /// the button: 10,005 lines at 10,000 rows, as many as there are.
    @Test("At 10,000 rows the table is its rows' height, and the rows built a frame are under 100, as at 1,000")
    func tallTableIsItsRowsHeight() {
        let small = Self.builtPerStep(rows: 1_000)
        #expect(small.built.allSatisfy { $0 < 100 }, "\(small.built)")
        let tall = Self.builtPerStep(rows: 10_000)
        #expect(tall.built == small.built)
        #expect(tall.contentHeight == 10_005, "\(tall.contentHeight)")
    }

    /// Past the first rung `.fixedSize` measured at (64 screens of the 4,096
    /// lines it was offered there: 262,144), its content was the height it was
    /// offered, and the rows past it out of reach.
    @Test("At 300,000 rows, past the ladder's first rung, the table is its rows' height and End reaches the last")
    func tableTallerThanTheFirstRung() {
        let probe = FixedSizeProbe()
        let app = Self.app(300_000, probe: probe)
        _ = app.screen
        #expect(probe.contentHeight == 300_005, "\(probe.contentHeight)")
        _ = app.press(.tab)
        probe.built = 0
        _ = app.press(.end)
        #expect(app.screen.contains("r299999"), "\(app.screen)")
        #expect(probe.built < 100, "built \(probe.built)")
    }

    // MARK: - Outside a scroll view (the baseline's `.fixedSize` situation)

    private static func fixedSize(
        _ subject: ScrollFitSubject, rows: Int, situation: ScrollFitSituation = .fixedSize
    ) -> ScrollFitResult {
        ScrollFitMeasure.measure(subject, situation, rows: rows, walk: false)
    }

    /// Off, the table was the screen's height left under the title after
    /// laying out the 4,096 rows of the first rung (`tallTableFixedSize`).
    /// On, it is its rows' height (design 2f); the window shows its first 23
    /// lines, and only the rows in them are built (P5b): drawn whole, it built
    /// 24,093 rows on the first frame and 10,000 on each wheel step, which
    /// moves nothing. A frame draws the rows on screen again, as any frame of
    /// a table whose columns compute their values does (its rows are kept
    /// across frames only where every column names a property), in a scroll
    /// view too.
    @Test("Outside a scroll view a 10,000-row table under .fixedSize is its rows' height, and builds the rows that show")
    func tallTableOutsideAScrollView() {
        let result = Self.fixedSize(.table, rows: 10_000)
        #expect(result.sizeA == CellSize(width: 60, height: 10_003), "\(result)")
        #expect(result.builtFirst < 100, "\(result)")
        #expect(result.builtStep <= 23, "\(result)")
    }

    /// `VStack { title; table }.fixedSize(horizontal: false, vertical: true)`
    /// as the window's root — or the twin: the same table framed to its full
    /// height, given a height and so drawn whole.
    private struct RootPage: View {
        let rows: Int
        var framed = false

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("title")
                if framed { table.frame(height: rows + 3) } else { table }
            }
            .fixedSize(horizontal: false, vertical: true)
        }

        private var table: some View {
            Table((0..<rows).map(Entry.init)) {
                TableColumn("Row") { (entry: Entry) in Text(verbatim: "r\(entry.id)") }
            }
        }
    }

    /// What shows is the top of the table drawn whole, and stays so as the
    /// cursor moves, though the window shows none of the rows it moves to.
    @Test("Outside a scroll view the table shows what the same table drawn whole shows")
    func showsTheWholeTablesTop() {
        let pulled = TestApp(width: 30, height: 12) { RootPage(rows: 300) }
        let whole = TestApp(width: 30, height: 12) { RootPage(rows: 300, framed: true) }
        #expect(pulled.screen.lines == whole.screen.lines, "\(pulled.screen)\n---\n\(whole.screen)")
        for step in 1...3 {
            _ = pulled.press(.tab)
            _ = whole.press(.tab)
            _ = pulled.press(.down, times: 4)
            _ = whole.press(.down, times: 4)
            pulled.scroll(.down, by: 2, at: CellPoint(x: 5, y: 5))
            whole.scroll(.down, by: 2, at: CellPoint(x: 5, y: 5))
            #expect(pulled.screen.lines == whole.screen.lines, "step \(step):\n\(pulled.screen)\n---\n\(whole.screen)")
        }
    }

    /// A frame shorter than the content draws it past its edges, offering it
    /// its whole height (`ownSizePastOffer`), and places it by its alignment:
    /// here its bottom, the table's last rows. All of it can show, so all of
    /// it is drawn.
    @Test("A frame that draws the content past its edges, by its bottom, shows the table's last rows")
    func framePlacesItWhole() {
        let app = TestApp(width: 30, height: 12) {
            RootPage(rows: 300).frame(height: 12, alignment: .bottom)
        }
        #expect(app.screen.contains("r299"), "\(app.screen)")
    }

    @Test("A table of 3 or 60 rows under .fixedSize is as the baseline has it", arguments: [(3, 6), (60, 63)])
    func shortTablesUnchanged(_ rows: Int, _ height: Int) {
        #expect(Self.fixedSize(.table, rows: rows).sizeA == CellSize(width: 60, height: height))
    }

    /// The views the baseline found already content-sized under `.fixedSize`
    /// (60 rows: 60 lines and their chrome) were the screen's height at 10,000.
    /// Not among them: the views that answer the height they are offered, up
    /// to their content, and say they are flexible — `TextEditor`, a nested
    /// `ScrollView`, a grouped `Form`, the split views — which are content-sized
    /// since P7 (`ContentSizedOfferedNoneTests`).
    @Test(
        "Content-sized views under .fixedSize are their content's height at 10,000 rows",
        arguments: [
            // Pulled, from the window's top (P5b): its band drawn the width it
            // is offered, as a pulled lazy stack's is in a scroll view.
            (ScrollFitSubject.lazyVStack, CellSize(width: 60, height: 10_000)),
            (.groupBox, CellSize(width: 13, height: 10_003)),
            (.grid, CellSize(width: 14, height: 10_000)),
            (.tabView, CellSize(width: 9, height: 10_001)),
            (.flowLayout, CellSize(width: 60, height: 1_641)),
        ])
    func contentSizedViewsAreTheirContent(_ subject: ScrollFitSubject, _ size: CellSize) {
        #expect(Self.fixedSize(subject, rows: 10_000).sizeA == size)
    }

    /// A `List` is its content's height too since P7, which it answers asked
    /// for no height (`ContentSizedOfferedNoneTests`); until then it said it
    /// filled what it was offered, and kept the screen's height.
    @Test("A List under .fixedSize is its content's height, at 60 and 10,000 rows", arguments: [60, 10_000])
    func listIsItsContentsHeight(_ rows: Int) {
        #expect(Self.fixedSize(.listPlain, rows: rows).sizeA == CellSize(width: 60, height: rows + 2))
    }

    // MARK: - Fillers (B-SCROLLFIT-7)

    /// Off, a `GeometryReader` took the ladder's rung: 4,096 blank lines in a
    /// scroll view, and under `.fixedSize` the screen's height left under the
    /// title. On, offered no height it is its minimum, as a `Color` is, so it
    /// comes out as tall as a `Color` does wherever the baseline puts one
    /// (no lines in a vertical scroll view, which draws its content at its
    /// own height since P7; the viewport's in a horizontal one).
    @Test(
        "A GeometryReader offered no height is its minimum, as a Color is",
        arguments: [ScrollFitSituation.alone, .underTitle, .twoStacked, .fixedSize, .horizontal])
    func geometryReaderIsItsMinimum(_ situation: ScrollFitSituation) {
        let reader = ScrollFitMeasure.measure(.geometryReader, situation, rows: 3, walk: false)
        let color = ScrollFitMeasure.measure(.color, situation, rows: 3, walk: false)
        // Heights: a reader fills the width it is laid out at, where a
        // `Color` in a column fixed to its ideal width is none wide.
        #expect(reader.sizeA?.height == color.sizeA?.height, "\(reader) against \(color)")
        #expect(reader.sizeB?.height == color.sizeB?.height, "\(reader) against \(color)")
    }

    @Test("Under .fixedSize a GeometryReader is no lines tall, and a frame filling its height is its content's")
    func fillersUnderFixedSize() {
        #expect(Self.fixedSize(.geometryReader, rows: 3).sizeA == CellSize(width: 60, height: 0))
        #expect(Self.fixedSize(.maxHeightText, rows: 3).sizeA == CellSize(width: 4, height: 1))
    }

    /// Given a height, it fills it as before: the minimum is only the answer
    /// to "how tall with nothing to stop it".
    @Test("Given a height, a GeometryReader fills it")
    func geometryReaderFillsAHeight() {
        var size: CellSize?
        let app = TestApp(width: 30, height: 10) {
            VStack(spacing: 0) {
                Text("title")
                GeometryReader { proxy in Text(verbatim: "\(proxy.size.height)") }
                    .onGeometryChange(for: CellSize.self, of: { $0.size }, action: { size = $0 })
            }
        }
        _ = app.screen
        #expect(size == CellSize(width: 30, height: 9), "\(String(describing: size))")
    }
}
