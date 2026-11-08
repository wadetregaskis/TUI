//  🖥️ TUI — A Terminal UI framework for Swift
//  AdaptiveGridItemGapTests.swift
//
//  `GridItem.resolve` divides what the fixed and flexible items leave among the
//  adaptive ones, and charged each fixed or flexible item its trailing gap but
//  no adaptive item its own. With two adaptive items the gap between their two
//  groups was never set aside, so the tracks and gaps came to one cell more
//  than was available, and nothing ever shrank them: the last column was cut.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIGrid

@MainActor
@Suite("Adaptive grid items share the room their gaps leave")
struct AdaptiveGridItemGapTests {

    private func total(_ tracks: [GridTrack]) -> Int {
        tracks.reduce(0) { $0 + $1.extent } + tracks.dropLast().reduce(0) { $0 + $1.spacing }
    }

    @Test(
        "Tracks and the gaps between them fit what is available",
        arguments: [
            [GridItem(.adaptive(minimum: 5)), GridItem(.adaptive(minimum: 5))],
            [GridItem(.fixed(3)), GridItem(.adaptive(minimum: 5)), GridItem(.adaptive(minimum: 5))],
            [GridItem(.adaptive(minimum: 4)), GridItem(.flexible()), GridItem(.adaptive(minimum: 4))],
        ])
    func fits(items: [GridItem]) {
        // From the least that holds one track of each item: below it, a grid
        // still draws one clipped track per item rather than none.
        for available in 15...40 {
            let tracks = GridItem.resolve(items, available: available)
            #expect(total(tracks) <= available, "\(available): \(tracks.map(\.extent))")
        }
    }

    @Test("Two adaptive items in 22 cells fill exactly 22")
    func twoAdaptiveItems() {
        let tracks = GridItem.resolve(
            [GridItem(.adaptive(minimum: 5)), GridItem(.adaptive(minimum: 5))], available: 22)
        // Four 5-cell tracks and three gaps were 23.
        #expect(total(tracks) == 22, "\(tracks.map(\.extent))")
    }
}
