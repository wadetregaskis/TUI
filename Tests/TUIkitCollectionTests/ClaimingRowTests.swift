//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ClaimingRowTests.swift
//
//  `ClaimingRow.append(contentsOf:)` splices one row into another: its bytes, and
//  its claims moved to the columns they now sit at.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("A ClaimingRow splices a row, claims and all")
struct ClaimingRowTests {

    /// Three blanks, an opaque wall, then a spliced row of two translucent cells: the
    /// splice's claim must land on the two cells it was drawn in, past everything
    /// the row had already drawn.
    @Test("A spliced row's claims land on the columns it now sits at")
    func spliceMovesTheClaims() {
        var inner = ClaimingRow()
        inner.append("ab", cells: 2, ink: Color.red.opacity(0.5))
        var row = ClaimingRow()
        row.skip(cells: 3)
        row.append("│", cells: 1, ink: Color.white)
        row.append(contentsOf: inner)

        #expect(row.cells == 6)
        #expect(row.text.stripped == "   │ab")
        var buffer = FrameBuffer(lines: [row.text])
        buffer.opacityRegions = row.claims
        // Coverage, not claim count: what a row owes is an alpha per column.
        let claimed = (0..<6).filter { owed(atColumn: $0, row: 0, in: buffer).ink != 1 }
        #expect(claimed == [4, 5])
    }

    /// `appendCells(cycling:)` is a track's constant-colour fill spelled once per glyph
    /// instead of once per cell. It must be the per-cell loop exactly — the bytes, the
    /// claims (including how the first one meets a claim already on the row) and the
    /// cell count — for one glyph and a cycle, short and long runs, with and without a
    /// field, opaque and translucent.
    @Test("A run of cycled cells is the per-cell appends, byte for byte and claim for claim")
    func cycledCellsMatchPerCellAppends() {
        let glyphSets: [[Character]] = [["█"], ["▰", "▱"], ["a", "b", "c"]]
        let pairs: [(ink: Color?, field: Color?)] = [
            (Color.green, Color.green), (Color.green, nil), (nil, nil),
            (Color.red.opacity(0.5), Color.red.opacity(0.5)), (Color.blue, Color.white.opacity(0.25)),
        ]
        for glyphs in glyphSets {
            for pair in pairs {
                for count in [0, 1, 2, 3, 7] {
                    for lead in [nil, pair.ink] as [Color?] {
                        var perCell = ClaimingRow()
                        var shared = ClaimingRow()
                        if let lead {
                            // A run already on the row, owing what the cells will: the
                            // first cell's claim must meet it the same way in both.
                            perCell.append("x", cells: 1, ink: lead, field: pair.field)
                            shared.append("x", cells: 1, ink: lead, field: pair.field)
                        }
                        for index in 0..<count {
                            perCell.append(
                                String(glyphs[index % glyphs.count]), cells: 1, ink: pair.ink, field: pair.field)
                        }
                        shared.appendCells(cycling: glyphs, count: count, ink: pair.ink, field: pair.field)
                        #expect(shared.text == perCell.text, "glyphs \(glyphs), count \(count)")
                        #expect(shared.claims == perCell.claims, "glyphs \(glyphs), count \(count)")
                        #expect(shared.cells == perCell.cells)
                    }
                }
            }
        }
    }
}
