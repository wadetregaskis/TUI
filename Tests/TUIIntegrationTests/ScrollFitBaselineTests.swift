//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollFitBaselineTests.swift
//
//  A characterization: what content-sized views and space-fillers get
//  along an axis their parent leaves unbounded (a `ScrollView`'s,
//  `.fixedSize`'s). Recorded as step 1 of the owner's SCROLL-FIT ruling
//  (2026-11-11), before it changed anything; the lanes that built it
//  updated these expectations on purpose, so each change shows as a row or a
//  test they edited, and P7, which turned SCROLL-FIT on, moved them to what
//  the ruling asks: content-sized views their content's height, fillers
//  their minimum. They stay as the pins of that behaviour. The step-1
//  findings are in `Documentation/Working notes/plan/SCROLL-FIT-baseline.md`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting
@testable import TUITestSupport

/// At 24-bit colour, as the table was recorded: without colour a scrollbar's
/// thumb is a glyph across whole cells rather than a fill with an eighth-cell
/// edge, so the screen's text holds still for more lines of the wheel, and the
/// walk stops at two unchanged screens before it reaches a two-stacked list's
/// last row. `swift test` sets `NO_COLOR` whenever its output is not a
/// terminal, which failed six `List` rows' reach there every time.
@MainActor
@Suite("SCROLL-FIT baseline: what content-sized views get along an unbounded axis", .drawsInTruecolor)
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

    /// Its rows' height since SCROLL-FIT P7, and pulled: it builds only the
    /// rows on screen and draws no bar of its own. (Capped at the scroll
    /// view's height by TABLE-IN-SCROLL-HEIGHT until P7: 59x24, scrolling its
    /// own rows, the page's title and what follows out of the keyboard's
    /// reach.)
    @Test("A 10,000-row table under a title is its rows' height and builds only the rows on screen")
    func tallTableUnderTitle() {
        let result = tall(.table, .underTitle)
        #expect(result.sizeA == CellSize(width: 59, height: 10_003))
        #expect(result.builtFirst < 150, "built \(result.builtFirst)")
        #expect(result.builtStep < 50, "a wheel step built \(result.builtStep)")
        #expect(!result.innerIndicator)
    }

    /// `.fixedSize` climbs the ladder (P5) and, at the window's root, draws
    /// only the lines its offer holds (P5b). (Before: 60x23, after building
    /// 4,153 rows to draw 20.)
    @Test("A 10,000-row table under .fixedSize is its rows' height and builds only the rows that show")
    func tallTableFixedSize() {
        let result = tall(.table, .fixedSize)
        #expect(result.sizeA == CellSize(width: 60, height: 10_003))
        #expect(result.builtFirst < 150, "built \(result.builtFirst)")
    }

    /// `ScrollView(.horizontal)` proposes its own height (A-SCROLLFIT-2): the
    /// table is framed to it and scrolls its own rows. (Before: 4,096 lines,
    /// 16,372 rows built on the first frame and 4,093 a wheel step; then
    /// 4,156 on the first frame, for its columns' widths read at the
    /// measuring ladder's first rung.)
    @Test("A 10,000-row table in a horizontal ScrollView is the view's height and scrolls its own rows")
    func tallTableHorizontal() {
        let result = tall(.table, .horizontal)
        #expect(result.sizeA?.height == 24)
        #expect(result.innerIndicator)
        #expect(result.builtStep < 50, "a wheel step built \(result.builtStep)")
        #expect(result.builtFirst < 100, "the first frame built \(result.builtFirst)")
    }

    /// Its content's height, pulled (P3). (Before P7: the 4,095 lines the
    /// measure ladder's first rung offered, some 4,000 of them blank, and
    /// 12,000 rows built on the first frame.)
    @Test("A 10,000-row List under a title is its rows' height and builds only the rows on screen")
    func tallListUnderTitle() {
        let result = tall(.listPlain, .underTitle)
        #expect(result.sizeA == CellSize(width: 59, height: 10_002))
        #expect(result.builtFirst < 150, "built \(result.builtFirst)")
        #expect(result.builtStep < 50, "a wheel step built \(result.builtStep)")
    }

    /// A lazy stack is pulled wherever it stands (SCROLL-FIT P2): it bands
    /// itself against the request the column above it hands it, and its first
    /// frame needs no total — the measuring walk that frame begins with draws
    /// down to the viewport's bottom only (design 1d). So the first frame and a
    /// wheel step each build about a screenful, alone or under a title. Its
    /// size, as `onGeometryChange` reads it, is its whole height (P5b; its
    /// band, 59x26, before P7). (Before P2: alone, 20,075 rows built on the
    /// first frame; under a title, drawn whole, 9 × 10,000 and 50,000+.)
    @Test("A 10,000-row LazyVStack at the scroll content's origin builds a screenful on its first frame and a step")
    func tallLazyStackAlone() {
        let result = tall(.lazyVStack, .alone)
        #expect(result.sizeA == CellSize(width: 59, height: 10_000))
        #expect(result.builtFirst < 150, "built \(result.builtFirst)")
        #expect(result.builtStep < 50, "a wheel step built \(result.builtStep)")
    }

    @Test("A 10,000-row LazyVStack under a title is pulled: a screenful on its first frame and a step")
    func tallLazyStackUnderTitle() {
        let result = tall(.lazyVStack, .underTitle)
        #expect(result.sizeA == CellSize(width: 59, height: 10_000))
        #expect(result.builtFirst < 150, "built \(result.builtFirst)")
        #expect(result.builtStep < 50, "a wheel step built \(result.builtStep)")
    }

    /// SCROLL-FIT P8 (A-SCROLLFIT-5 (a)): a flow of 10,000 items measures
    /// every one on its first frame, to break its lines from the top, and is
    /// drawn as a lazy stack of those lines, so a wheel step builds only the
    /// items of the lines on screen: the items' data is equatable, and their
    /// measures are kept. Each line on screen draws its items afresh, about
    /// 150 at 60 × 24, where a lazy stack's rows are served from the memo.
    /// (Before P8, the first frame built 80,000 rows, and every frame after
    /// measured them all again.)
    @Test("A 10,000-item FlowLayout under a title builds a screenful of items for a wheel step")
    func tallFlowLayoutUnderTitle() {
        let result = tall(.flowLayout, .underTitle)
        #expect(result.builtStep < 250, "a wheel step built \(result.builtStep)")
        #expect(result.builtFirst < 40_000, "built \(result.builtFirst)")
    }

    /// Its text's height, pulled (P4). (Before P7: content-sized up to the
    /// ladder's first rung, 4,095 lines, then scrolling itself.)
    @Test("A 10,000-line TextEditor under a title is its text's height")
    func tallTextEditorUnderTitle() {
        #expect(tall(.textEditor, .underTitle).sizeA == CellSize(width: 59, height: 10_000))
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

    /// The table, focused at launch, is its rows' height and the page's to
    /// scroll (P7): the title stays on line 0 (the arrival reveal, P6), the
    /// keys move its cursor and the page follows it, its header pinned over
    /// the viewport's top while its rows are under it. (Before P7 the table
    /// was the screen's height and the reveal scrolled the title away; the
    /// keys moved its rows inside it, and the page never moved.)
    @Test("Keys in a tall Table under a title move the page to the cursor; its header stays pinned")
    func keysInTallTable() {
        let app = tallUnderTitle(table: true, selection: ScrollFitSelection())
        #expect(app.focusedID?.hasPrefix("table-") == true)
        #expect(app.screen.lines[0].contains("title"), "first frame:\n\(app.screen)")
        func pinned(_ step: String, shows row: String) {
            #expect(app.screen.contains(row), "\(step):\n\(app.screen)")
            #expect(app.screen.lines[0].contains("Name"), "\(step): the header pinned\n\(app.screen)")
        }
        _ = app.press(.down, times: 31)
        pinned("down 31", shows: "r32")
        _ = app.press(.pageDown)
        pinned("page down", shows: "r52")
        _ = app.press(.end)
        pinned("end", shows: "r60")
        _ = app.press(.home)
        app.type("r45")
        pinned("type-select r45", shows: "r45")
    }

    /// The list is its rows' height (P7), the page following its cursor; past
    /// its last row the wheel reaches the line after it, not the four
    /// thousand blank lines it was offered before.
    @Test("Keys in a tall List under a title move the page to the cursor; the line after it follows its rows")
    func keysInTallList() {
        let app = tallUnderTitle(table: false, selection: ScrollFitSelection())
        #expect(app.focusedID?.hasPrefix("list-") == true)
        #expect(app.screen.lines[0].contains("title"), "\(app.screen)")
        _ = app.press(.down, times: 31)
        #expect(app.screen.contains("r32"), "\(app.screen)")
        _ = app.press(.end)
        #expect(app.screen.contains("r60"), "\(app.screen)")
        _ = app.press(.home)
        app.type("r45")
        #expect(app.screen.contains("r45"), "\(app.screen)")
        app.scroll(.down, by: 200, at: CellPoint(x: 30, y: 12))
        #expect(app.screen.contains("after") && app.screen.contains("r60"), "\(app.screen)")
    }
}
