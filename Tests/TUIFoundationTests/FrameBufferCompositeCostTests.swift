//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameBufferCompositeCostTests.swift
//
//  The copying `composited(with:at:)` padded every row of the base (a measure
//  each) and then built its result with `FrameBuffer(lines:)` (a second measure
//  each), however little the overlay covered — and the root composites every
//  floating layer with it: a menu, a tooltip, every `.offset` view's drawing.
//  So a one-cell layer over a screen cost two walks of every row of the screen
//  (hunt 11-20, CORE1-4). These hold its cost to the rows the overlay covers.
//
//  Measured in CPU time, the fastest of several batches, as
//  `FrameBufferCombineScalingTests` explains; what is asserted is the SHAPE —
//  a ratio between two sizes — so it means the same on any machine.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUICore
@testable import TUITestSupport

@Suite("Compositing costs the rows it covers")
struct FrameBufferCompositeCostTests {
    /// The cost of compositing one cell onto `rows` uniform rows. The rows are
    /// wide glyphs, which a measure decodes cell by cell, so a walk of a row is
    /// what the time is made of rather than the array of rows around it.
    private func compositeOneCell(rows: Int) -> TimeInterval {
        let row = String(repeating: "世界", count: 40)
        let base = FrameBuffer(lines: Array(repeating: row, count: rows))
        precondition(base.linesAreUniformWidth)
        let cell = FrameBuffer(lines: ["x"])
        return bestCPUSeconds {
            for _ in 0..<4 {
                let composited = base.composited(with: cell, at: (x: 2, y: 0))
                precondition(composited.height == rows)
            }
        }
    }

    /// 16× the rows under the same one-cell overlay. Walking every row costs
    /// 16× (17.1× before the fix); walking only the covered one costs
    /// the same at both sizes, plus copying the array of rows (1.1× after).
    @Test("A one-cell overlay over a uniform buffer does not walk every row")
    func smallOverlayOverTallBase() {
        let ratio = compositeOneCell(rows: 800) / compositeOneCell(rows: 50)
        #expect(
            ratio < 5,
            """
            composited grew \(ratio.formatted(.number.precision(.fractionLength(1))))× for 16× the base's rows \
            under a one-cell overlay — it is walking rows the overlay does not cover again.
            """)
    }
}
