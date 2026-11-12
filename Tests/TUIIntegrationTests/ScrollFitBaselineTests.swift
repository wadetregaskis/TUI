//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollFitBaselineTests.swift
//
//  A characterization, not a specification: what content-sized views and
//  space-fillers get today along an axis their parent leaves unbounded (a
//  `ScrollView`'s, `.fixedSize`'s), before the owner's SCROLL-FIT ruling
//  (2026-11-11) changes it. Step 1 of that ruling: the lanes that build it
//  (windowing anywhere in scroll content; content-sized defaults with a
//  pinned header, a pinned horizontal bar and keyboard reveal) update these
//  expectations on purpose, so each change they make shows here as a row
//  they edited. The findings are written up in
//  `Documentation/Working notes/plan/SCROLL-FIT-baseline.md`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting

@MainActor
@Suite("SCROLL-FIT baseline: what content-sized views get along an unbounded axis today")
struct ScrollFitBaselineTests {
    // MARK: - The table, at 3 and 60 rows

    @Test("Size, own bar and reach, as the baseline table records", arguments: ScrollFitBaseline.rows)
    func baseline(_ row: ScrollFitBaselineRow) {
        let result = ScrollFitMeasure.measure(row.subject, row.situation, rows: row.rows)
        func size(_ size: CellSize?) -> String { size.map { "\($0.width)x\($0.height)" } ?? "-" }
        #expect(size(result.sizeA) == row.sizeA, "\(result.screen)")
        #expect(size(result.sizeB) == row.sizeB, "\(result.screen)")
        let reached =
            row.situation == .twoStacked
            ? "\(result.reachedA ? "Y" : "n")\(result.reachedB ? "Y" : "n")" : (result.reachedA ? "Y" : "n")
        #expect(reached == row.reached, "\(result.screen)")
        #expect(result.innerIndicator == row.ownBar, "\(result.screen)")
    }

    // MARK: - 10,000 rows: height and rows built

    /// The first frame only (no wheel walk: some of these build every row on
    /// every frame, and a walk took minutes).
    private func tall(_ subject: ScrollFitSubject, _ situation: ScrollFitSituation) -> ScrollFitResult {
        ScrollFitMeasure.measure(subject, situation, rows: 10_000, walk: false)
    }

    /// Capped at the scroll view's height since TABLE-IN-SCROLL-HEIGHT, a
    /// tall table scrolls its own rows and builds only those it shows.
    @Test("A 10,000-row table under a title is the viewport's height and builds only its visible rows")
    func tallTableUnderTitle() {
        let result = tall(.table, .underTitle)
        #expect(result.sizeA == CellSize(width: 59, height: 24))
        #expect(result.builtFirst < 300, "built \(result.builtFirst)")
        #expect(result.innerIndicator)
    }

    /// `.fixedSize` makes no cap: the table measures its rows, up to the
    /// measure ladder's first rung (4,096 lines), and then takes the height
    /// left, so it builds thousands of rows to draw 20.
    @Test("A 10,000-row table under .fixedSize builds the ladder's first rung to show the screen's height")
    func tallTableFixedSize() {
        let result = tall(.table, .fixedSize)
        #expect(result.sizeA == CellSize(width: 60, height: 23))
        #expect(result.builtFirst > 4_000, "built \(result.builtFirst)")
    }

    /// The cap reads a vertical scroll view's viewport; `ScrollView(.horizontal)`,
    /// which still scrolls vertically here, gives the table none.
    @Test("A 10,000-row table in a horizontal ScrollView is 4,096 lines and builds them all")
    func tallTableHorizontal() {
        let result = tall(.table, .horizontal)
        #expect(result.sizeA == CellSize(width: 59, height: 4_096))
        #expect(result.builtFirst > 16_000, "built \(result.builtFirst)")
    }

    /// A `List` takes the height it is offered, and a scroll view's content
    /// is offered the ladder's first rung: 4,096 lines, whatever its rows.
    @Test("A 10,000-row List under a title is 4,095 lines and builds that many rows on the first frame")
    func tallListUnderTitle() {
        let result = tall(.listPlain, .underTitle)
        #expect(result.sizeA == CellSize(width: 59, height: 4_095))
        #expect(result.builtFirst > 16_000, "built \(result.builtFirst)")
        #expect(result.builtStep < 50, "a wheel step built \(result.builtStep)")
    }

    /// At the scroll content's origin a lazy stack consumes the scroll
    /// window: a wheel step builds a handful of rows, but the first frame
    /// builds every row twice.
    @Test("A 10,000-row LazyVStack at the scroll content's origin windows its steps but not its first frame")
    func tallLazyStackAlone() {
        let result = tall(.lazyVStack, .alone)
        #expect(result.sizeA == CellSize(width: 59, height: 26))
        #expect(result.builtFirst >= 20_000, "built \(result.builtFirst)")
        #expect(result.builtStep < 50, "a wheel step built \(result.builtStep)")
    }

    /// Below a title it is not at the origin, so it consumes no window and is
    /// drawn whole.
    @Test("A 10,000-row LazyVStack under a title is drawn whole")
    func tallLazyStackUnderTitle() {
        let result = tall(.lazyVStack, .underTitle)
        #expect(result.sizeA == CellSize(width: 9, height: 10_000))
        #expect(result.builtFirst >= 50_000, "built \(result.builtFirst)")
    }

    /// Content-sized up to the ladder's first rung, then the height offered.
    @Test("A 10,000-line TextEditor under a title is 4,095 lines")
    func tallTextEditorUnderTitle() {
        #expect(tall(.textEditor, .underTitle).sizeA == CellSize(width: 59, height: 4_095))
    }

    // MARK: - Keys in a tall Table and List under a title

    private func tallUnderTitle(table: Bool, selection: ScrollFitSelection) -> TestApp {
        let data = ScrollFitCatalogue.items("r", 60)
        let binding = Binding<Int?>(get: { selection.value }, set: { selection.value = $0 })
        return TestApp(width: 60, height: 24) {
            ScrollView {
                VStack {
                    Text("title")
                    if table {
                        Table(data, selection: binding) {
                            TableColumn("Name") { (item: ScrollFitItem) in Text(item.label) }.width(20)
                            TableColumn("Alpha") { (item: ScrollFitItem) in Text("alpha-\(item.id)") }.width(20)
                            TableColumn("Beta") { (item: ScrollFitItem) in Text("beta-\(item.id)") }.width(20)
                            TableColumn("Gamma") { (item: ScrollFitItem) in Text("gamma-\(item.id)") }.width(20)
                        }
                    } else {
                        List(data, selection: binding) { Text($0.label) }
                    }
                    Text("after")
                }
            }
        }
    }

    /// The table, focused at launch, is revealed: the page scrolls one line,
    /// past the title. It is the screen's height, its header on line 1 and its
    /// horizontal bar on line 22, and the keys move its cursor through its own
    /// rows; the page never moves, so the title and the line after the table
    /// stay out of sight.
    @Test("Keys in a tall Table under a title scroll the table's rows; its header and bar stay put")
    func keysInTallTable() {
        let app = tallUnderTitle(table: true, selection: ScrollFitSelection())
        func pinned(_ step: String) {
            let lines = app.screen.lines
            #expect(lines[0].contains("╭") && lines[1].contains("Name"), "\(step):\n\(app.screen)")
            #expect(lines[22].contains("◀") && lines[23].contains("╰"), "\(step):\n\(app.screen)")
            #expect(!app.screen.contains("title") && !app.screen.contains("after"), "\(step):\n\(app.screen)")
        }
        #expect(app.focusedID?.hasPrefix("table-") == true)
        pinned("first frame")
        _ = app.press(.down, times: 31)
        pinned("down 31")
        #expect(app.screen.lines[21].contains("r32"), "\(app.screen)")
        _ = app.press(.pageDown)
        pinned("page down")
        #expect(app.screen.lines[21].contains("r52"), "\(app.screen)")
        _ = app.press(.end)
        pinned("end")
        #expect(app.screen.lines[21].contains("r60"), "\(app.screen)")
        _ = app.press(.home)
        app.type("r45")
        pinned("type-select r45")
        #expect(app.screen.lines[21].contains("r45"), "\(app.screen)")
    }

    /// The list is 4,095 lines (see `tallListUnderTitle`): the outer page
    /// scrolls to keep its cursor on screen, and past its last row are some
    /// four thousand blank lines the wheel reaches.
    @Test("Keys in a tall List under a title move the page to the cursor; blank lines follow its rows")
    func keysInTallList() {
        let app = tallUnderTitle(table: false, selection: ScrollFitSelection())
        #expect(app.focusedID?.hasPrefix("list-") == true)
        #expect(app.screen.lines[0].contains("╭") && !app.screen.contains("title"), "\(app.screen)")
        _ = app.press(.down, times: 31)
        #expect(app.screen.lines[23].contains("r32"), "\(app.screen)")
        _ = app.press(.end)
        #expect(app.screen.lines[23].contains("r60"), "\(app.screen)")
        _ = app.press(.home)
        app.type("r45")
        #expect(app.screen.lines[23].contains("r45"), "\(app.screen)")
        app.scroll(.down, by: 200, at: CellPoint(x: 30, y: 12))
        #expect(app.screen.lines.allSatisfy { !$0.contains { $0.isNumber } }, "\(app.screen)")
    }
}
