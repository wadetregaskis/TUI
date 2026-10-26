//  🖥️ TUI — A Terminal UI framework for Swift
//  CellAspectTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIStyling

@Suite("The cell-aspect rule")
struct CellAspectTests {

    @Test("A usable ratio passes through unchanged", arguments: [0.1, 1.0, 2.0, 2.4, 4.0, 10.0])
    func usable(ratio: Double) {
        #expect(sanitizedCellAspect(ratio) == ratio)
    }

    @Test("A ratio with no meaning falls back to the default, not to a bound",
          arguments: [Double.nan, .infinity, -.infinity, 0, -0.0, -2])
    func meaningless(ratio: Double) {
        #expect(sanitizedCellAspect(ratio) == 2.0)
    }

    @Test("A finite ratio past either end lands on that end")
    func clamped() {
        #expect(sanitizedCellAspect(1e300) == cellAspectRange.upperBound)
        #expect(sanitizedCellAspect(10.5) == cellAspectRange.upperBound)
        #expect(sanitizedCellAspect(1e-300) == cellAspectRange.lowerBound)
        #expect(sanitizedCellAspect(0.05) == cellAspectRange.lowerBound)
        #expect(cellAspectRange == 0.1...10)
    }
}
