//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableRowInkTests.swift
//
//  A table row states its cells' ink once per run of plain cells, not once per
//  cell (decisions A-SPF-1), and draws exactly what the per-cell spelling drew.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitStyling
@testable import TUIkitTables
@testable import TUIkitTestSupport

@MainActor
@Suite("Table row ink")
struct TableRowInkTests {

    /// Deterministic, so a failure names a row that can be drawn again.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// What a cell's text can be: plain words, nothing at all (a wrapped row's line
    /// past a short cell's last), and text with escapes of its own — closed by a
    /// reset, left running, and an underline, whose ink a blank cell after it
    /// WOULD show if it ran on.
    private static let texts = [
        "alpha", "b", "gamma delta", "", "",
        "\u{1B}[1mbold\u{1B}[0m", "\u{1B}[4munder\u{1B}[24m", "\u{1B}[3mleft running",
        "\u{1B}[38;2;9;9;9mown ink\u{1B}[39m",
    ]

    private static let cellInk = Color.rgb(200, 180, 40)
    private static let markInk = Color.rgb(40, 120, 220)
    private static let fill = Color.rgb(30, 30, 60)

    /// One line of a row, as `Table` composes it: an optional mark and its gap,
    /// then the cells padded to their columns with spacing between them.
    private func compose(_ cells: [String], mark: String?, ink: TableRowInk) -> String {
        var ink = ink
        var content = ""
        if let mark {
            ink.appendMark(mark, in: Self.markInk, into: &content)
            content += " "
        }
        for (index, text) in cells.enumerated() {
            if index > 0 { content += "  " }
            ink.open(before: text, into: &content)
            content += text
            content += "   "
            ink.close(after: text, into: &content)
        }
        ink.finish(into: &content)
        return content
    }

    /// The cells' ink introducer at the depth in force.
    private func introducer() -> String? {
        var style = TextStyle()
        style.foregroundColor = Self.cellInk
        return ANSIRenderer.styleSequence(for: style)
    }

    /// Every column of `line` as it is seen, and the column after it: a bare glyph
    /// drawn after the row — a scroll bar's, a border's — must not take its ink.
    private func seen(_ line: String) -> [Seen] {
        paintedCells(line + "|").map { Seen(glyph: $0.glyph, state: $0.visibleState) }
    }

    private struct Seen: Equatable {
        let glyph: Character
        let state: SGRState
    }

    /// The paints a row is finished with, each with the close its ink takes under it.
    private func paints() -> [(name: String, close: String, paint: @MainActor (String) -> String)] {
        let reset = ANSIRenderer.reset
        let fixed = RowBackground.fixed(Self.fill)
        return [
            ("none", reset, { RowBackground.none.painting($0, padding: 2) }),
            ("still fill", ANSIRenderer.defaultForeground, { fixed.painting($0, padding: 2) }),
            ("breathing fill frame", reset, { RowBackground.Paint.fill(Self.fill).painting($0 + "  ") }),
            ("faint", reset, { ANSIRenderer.applyPersistentDim($0) }),
            ("faint on a still fill", ANSIRenderer.defaultForeground, {
                fixed.painting(ANSIRenderer.applyPersistentDim($0), padding: 2)
            }),
        ]
    }

    /// `TableRowInk` with `shares: false` is the spelling every table row used
    /// before decisions A-SPF-1 — the ink stated and closed around every cell and
    /// the mark — and the one a reversal still uses. Shared, the ink runs on across
    /// the blank cells between plain cells; every glyph keeps its ink and every cell
    /// its field, at every depth, under every paint a row is finished with, and with
    /// a cell's own escapes anywhere in the row.
    @Test(
        "A row that states its ink once per run draws every cell the per-cell spelling drew",
        arguments: [ColorDepth.truecolor, .palette256, .basic16, .noColor])
    func sharedInkDrawsWhatPerCellDrew(_ depth: ColorDepth) {
        ColorDepth.withCurrent(depth) {
            var random = SeededGenerator(state: 2026_10_07)
            let introducer = introducer()
            var saved = 0
            for paint in paints() {
                for trial in 0..<120 {
                    let count = Int.random(in: 0...6, using: &random)
                    let cells = (0..<count).map { _ in Self.texts.randomElement(using: &random) ?? "" }
                    let mark = [String?.none, " ", "●"][Int.random(in: 0...2, using: &random)]
                    let perCell = paint.paint(compose(
                        cells, mark: mark, ink: TableRowInk(introducer: introducer, close: paint.close, shares: false)))
                    let shared = paint.paint(compose(
                        cells, mark: mark, ink: TableRowInk(introducer: introducer, close: paint.close, shares: true)))
                    #expect(
                        seen(shared) == seen(perCell),
                        "\(paint.name) #\(trial): \(perCell.debugDescription) became \(shared.debugDescription)")
                    #expect(shared.utf8.count <= perCell.utf8.count, "\(paint.name) #\(trial)")
                    saved += perCell.utf8.count - shared.utf8.count
                }
            }
            if depth != .noColor { #expect(saved > 0, "nothing was saved at \(depth)") }
        }
    }

    /// Why a reversal keeps the close per run: under SGR 7 a cell's ink is the
    /// colour it is FILLED with, so the ink running on across a blank cell would
    /// fill it in the cells' ink rather than the reversal's own. Pinned so the
    /// exception cannot be dropped as an oversight.
    @Test("Under a reversal a shared ink would fill the blanks between cells, so a reversal keeps its closes")
    func reversalKeepsItsCloses() {
        ColorDepth.withCurrent(.truecolor) {
            let reversal = RowBackground.reversed(ink: Color.rgb(220, 220, 220), field: Color.rgb(20, 20, 30))
            #expect(!TableRowInk(introducer: introducer(), under: reversal, bandsAcrossRow: false).shares)
            let cells = ["alpha", "beta"]
            let perCell = reversal.painting(
                compose(cells, mark: "●", ink: TableRowInk(introducer: introducer(), close: ANSIRenderer.reset, shares: false)),
                padding: 2)
            let shared = reversal.painting(
                compose(cells, mark: "●", ink: TableRowInk(introducer: introducer(), close: ANSIRenderer.reset, shares: true)),
                padding: 2)
            #expect(seen(shared) != seen(perCell))
        }
    }

    /// What an ANCESTOR's reverse video does to a shared row — a `List` row, or a
    /// table row around a view cell, reversing a table nested in it where its
    /// palette's highlight cannot be measured. The nested row cannot see that
    /// reversal, so it shares its ink, and under SGR 7 a blank cell's ink is its
    /// fill: the spacing between its cells shows their ink and its blank marks the
    /// reversal's (decisions-SPF2 B-SPF2-2). Pinned: no glyph changes — every
    /// cell that draws one is in the state it was — only blank cells can differ,
    /// and they do; and a breathing reversal's reversed frame, which drops every
    /// colour of the row's own first, draws exactly what it drew.
    @Test(
        "Under an ancestor's reverse video only a shared row's blank cells differ",
        arguments: [ColorDepth.truecolor, .palette256, .basic16, .noColor])
    func ancestorReversalDiffersOnlyInBlankCells(_ depth: ColorDepth) {
        ColorDepth.withCurrent(depth) {
            var random = SeededGenerator(state: 2026_10_08)
            let introducer = introducer()
            let (ink, field) = (Color.rgb(220, 220, 220), Color.rgb(20, 20, 30))
            let exchanging = RowBackground.reversed(ink: ink, field: field)
            let pairOnly = RowBackground.Paint.reversed(ink: ink, field: field)
            var blanksDiffering = 0
            for trial in 0..<200 {
                let count = Int.random(in: 0...6, using: &random)
                let cells = (0..<count).map { _ in Self.texts.randomElement(using: &random) ?? "" }
                let mark = [String?.none, " ", "●"][Int.random(in: 0...2, using: &random)]
                let perCell = compose(
                    cells, mark: mark, ink: TableRowInk(introducer: introducer, close: ANSIRenderer.reset, shares: false))
                let shared = compose(
                    cells, mark: mark, ink: TableRowInk(introducer: introducer, close: ANSIRenderer.reset, shares: true))
                let before = seen(exchanging.painting(perCell))
                let after = seen(exchanging.painting(shared))
                #expect(before.map(\.glyph) == after.map(\.glyph), "#\(trial)")
                for (old, new) in zip(before, after) where old != new {
                    if old.glyph == " " {
                        blanksDiffering += 1
                    } else {
                        Issue.record("#\(trial): \(old.glyph) changed: \(perCell.debugDescription) became \(shared.debugDescription)")
                    }
                }
                #expect(
                    seen(pairOnly.painting(shared)) == seen(pairOnly.painting(perCell)),
                    "#\(trial): \(perCell.debugDescription) became \(shared.debugDescription)")
            }
            if depth != .noColor {
                #expect(blanksDiffering > 0, "an ancestor's reversal shows no blank cell's ink: update B-SPF2-2")
            }
        }
    }

    @Test("A row's background decides its ink's close and whether its runs share one introducer")
    func closeAndSharingFollowTheBackground() {
        let still = TableRowInk(introducer: "x", under: .fixed(Self.fill), bandsAcrossRow: false)
        #expect(still.close == ANSIRenderer.defaultForeground && still.shares)
        let bare = TableRowInk(introducer: "x", under: .none, bandsAcrossRow: false)
        #expect(bare.close == ANSIRenderer.reset && bare.shares)
        let banded = TableRowInk(introducer: nil, under: .fixed(Self.fill), bandsAcrossRow: true)
        #expect(!banded.shares, "a banded row paints cell by cell, its mark closed as before")
    }

    // MARK: - In a table

    private struct Row: Identifiable, Sendable {
        let id: Int
        let name: String
        let kind: String
        let size: String
    }

    private static let rows = (0..<4).map { Row(id: $0, name: "row\($0)", kind: "file", size: "\($0 * 10)") }

    /// The raw line holding `needle`.
    private func line(_ needle: String, in buffer: FrameBuffer) -> String {
        buffer.lines.first { $0.stripped.contains(needle) } ?? ""
    }

    private func count(_ needle: String, in line: String) -> Int {
        line.components(separatedBy: needle).count - 1
    }

    /// The cells' ink and its one close, wherever the row is plain — striped and
    /// unstriped, with a selection's blank mark before it — where every cell used
    /// to state and close it: three columns stated it three times.
    @Test("A plain table row states its cells' ink once and closes it once")
    func plainRowStatesItsInkOnce() throws {
        let table = Table(Self.rows, selection: .constant(Set<Int>())) {
            TableColumn("Name", value: \Row.name)
            TableColumn("Kind", value: \Row.kind)
            TableColumn("Size", value: \Row.size)
        }
        // Inset: no border, whose glyphs state escapes of their own on the line.
        let buffer = ColorDepth.withCurrent(.truecolor) {
            renderToBuffer(
                table.tableStyle(.inset).alternatingRowBackgrounds(.enabled), context: makeRenderContext(width: 40, height: 10))
        }
        for name in ["row1", "row2"] {
            let row = line(name, in: buffer)
            // One foreground introducer per row: the cells' — an unselected row's
            // blank mark states none — and one close: SGR 39 under the stripe
            // (row1), a reset where there is no fill (row2).
            #expect(count("\u{1B}[38;", in: row) == 1, "\(name) is \(row.debugDescription)")
            #expect(count("\u{1B}[0m", in: row) + count("\u{1B}[39m", in: row) == 1, "\(name) is \(row.debugDescription)")
        }
    }

    /// A table drawn inside a `List` row keeps the per-cell closes: the list's
    /// cursor row may reverse its content where the palette's highlight cannot be
    /// measured, and reverse video fills the blanks between cells with the ink in
    /// force (decisions B-SPF2-2). Every `List` row installs
    /// `\.listRowEditRestrictions`, so that is how the table knows.
    @Test("A table inside a List row states its cells' ink cell by cell, as before the ink was shared")
    func tableInsideAListRowDoesNotShare() throws {
        let table = Table(Self.rows, selection: .constant(Set<Int>())) {
            TableColumn("Name", value: \Row.name)
            TableColumn("Kind", value: \Row.kind)
            TableColumn("Size", value: \Row.size)
        }
        var context = makeRenderContext(width: 40, height: 10)
        context.environment.listRowEditRestrictions = RowEditRestrictions()
        let buffer = ColorDepth.withCurrent(.truecolor) {
            renderToBuffer(table.tableStyle(.inset), context: context)
        }
        // Cell by cell, as every row was before the ink was shared: the blank
        // selection mark states its colour and closes, and so does each of the
        // three cells (a shared row states one introducer and one close).
        let row = line("row2", in: buffer)
        #expect(count("\u{1B}[38;", in: row) == 4, "row2 is \(row.debugDescription)")
        #expect(count("\u{1B}[0m", in: row) == 4, "row2 is \(row.debugDescription)")
    }

    /// A styled cell closes with a reset, which its bold needs, and the cells after
    /// it state the ink again: the size column is drawn in the ink the name
    /// column is, not in the terminal's own colour the reset left in force.
    ///
    /// Read off the painted cells rather than counted in the bytes: the bold
    /// `Text` states its own foreground, so a count of introducers is met without
    /// the ink ever being stated again.
    @Test("A cell with escapes of its own is closed with a reset and the ink stated again after it")
    func styledCellClosesWithAReset() throws {
        let table = Table(Self.rows) {
            TableColumn("Name", value: \Row.name)
            TableColumn("Kind") { (row: Row) in Text(verbatim: row.kind).bold() }
            TableColumn("Size", value: \Row.size)
        }
        let buffer = ColorDepth.withCurrent(.truecolor) {
            renderToBuffer(
                table.tableStyle(.inset).alternatingRowBackgrounds(.disabled), context: makeRenderContext(width: 40, height: 10))
        }
        let row = line("row2", in: buffer)
        let cells = paintedCells(row)
        let size = try #require(cells.lastIndex { $0.glyph == "0" })
        let name = try #require(cells.firstIndex { $0.glyph == "r" })
        #expect(!cells[size].state.isBold, "the bold ran into the next cell: \(row.debugDescription)")
        #expect(cells[name].ink != nil, "the name is drawn in the cells' ink: \(row.debugDescription)")
        #expect(
            cells[size].ink == cells[name].ink,
            "the ink was not stated again after the bold cell's reset: \(row.debugDescription)")
    }
}
