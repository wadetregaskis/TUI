//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuBackdropReachTests.swift
//
//  An open menu files a region behind itself that closes it on a press
//  anywhere outside it, the press spent on that. The region was a fixed 8,192
//  cells square centred on the menu, so on a screen wider than 4,096 columns
//  a press far enough from the menu missed it, and reached the page under the
//  open menu instead. The region now spans the screen, wherever the menu is
//  on it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUIMenus
import TUITesting

/// What the page's button did.
@MainActor
private final class Presses {
    var pressed = 0
}

/// A pull-down menu at the left of a very wide screen, and a button at its
/// right edge.
private struct WideScreenMenuApp: App {
    var presses = Presses()

    var body: some Scene {
        WindowGroup {
            HStack(spacing: 0) {
                Menu("Actions") {
                    Button("Rename") {}
                    Button("Delete") {}
                }
                Spacer()
                Button("Far") { presses.pressed += 1 }
            }
        }
    }
}

@MainActor
@Suite("An open menu's dismiss backdrop")
struct MenuBackdropReachTests {
    @Test("A press anywhere on a screen wider than 4,096 columns closes an open menu, and reaches nothing under it")
    func pressFarAwayCloses() throws {
        let presses = Presses()
        let app = TestApp(WideScreenMenuApp(presses: presses), width: 5_000, height: 8)
        var now: Int64 = 0
        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }
        frame()
        frame()
        app.send(KeyEvent(key: .enter))
        frame()
        #expect(app.screen.contains("Rename"), "the menu is open")
        let row = try #require(app.screen.lines.firstIndex { $0.contains("Far") })
        let line = app.screen.lines[row]
        let found = try #require(line.range(of: "Far"))
        let x = line.distance(from: line.startIndex, to: found.lowerBound) + 1
        #expect(x > 4_096, "the button is past the old backdrop's reach")
        for phase in [MousePhase.pressed, .released] {
            app.send(MouseEvent(button: .left, phase: phase, x: x, y: row))
        }
        frame()
        #expect(!app.screen.contains("Rename"), "a press far from the menu closed it")
        #expect(presses.pressed == 0, "and was spent closing it, not on the page's button")
    }
}
