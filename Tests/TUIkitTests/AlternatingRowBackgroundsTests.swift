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
    // (`Table.isStriped(row:environment:)` says where).

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
