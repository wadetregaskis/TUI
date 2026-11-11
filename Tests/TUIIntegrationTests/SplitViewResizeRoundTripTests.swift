//  🖥️ TUI — A Terminal UI framework for Swift
//  SplitViewResizeRoundTripTests.swift
//
//  A split view the terminal narrows and widens again puts its dividers back
//  where they were: each size is scaled from the sizes last set, not from the
//  last scaling's rounding; and a navigation split view's column keeps the
//  width the person gave it, though a narrower terminal held it in a while.
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
    private func dividers(_ app: TestApp, glyph: Character = "│") -> [Int] {
        let row = glyph == "│" ? 0 : app.screen.lines.firstIndex { $0.contains(glyph) } ?? 0
        return Array(app.screen.lines[row]).enumerated().filter { $0.element == glyph }.map(\.offset)
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

    @Test("A navigation split view's column the person widened is as wide again once the terminal is")
    func navigationSplitColumnKeepsItsWidth() {
        let app = TestApp(width: 80, height: 5) {
            NavigationSplitView {
                Text("SIDEBAR")
            } detail: {
                Text("DETAIL")
            }
        }
        // Tab to the divider and widen the sidebar ten cells.
        app.press(.tab)
        app.press(.right, times: 10)
        let widened = dividers(app, glyph: "◀")
        #expect(widened.count == 1, "\(app.screen)")
        // A terminal too narrow for it holds the column in; wider again, the
        // column stayed at the narrow width, the clamp written over the
        // person's width.
        app.resize(width: 20, height: 5)
        app.resize(width: 80, height: 5)
        #expect(dividers(app, glyph: "◀") == widened, "\(app.screen)")
        // A step taken at a narrower width is a step from what was shown
        // there: 30 columns hold the sidebar to 19, its detail keeping 10.
        app.resize(width: 30, height: 5)
        let narrow = dividers(app, glyph: "◀")
        app.press(.left)
        #expect(dividers(app, glyph: "◀") == narrow.map { $0 - 1 }, "\(app.screen)")
        app.resize(width: 80, height: 5)
        #expect(dividers(app, glyph: "◀") == narrow.map { $0 - 1 }, "\(app.screen)")
    }
}
