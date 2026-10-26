//  🖥️ TUI — A Terminal UI framework for Swift
//  TrackBackgroundPatternTests.swift
//
//  A `.threeSegment` track's background pattern is the track's, laid from its
//  first cell, and the fill covers it: it does not slide along as the fill
//  grows. Found filming the README's Track styles clip (owner, 2026-10-26),
//  where a Pac-Man's dots moved ahead of him rather than waiting to be eaten.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUINumericControls
@testable import TUITestSupport

@MainActor
@Suite("A track's background pattern stays put")
struct TrackBackgroundPatternTests {
    private static let pacMan = TrackStyle.threeSegment(
        leading: " ", middle: " ", trailing: "ᗧ", backgroundPattern: "• ")

    /// The columns of the dots a 20-cell bar at `value` draws.
    private func dots(at value: Double) -> [Int] {
        let bar = ProgressView(value: value, total: 1).trackStyle(Self.pacMan).frame(width: 20)
        let line = renderToBuffer(bar, context: makeRenderContext(width: 20, height: 1)).lines[0].stripped
        return Array(line).enumerated().compactMap { $0.element == "•" ? $0.offset : nil }
    }

    @Test("The dots ahead of the fill are where they were before it grew")
    func dotsStayPut() {
        let before = dots(at: 0.3)
        let after = dots(at: 0.35)
        #expect(!before.isEmpty && !after.isEmpty)
        // Every dot still ahead of the fill is one that was there before.
        #expect(Set(after).isSubset(of: Set(before)), "before \(before), after \(after)")
        // And they sit on the pattern's own cells: every other column from the track's start.
        #expect(after.allSatisfy { $0.isMultiple(of: 2) }, "\(after)")
    }
}
