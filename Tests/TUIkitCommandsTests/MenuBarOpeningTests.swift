//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuBarOpeningTests.swift
//
//  Opening the menu bar's menus: a click on a title, F10, Alt and a title's
//  first letter; with one open, Left and Right, F10, Escape and Return. The
//  bar is not in the Tab ring.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitCommands
@testable import TUIkitFoundation
import TUIkitPresentation

// MARK: - Fixtures

/// What the menus and the page did, reachable from an `App`.
private final class OpeningProbe: @unchecked Sendable {
    static let shared = OpeningProbe()
    var log: [String] = []
}

/// Two menus of two items each, over a page of two buttons; the scene's own
/// commands taken away, so the bar's first menu is Alpha.
private struct TwoMenusApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                Button("PageA") { OpeningProbe.shared.log.append("page a") }
                Button("PageB") { OpeningProbe.shared.log.append("page b") }
            }
        }
        .commandsRemoved()
        .commands {
            CommandMenu("Alpha") {
                Button("A1") { OpeningProbe.shared.log.append("a1") }
                Button("A2") { OpeningProbe.shared.log.append("a2") }.keyboardShortcut("y", modifiers: .control)
            }
            CommandMenu("Beta") {
                Button("B1") { OpeningProbe.shared.log.append("b1") }
            }
        }
    }
}

/// The same under a sheet.
private struct UnderSheetApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("PAGE").sheet(isPresented: .constant(true)) { Text("SHEET") } }
            .commands { CommandMenu("Alpha") { Button("A1") {} } }
    }
}

// MARK: - Tests

@MainActor
@Suite("Opening the menu bar's menus", .serialized)
struct MenuBarOpeningTests {

    /// A fresh app, after its first frame, its log cleared.
    private func launched<A: App>(_ app: A) -> (HeadlessApp<A>, Clock) {
        OpeningProbe.shared.log = []
        let headless = HeadlessApp(app, width: 40, height: 12)
        let clock = Clock()
        clock.frame(headless)
        return (headless, clock)
    }

    /// The frame's rows, stripped.
    private func rows<A: App>(_ app: HeadlessApp<A>) -> [String] {
        app.screen.map(\.stripped)
    }

    /// Whether the screen shows `text` below the bar's row.
    private func shows<A: App>(_ text: String, _ app: HeadlessApp<A>) -> Bool {
        rows(app).dropFirst().contains { $0.contains(text) }
    }

    @Test("F10 opens the first menu with its first item highlighted, and Return chooses it")
    func f10Opens() {
        let (app, clock) = launched(TwoMenusApp())
        #expect(!shows("A1", app), "sanity: every menu closed")
        #expect(app.send(KeyEvent(key: .f10)))
        clock.frame(app)
        #expect(shows("A1", app) && shows("A2", app), "\(rows(app))")
        app.send(KeyEvent(key: .enter))
        clock.frame(app)
        #expect(OpeningProbe.shared.log == ["a1"])
        #expect(!shows("A1", app), "choosing closed the menu: \(rows(app))")
    }

    @Test("Down moves the highlight; Escape closes the menu and the page has its focus back")
    func escapeRestoresTheFocus() {
        let (app, clock) = launched(TwoMenusApp())
        app.send(KeyEvent(key: .f10))
        clock.frame(app)
        app.send(KeyEvent(key: .escape))
        clock.frame(app)
        #expect(!shows("A1", app), "\(rows(app))")
        app.send(KeyEvent(key: .enter))
        #expect(OpeningProbe.shared.log == ["page a"], "Return is the focused page button's again")
        app.send(KeyEvent(key: .f10))
        clock.frame(app)
        app.send(KeyEvent(key: .down))
        clock.frame(app)
        app.send(KeyEvent(key: .enter))
        #expect(OpeningProbe.shared.log == ["page a", "a2"])
    }

    @Test("Left and Right step to the menu beside the open one, round the ends")
    func arrowsStep() {
        let (app, clock) = launched(TwoMenusApp())
        app.send(KeyEvent(key: .f10))
        clock.frame(app)
        app.send(KeyEvent(key: .right))
        clock.frame(app)
        #expect(shows("B1", app) && !shows("A1", app), "\(rows(app))")
        app.send(KeyEvent(key: .right))
        clock.frame(app)
        #expect(shows("A1", app), "past the last menu, the first: \(rows(app))")
        app.send(KeyEvent(key: .left))
        clock.frame(app)
        #expect(shows("B1", app), "before the first, the last: \(rows(app))")
        app.send(KeyEvent(key: .enter))
        #expect(OpeningProbe.shared.log == ["b1"], "the stepped-to menu highlights its first item")
    }

    @Test("F10 with a menu open closes it")
    func f10Closes() {
        let (app, clock) = launched(TwoMenusApp())
        app.send(KeyEvent(key: .f10))
        clock.frame(app)
        app.send(KeyEvent(key: .f10))
        clock.frame(app)
        #expect(!shows("A1", app), "\(rows(app))")
    }

    @Test("Alt and a title's first letter opens that menu, closed or with another open")
    func altLetterOpens() {
        let (app, clock) = launched(TwoMenusApp())
        #expect(app.send(KeyEvent(key: .character("b"), alt: true)))
        clock.frame(app)
        #expect(shows("B1", app), "\(rows(app))")
        app.send(KeyEvent(key: .character("a"), alt: true))
        clock.frame(app)
        #expect(shows("A1", app) && !shows("B1", app), "\(rows(app))")
    }

    @Test("A click on a title opens its menu with nothing highlighted; a click while it is open closes it")
    func clickOpens() throws {
        let (app, clock) = launched(TwoMenusApp())
        let column = try #require(rows(app)[0].range(of: "Beta")).lowerBound.utf16Offset(in: rows(app)[0])
        app.send(MouseEvent(button: .left, phase: .pressed, x: column, y: 0))
        app.send(MouseEvent(button: .left, phase: .released, x: column, y: 0))
        clock.frame(app)
        #expect(shows("B1", app), "\(rows(app))")
        app.send(KeyEvent(key: .enter))
        #expect(OpeningProbe.shared.log.isEmpty, "the pointer chose nothing, so Return chooses nothing")
        app.send(MouseEvent(button: .left, phase: .pressed, x: column, y: 0))
        app.send(MouseEvent(button: .left, phase: .released, x: column, y: 0))
        clock.frame(app)
        #expect(!shows("B1", app), "\(rows(app))")
    }

    @Test("The bar is not in the Tab ring")
    func notInTheTabRing() {
        let (app, clock) = launched(TwoMenusApp())
        app.send(KeyEvent(key: .tab))
        clock.frame(app)
        app.send(KeyEvent(key: .tab))
        clock.frame(app)
        app.send(KeyEvent(key: .enter))
        #expect(OpeningProbe.shared.log == ["page a"], "two Tabs go round the page's two buttons")
        #expect(!shows("A1", app))
    }

    @Test("An open menu's item's shortcut fires once, as its menu's other items' do")
    func shortcutWhileOpen() {
        let (app, clock) = launched(TwoMenusApp())
        app.send(KeyEvent(key: .f10))
        clock.frame(app)
        app.send(KeyEvent(key: .character("y"), ctrl: true))
        #expect(OpeningProbe.shared.log == ["a2"])
    }

    @Test("Behind a modal, F10 and Alt open nothing")
    func inertUnderAModal() {
        let (app, clock) = launched(UnderSheetApp())
        clock.frame(app)
        app.send(KeyEvent(key: .f10))
        app.send(KeyEvent(key: .character("a"), alt: true))
        clock.frame(app)
        #expect(!shows("A1", app), "\(rows(app))")
    }
}

/// The frames' instants, 20 ms apart.
@MainActor
private final class Clock {
    private var now: Int64 = 0

    func frame<A: App>(_ app: HeadlessApp<A>) {
        app.frame(atNanos: now)
        now += 20_000_000
    }
}
