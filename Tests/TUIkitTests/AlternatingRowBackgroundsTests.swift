//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AlternatingRowBackgroundsTests.swift
//
//  `.alternatingRowBackgrounds(_:)`: every other row of a table or a list
//  takes the stripe tint, and only when the behavior asks for it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Alternating row backgrounds")
struct AlternatingRowBackgroundsTests {

    private struct Row: Identifiable, Sendable, Equatable {
        let id: Int
        let name: String
    }

    private static let rows = (0..<4).map { Row(id: $0, name: "row\($0)") }

    /// The raw line holding `needle`.
    private func line(_ needle: String, in buffer: FrameBuffer) -> String {
        buffer.lines.first { $0.stripped.contains(needle) } ?? ""
    }

    /// Whether a line paints a background colour.
    private func paintsBackground(_ line: String) -> Bool {
        line.contains("\u{1B}[48;")
    }

    private func table(_ behavior: AlternatingRowBackgroundBehavior?) -> FrameBuffer {
        let table = Table(Self.rows) { TableColumn("Name", value: \Row.name) }
        let context = makeRenderContext(width: 30, height: 10)
        guard let behavior else { return renderToBuffer(table, context: context) }
        return renderToBuffer(table.alternatingRowBackgrounds(behavior), context: context)
    }

    // Row 0 is the cursor row of a focused table, which wears the focus wash
    // whatever the stripes do, so the rows below it are the ones that tell.

    // The phase is macOS's, measured: the second row is the first tinted
    // (the `stripe` of `Table`'s `RowPaint`, in Table.swift, says where).

    @Test("A striped table tints every other row, from the second")
    func tableStripes() {
        let buffer = table(.enabled)
        #expect(paintsBackground(line("row1", in: buffer)))
        #expect(!paintsBackground(line("row2", in: buffer)))
        #expect(paintsBackground(line("row3", in: buffer)))
    }

    @Test("A table stripes by default, as a macOS table does (decisions A29)", arguments: [
        AlternatingRowBackgroundBehavior?.none, .automatic,
    ])
    func tableStripesByDefault(_ behavior: AlternatingRowBackgroundBehavior?) {
        let buffer = table(behavior)
        #expect(paintsBackground(line("row1", in: buffer)))
        #expect(!paintsBackground(line("row2", in: buffer)))
        #expect(paintsBackground(line("row3", in: buffer)))
    }

    @Test("A table stripes under every built-in style")
    func tableStripesUnderEveryStyle() {
        let context = makeRenderContext(width: 30, height: 10)
        let base = Table(Self.rows) { TableColumn("Name", value: \Row.name) }
        for buffer in [
            renderToBuffer(base.tableStyle(.inset), context: context),
            renderToBuffer(base.tableStyle(.bordered), context: context),
        ] {
            #expect(paintsBackground(line("row1", in: buffer)))
            #expect(!paintsBackground(line("row2", in: buffer)))
        }
    }

    @Test("A table on a surface stripes over the surface, not over the page")
    func stripesOverTheSurfaceItSitsOn() throws {
        var context = makeRenderContext(width: 30, height: 10)
        let palette = context.environment.palette
        // What a `TabView`'s body publishes for its content.
        let surface = context.environment.liftedSurface
        let expected = try #require(palette.stripeFill(over: surface))
        let overPage = try #require(palette.stripeFill(over: palette.background))
        try #require(expected != overPage, "the test palette cannot tell the two grounds apart")
        context.environment.surfaceBackground = surface
        let buffer = renderToBuffer(Table(Self.rows) { TableColumn("Name", value: \Row.name) }, context: context)
        let striped = line("row1", in: buffer)
        #expect(striped.contains(expected.backgroundEscape()), "row1 is \(striped.debugDescription)")
    }

    @Test("A table told not to stripe draws no stripes")
    func tableUnstripedWhenDisabled() {
        let buffer = table(.disabled)
        #expect(Self.rows.dropFirst().allSatisfy { !paintsBackground(line($0.name, in: buffer)) })
    }

    @Test("The modifier's default is enabled")
    func defaultArgumentEnables() {
        let buffer = renderToBuffer(
            Table(Self.rows) { TableColumn("Name", value: \Row.name) }.alternatingRowBackgrounds(),
            context: makeRenderContext(width: 30, height: 10))
        #expect(paintsBackground(line("row1", in: buffer)))
    }

    @Test("A striped list tints every other row as a striped table does")
    func listStripes() {
        let list = List(Self.rows) { row in Text(row.name) }
        let context = makeRenderContext(width: 30, height: 10)
        let striped = renderToBuffer(list.alternatingRowBackgrounds(), context: context)
        #expect(paintsBackground(line("row1", in: striped)))
        #expect(!paintsBackground(line("row2", in: striped)))
        // A list keeps macOS's answer: no stripes unless asked (decisions A46).
        let plain = renderToBuffer(list, context: context)
        #expect(!paintsBackground(line("row1", in: plain)))
        let automatic = renderToBuffer(list.alternatingRowBackgrounds(.automatic), context: context)
        #expect(!paintsBackground(line("row1", in: automatic)))
    }

    @Test("A kept row that moves to the other parity is repainted, not composed again")
    func parityMoveRepaints() throws {
        var rows = Self.rows
        let context = makeRenderContext(width: 30, height: 10)
        let cache = try #require(context.renderCache)
        func frame() -> FrameBuffer {
            renderToBuffer(Table(rows) { TableColumn("Name", value: \Row.name) }, context: context)
        }
        for _ in 0..<3 { _ = frame() }
        // A newest-first log gaining an entry: every kept row moves one down,
        // to the other parity.
        rows.insert(Row(id: 9, name: "new"), at: 0)
        let before = cache.rowWork.rendered
        let moved = frame()
        // The new row and the cursor's (never kept) are composed; the four that
        // moved are not.
        #expect(cache.rowWork.rendered - before <= 2, "\(cache.rowWork.rendered - before) rows composed")
        #expect(!paintsBackground(line("row1", in: moved)))
        #expect(paintsBackground(line("row2", in: moved)))
        #expect(!paintsBackground(line("row3", in: moved)))
    }

    @Test("A kept row that moves back to a parity it was drawn at is served as kept there, not repainted again")
    func parityMoveBackServes() throws {
        var rows = Self.rows
        let context = makeRenderContext(width: 30, height: 10)
        let cache = try #require(context.renderCache)
        func frame() -> FrameBuffer {
            renderToBuffer(Table(rows) { TableColumn("Name", value: \Row.name) }, context: context)
        }
        for _ in 0..<3 { _ = frame() }
        let unmoved = frame()
        // A log tailing into the table: the rows move to the other parity and
        // back again, entry after entry.
        rows.insert(Row(id: 9, name: "new"), at: 0)
        var before = cache.rowWork.repainted
        _ = frame()
        #expect(cache.rowWork.repainted - before >= 3, "the moved rows are repainted at their new parity")
        rows.removeFirst()
        before = cache.rowWork.repainted
        let back = frame()
        #expect(cache.rowWork.repainted - before == 0, "\(cache.rowWork.repainted - before) rows repainted on the way back")
        #expect(back.lines == unmoved.lines)
        rows.insert(Row(id: 9, name: "new"), at: 0)
        before = cache.rowWork.repainted
        _ = frame()
        #expect(cache.rowWork.repainted - before == 0, "\(cache.rowWork.repainted - before) rows repainted at a parity they wore")
    }

    /// A striped row closes its ink with SGR 39 rather than a reset, so the
    /// stripe stays in force and is stated once (`TableRowInk`).
    /// Every cell must be what the persistent paint drew before: the unstriped
    /// row's cell with the stripe under it, inside the row, and the unstriped
    /// cell outside it (the border and the container's padding) — and a cell
    /// carrying escapes of its own keeps its reset, after which the stripe is
    /// stated again.
    @Test("A striped row states its stripe once and draws every cell the persistent paint drew")
    func stripeStatedOnce() throws {
        let plainColumns = Table(Self.rows) {
            TableColumn("Name", value: \Row.name)
            TableColumn("ID") { (row: Row) in Text(verbatim: "\(row.id)") }
        }
        let styledColumn = Table(Self.rows) {
            TableColumn("Name", value: \Row.name)
            TableColumn("Loud") { (row: Row) in Text(verbatim: row.name).bold() }
        }
        for (table, statesOnce) in [(AnyView(plainColumns), true), (AnyView(styledColumn), false)] {
            let striped = renderToBuffer(table.alternatingRowBackgrounds(.enabled), context: makeRenderContext(width: 40, height: 10))
            let plain = renderToBuffer(table.alternatingRowBackgrounds(.disabled), context: makeRenderContext(width: 40, height: 10))
            for name in ["row1", "row3"] {
                let new = line(name, in: striped)
                let cells = paintedCells(new)
                let unstriped = paintedCells(line(name, in: plain))
                try #require(unstriped.count == cells.count)
                let stripe = try #require(cells.map(\.background).first { !$0.isEmpty })
                // The stripe runs unbroken across the row, from its first cell
                // to its last, and nowhere else.
                let covered = cells.indices.filter { cells[$0].background == stripe }
                let row = try #require(covered.first)...(try #require(covered.last))
                #expect(covered.count == row.count, "\(name): the stripe is broken")
                #expect(row.count > Self.rows[0].name.count * 2, "\(name): the stripe covers \(row.count) cells")
                for column in cells.indices {
                    var expected = unstriped[column].state
                    if row.contains(column) { expected.apply(stripe) }
                    #expect(cells[column].state == expected, "\(name) column \(column)")
                    #expect(cells[column].glyph == unstriped[column].glyph, "\(name) column \(column)")
                }
                let statements = new.components(separatedBy: stripe).count - 1
                if statesOnce {
                    #expect(statements == 1, "\(name): the stripe stated \(statements) times")
                } else {
                    #expect(statements > 1, "\(name): a styled cell's own reset ends the stripe, which is stated again")
                }
            }
        }
    }

    @Test("A kept striped row takes the stripe of the surface the table moved onto")
    func memoFollowsTheSurface() throws {
        var context = makeRenderContext(width: 30, height: 10)
        let palette = context.environment.palette
        let surface = context.environment.liftedSurface
        let overSurface = try #require(palette.stripeFill(over: surface))
        try #require(overSurface != palette.stripeFill(over: palette.background))
        func frame() -> FrameBuffer {
            renderToBuffer(Table(Self.rows) { TableColumn("Name", value: \Row.name) }, context: context)
        }
        for _ in 0..<3 { _ = frame() }
        context.environment.surfaceBackground = surface
        let striped = line("row1", in: frame())
        #expect(striped.contains(overSurface.backgroundEscape()), "row1 is \(striped.debugDescription)")
    }

    @Test("A kept row that moves to the other parity redraws its stripe")
    func memoFollowsParity() {
        var rows = Self.rows
        let harnessContext = makeRenderContext(width: 30, height: 10)
        func frame() -> FrameBuffer {
            renderToBuffer(
                Table(rows) { TableColumn("Name", value: \Row.name) }.alternatingRowBackgrounds(),
                context: harnessContext)
        }
        _ = frame()
        _ = frame()
        _ = frame()
        let before = frame()
        #expect(paintsBackground(line("row1", in: before)))
        #expect(!paintsBackground(line("row2", in: before)))
        rows.insert(Row(id: 9, name: "new"), at: 0)
        let moved = frame()
        #expect(!paintsBackground(line("row1", in: moved)))
        #expect(paintsBackground(line("row2", in: moved)))
    }
}
