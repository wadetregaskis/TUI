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

    @Test("A striped table tints every other row, from the first")
    func tableStripes() {
        let buffer = table(.enabled)
        #expect(!paintsBackground(line("row1", in: buffer)))
        #expect(paintsBackground(line("row2", in: buffer)))
        #expect(!paintsBackground(line("row3", in: buffer)))
    }

    @Test("A table stripes by default, as a macOS table does (decisions A29)", arguments: [
        AlternatingRowBackgroundBehavior?.none, .automatic,
    ])
    func tableStripesByDefault(_ behavior: AlternatingRowBackgroundBehavior?) {
        let buffer = table(behavior)
        #expect(!paintsBackground(line("row1", in: buffer)))
        #expect(paintsBackground(line("row2", in: buffer)))
        #expect(!paintsBackground(line("row3", in: buffer)))
    }

    @Test("A table stripes under every built-in style")
    func tableStripesUnderEveryStyle() {
        let context = makeRenderContext(width: 30, height: 10)
        let base = Table(Self.rows) { TableColumn("Name", value: \Row.name) }
        for buffer in [
            renderToBuffer(base.tableStyle(.inset), context: context),
            renderToBuffer(base.tableStyle(.bordered), context: context),
        ] {
            #expect(paintsBackground(line("row2", in: buffer)))
            #expect(!paintsBackground(line("row3", in: buffer)))
        }
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
        #expect(paintsBackground(line("row2", in: buffer)))
    }

    @Test("A striped list tints every other row as a striped table does")
    func listStripes() {
        let list = List(Self.rows) { row in Text(row.name) }
        let context = makeRenderContext(width: 30, height: 10)
        let striped = renderToBuffer(list.alternatingRowBackgrounds(), context: context)
        #expect(paintsBackground(line("row2", in: striped)))
        #expect(!paintsBackground(line("row1", in: striped)))
        // A list keeps macOS's answer: no stripes unless asked (decisions A46).
        let plain = renderToBuffer(list, context: context)
        #expect(!paintsBackground(line("row2", in: plain)))
        let automatic = renderToBuffer(list.alternatingRowBackgrounds(.automatic), context: context)
        #expect(!paintsBackground(line("row2", in: automatic)))
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
        #expect(paintsBackground(line("row2", in: before)))
        #expect(!paintsBackground(line("row3", in: before)))
        rows.insert(Row(id: 9, name: "new"), at: 0)
        let moved = frame()
        #expect(!paintsBackground(line("row2", in: moved)))
        #expect(paintsBackground(line("row3", in: moved)))
    }
}
