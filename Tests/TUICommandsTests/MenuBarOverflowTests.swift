//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuBarOverflowTests.swift
//
//  A menu bar wider than the terminal: the row scrolls to keep the title the
//  keyboard or an open menu lights in view, with « and » where titles are
//  hidden, which a press opens; and it draws within the row at any width.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICommands
@testable import TUIFoundation
import TUITesting

// MARK: - Fixtures

/// Six menus of one item each, wider together than a 30-column terminal, the
/// scene's own commands taken away.
private struct SixMenusApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("PAGE") }
            .commandsRemoved()
            .commands {
                CommandMenu("Alpha") { Button("A1") {} }
                CommandMenu("Beta") { Button("B1") {} }
                CommandMenu("Gamma") { Button("G1") {} }
                CommandMenu("Delta") { Button("D1") {} }
                CommandMenu("Epsilon") { Button("E1") {} }
                CommandMenu("Zeta") { Button("Z1") {} }
            }
    }
}

// MARK: - Tests

@MainActor
@Suite("A menu bar wider than the terminal", .serialized)
struct MenuBarOverflowTests {
    /// A fresh app `width` columns wide, after its first frame.
    private func launched(width: Int = 30) -> (TestApp, OverflowClock) {
        let app = TestApp(SixMenusApp(), width: width, height: 10)
        let clock = OverflowClock()
        clock.frame(app)
        return (app, clock)
    }

    private func press(_ key: Key, _ app: TestApp, _ clock: OverflowClock, times: Int = 1) {
        for _ in 0..<times {
            app.send(KeyEvent(key: key))
            clock.frame(app)
        }
    }

    @Test("With every menu closed, the titles start at the left edge and » says more follow")
    func closedShowsTheStartAndAnIndicator() {
        let (app, _) = launched()
        let bar = app.screen.lines[0]
        #expect(bar.hasPrefix(" Alpha  Beta "), "\(bar.debugDescription)")
        #expect(bar.hasSuffix("»"), "\(bar.debugDescription)")
        #expect(!bar.contains("Epsilon"), "no title is drawn cut in two: \(bar.debugDescription)")
    }

    @Test("F10 and Right walk to a title past the right edge, and the row scrolls to show it")
    func barModeScrollsToTheHighlight() {
        let (app, clock) = launched()
        press(.f10, app, clock)
        press(.right, app, clock, times: 5)
        let bar = app.screen.lines[0]
        #expect(bar.hasSuffix(" Zeta"), "the highlighted title is in view: \(bar.debugDescription)")
        #expect(bar.hasPrefix("«"), "« says titles are hidden to the left: \(bar.debugDescription)")
        #expect(!bar.contains("Alpha"), "\(bar.debugDescription)")
        // And back round to the first: the row returns to the start.
        press(.right, app, clock)
        #expect(app.screen.lines[0].hasPrefix(" Alpha "), "\(app.screen.lines[0].debugDescription)")
    }

    @Test("A menu opened past the right edge hangs from its title, in view")
    func openMenuScrollsAndAnchors() throws {
        let (app, clock) = launched()
        press(.f10, app, clock)
        press(.right, app, clock, times: 4)
        press(.down, app, clock)
        let bar = app.screen.lines[0]
        let column = try #require(bar.range(of: "Epsilon")).lowerBound.utf16Offset(in: bar)
        let item = try #require(app.screen.lines.firstIndex { $0.contains("E1") })
        let itemColumn = try #require(app.screen.lines[item].range(of: "E1")).lowerBound.utf16Offset(in: app.screen.lines[item])
        #expect(abs(itemColumn - column) <= 2, "the menu hangs from its title: \(app.screen.lines)")
        // Left and Right with the menu open scroll the row the same way.
        press(.right, app, clock)
        #expect(app.screen.lines[0].contains("Zeta") && app.screen.lines.contains { $0.contains("Z1") })
        press(.right, app, clock)
        #expect(app.screen.lines[0].hasPrefix(" Alpha ") && app.screen.lines.contains { $0.contains("A1") })
    }

    @Test("A press on » opens the first hidden title's menu, and on « the last hidden before the row")
    func indicatorsOpenHiddenMenus() throws {
        let (app, clock) = launched()
        let bar = app.screen.lines[0]
        let more = try #require(bar.lastIndex(of: "»")).utf16Offset(in: bar)
        app.send(MouseEvent(button: .left, phase: .pressed, x: more, y: 0))
        app.send(MouseEvent(button: .left, phase: .released, x: more, y: 0))
        clock.frame(app)
        let opened = app.screen.lines
        let menu = try #require(["G1", "D1", "E1"].first { item in opened.dropFirst().contains { $0.contains(item) } })
        #expect(opened[0].contains(["G1": "Gamma", "D1": "Delta", "E1": "Epsilon"][menu]!), "\(opened)")
        #expect(opened[0].hasPrefix("«"), "\(opened[0].debugDescription)")
        press(.escape, app, clock)
    }

    @Test("At any width the row is the terminal's width or less, and the lit title starts in view", arguments: [1, 2, 3, 4, 8])
    func smallWidths(width: Int) {
        let (app, clock) = launched(width: width)
        #expect(app.screen.lines[0].count <= width, "\(app.screen.lines[0].debugDescription)")
        press(.f10, app, clock)
        press(.right, app, clock, times: 5)
        let bar = app.screen.lines[0]
        #expect(bar.count <= width, "\(bar.debugDescription)")
        // " Zeta ", from its start, as much of it as there is room for.
        if width >= 2 { #expect(bar.contains("Z"), "\(bar.debugDescription)") }
    }

    @Test(
        "Which titles the row shows, from which column",
        arguments: [
            // Everything fits: no scroll, no indicator.
            ([5, 5], nil as Int?, 10, _MenuBarCore.TitleScroll(first: 0, end: 2, clipsLast: false, leading: false, trailing: false)),
            // Too wide, nothing lit: the start, and » in the last column.
            ([5, 5, 5], nil, 12, .init(first: 0, end: 2, clipsLast: false, leading: false, trailing: true)),
            // The last title lit: « then the titles that end with it.
            ([5, 5, 5], 2, 12, .init(first: 1, end: 3, clipsLast: false, leading: true, trailing: false)),
            // A middle title lit, room for it alone between « and ».
            ([5, 5, 5], 1, 7, .init(first: 1, end: 2, clipsLast: false, leading: true, trailing: true)),
            // A title wider than the row: itself, cut, and nothing else.
            ([5, 9, 5], 1, 6, .init(first: 1, end: 2, clipsLast: true, leading: false, trailing: false)),
            // Two cells: no room for an indicator.
            ([5, 5], nil, 2, .init(first: 0, end: 1, clipsLast: true, leading: false, trailing: false)),
        ])
    func scroll(widths: [Int], lit: Int?, width: Int, expected: _MenuBarCore.TitleScroll) {
        #expect(_MenuBarCore.TitleScroll(widths: widths, lit: lit, width: width) == expected)
    }
}

/// The frames' instants, 20 ms apart.
@MainActor
private final class OverflowClock {
    private var now: Int64 = 0

    func frame(_ app: TestApp) {
        app.frame(atNanos: now)
        now += 20_000_000
    }
}
