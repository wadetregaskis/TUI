//  🖥️ TUI — A Terminal UI framework for Swift
//  SplitViewResizeRoundTripTests.swift
//
//  A split view the terminal narrows and widens again puts its dividers back
//  where they were: each size is scaled from the sizes last set, not from the
//  last scaling's rounding.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
import TUITesting

@MainActor
@Suite("A split view across a resize")
struct SplitViewResizeRoundTripTests {
    /// The columns of the `│` dividers on the first row.
    private func dividers(_ app: TestApp) -> [Int] {
        Array(app.screen.lines[0]).enumerated().filter { $0.element == "│" }.map(\.offset)
    }

    @Test("Narrowed and widened again, the dividers are back where they were")
    func roundTrip() {
        let app = TestApp(width: 50, height: 4) {
            HSplitView {
                Text("LEFT")
                Text("MIDDLE")
                Text("RIGHT")
            }
        }
        // Move the first divider: Tab to it, and five cells left.
        app.press(.tab)
        app.press(.left, times: 5)
        let before = dividers(app)
        #expect(before.count == 2, "\(app.screen)")
        // Each narrowing rounds the panes down; scaled back up from those, the
        // dividers drifted towards the leading edge, a cell or more a trip.
        for width in [23, 31, 17] {
            app.resize(width: width, height: 4)
            app.resize(width: 50, height: 4)
            #expect(dividers(app) == before, "after a trip to \(width): \(app.screen)")
        }
        // A divider moved at the narrow width is where the panes stand from then on.
        app.resize(width: 25, height: 4)
        app.press(.right)
        let moved = dividers(app)
        app.resize(width: 50, height: 4)
        app.resize(width: 25, height: 4)
        #expect(dividers(app) == moved, "\(app.screen)")
    }
}
