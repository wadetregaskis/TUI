//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableColumnLineLimitTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
@testable import TUIkitLists
@testable import TUIkitTables
@testable import TUIkitTestSupport

/// A column's line limit is at least one, however it is set.
///
/// `lineLimit(_:)` clamped; the stored property did not, and the two are the
/// same knob. Below 1 the wrapper's fold-and-truncate block does not run at all,
/// so `column.lineLimit = 0` did not make a single-line column — it made an
/// unlimited one, growing the row to however many lines the value wrapped to.
@MainActor
@Suite("A column's line limit is at least one")
struct TableColumnLineLimitTests {

    private struct Row: Identifiable { let id: Int }

    @Test("Written directly", arguments: [0, -1, Int.min])
    func writingDirectlyIsClamped(_ limit: Int) {
        var column = TableColumn("Notes") { (_: Row) in Text(verbatim: "x") }
        column.lineLimit = limit
        #expect(column.lineLimit == 1)
    }

    @Test("…and through the modifier", arguments: [0, -1, Int.min])
    func theModifierIsClamped(_ limit: Int) {
        #expect(TableColumn("Notes") { (_: Row) in Text(verbatim: "x") }.lineLimit(limit).lineLimit == 1)
    }

    @Test("A real limit is kept")
    func realLimitsSurvive() {
        var column = TableColumn("Notes") { (_: Row) in Text(verbatim: "x") }
        column.lineLimit = 4
        #expect(column.lineLimit == 4)
        #expect(TableColumn("Notes") { (_: Row) in Text(verbatim: "x") }.lineLimit(3).lineLimit == 3)
    }
}
