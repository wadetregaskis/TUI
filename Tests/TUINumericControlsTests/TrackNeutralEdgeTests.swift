//  🖥️ TUI — A Terminal UI framework for Swift
//  TrackNeutralEdgeTests.swift
//
//  A fill from a neutral value starts within a cell where the style can draw
//  a fill on a cell's right (owner ruling B33-SUBCELL): its ramp glyph covers
//  the cell's empty left part, in the track's colour, over the fill's.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUINumericControls
@testable import TUITestSupport

@Suite("A track's fill from a neutral value, to a fraction of a cell")
struct TrackNeutralEdgeTests {
    private func track(_ fraction: Double, neutral: Double, style: TrackStyle = .blockFine) -> ClaimingRow {
        TrackRenderer.render(
            fraction: fraction, width: 4, style: style,
            fillColor: .rgb(200, 0, 0), backgroundColor: .rgb(0, 0, 90), accentColor: .rgb(7, 7, 7),
            palette: SystemPalette.green, neutralFraction: neutral)
    }

    @Test("Above the neutral value, the fill starts within its cell: the ramp glyph is the empty part")
    func startsWithinACellAbove() {
        // 0.3 of four cells of eight steps is the tenth step: cell 1, two steps in.
        let row = track(1.0, neutral: 0.3)
        #expect(row.text.stripped == " ▎██")
        #expect(row.cells == 4)
    }

    @Test("Below the neutral value, the fill starts within the value's cell and ends within the neutral's")
    func startsWithinACellBelow() {
        // From the tenth step to the 29th: "▎" for the empty start, "▋" for the end.
        let row = track(0.3, neutral: 0.9)
        #expect(row.text.stripped == " ▎█▋")
    }

    @Test("The start cell is drawn in the track's colour over the fill's")
    func startCellColours() {
        let text = track(1.0, neutral: 0.3).text
        let cell = text.components(separatedBy: "▎")[0]
        #expect(cell.contains("48;2;200;0;0"), "the fill as the field: \(cell.debugDescription)")
        #expect(cell.contains("38;2;0;0;90"), "the track as the ink: \(cell.debugDescription)")
    }

    @Test("A style that cannot draw a fill on a cell's right keeps the whole-cell start")
    func wholeCellElsewhere() {
        let row = track(1.0, neutral: 0.3, style: .block)
        #expect(!row.text.stripped.contains("▎"))
        #expect(row.cells == 4)
    }
}
