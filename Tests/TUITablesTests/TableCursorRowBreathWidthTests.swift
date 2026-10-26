//  🖥️ TUI — A Terminal UI framework for Swift
//  TableCursorRowBreathWidthTests.swift
//
//  A focused table's cursor row breathes across every cell of the row, its
//  last included. Found filming the README's Unicode clip (2026-10-26): the
//  row's last cell held one colour while the rest breathed, in Ghostty and
//  iTerm2 alike.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUITables
@testable import TUITestSupport
@testable import TUIView

private struct Row: Identifiable {
    let id: Int
    let flag: String
    let name: String
}

/// The Unicode clip's table, as it is filmed: flag, fixed and flexible columns,
/// a fixed frame, the first row selected.
private struct Breathing: View {
    @State private var selection: Int? = 0
    let rows = [Row(id: 0, flag: "🇯🇵", name: "日本語"), Row(id: 1, flag: "🇸🇪", name: "Svenska")]

    var body: some View {
        Table(rows, selection: $selection) {
            TableColumn("", value: \Row.flag).width(2)
            TableColumn("Language", value: \Row.name).width(11)
            TableColumn("Hello", value: \Row.name)
        }
        .frame(width: 46, height: 6)
    }
}

@MainActor
@Suite("A table's cursor row breathes to its last cell")
struct TableCursorRowBreathWidthTests {
    @Test("The cursor row's breath covers every cell its fill does, the last included")
    func lastCellBreathes() throws {
        try expectBreathCoversFill(renderToBuffer(Breathing(), context: makeRenderContext(width: 60, height: 10)))
    }

    /// The same question of a `List`, whose rows have a painter of their own.
    @Test("A list's cursor row breathes to its last cell too")
    func listLastCellBreathes() throws {
        let list = List(selection: .constant(Set([0]))) {
            ForEach(Breathing().rows) { Text($0.name) }
        }
        .frame(width: 46, height: 6)
        try expectBreathCoversFill(renderToBuffer(list, context: makeRenderContext(width: 60, height: 10)))
    }

    private func expectBreathCoversFill(_ drawn: FrameBuffer) throws {
        let row = try #require(drawn.lines.firstIndex { $0.stripped.contains("日本語") }, "\(drawn.lines)")
        var breathing = Set<Int>()
        for run in drawn.animatedCells where run.offsetY == row {
            breathing.formUnion(run.offsetX..<(run.offsetX + run.width))
        }
        #expect(!breathing.isEmpty, "the cursor row breathes")
        // The cells the row's fill paints: every cell on the row in the colour a
        // breathing cell is drawn in.
        let cells = paintedCells(drawn.lines[row])
        let fill = try #require(breathing.min().map { cells[$0].background })
        let filled = Set(cells.indices.filter { cells[$0].background == fill })
        #expect(
            filled.subtracting(breathing).isEmpty,
            "cells the fill paints that do not breathe: \(filled.subtracting(breathing).sorted())")
    }
}
