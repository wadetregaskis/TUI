//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuBarOpeningTests.swift
//
//  Opening the menu bar's menus: a click on a title, F10's bar mode (the
//  arrows, a title's letter, Return; Escape, F10 or any other key leaves),
//  Alt and a title's first letter; with one open, Left and Right, F10, Escape
//  and Return. The bar is not in the Tab ring.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICommands
@testable import TUIFoundation
import TUIPresentation

// MARK: - Fixtures

/// What the menus and the page did, reachable from an `App`.
private final class OpeningProbe: @unchecked Sendable {
    static let shared = OpeningProbe()
    var log: [String] = []
    /// Whether ``SheetLaterApp``'s sheet is up.
    var showsSheet = false
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

/// A sheet that is up while the probe says, the scene's own commands taken
/// away.
private struct SheetLaterApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            Text("PAGE").sheet(
                isPresented: Binding(get: { OpeningProbe.shared.showsSheet }, set: { OpeningProbe.shared.showsSheet = $0 })
            ) { Text("SHEET") }
        }
        .commandsRemoved()
        .commands { CommandMenu("Alpha") { Button("A1") {} } }
    }
}

/// A page whose own handler takes F10.
private struct PageF10App: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            Button("Page") {}
                .onKeyEvent { event in
                    guard event.key == .f10 else { return false }
                    OpeningProbe.shared.log.append("page f10")
                    return true
                }
        }
        .commandsRemoved()
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

    @Test("F10 highlights the first title and opens nothing; Down opens it, its first item highlighted")
    func f10WalksTheTitles() {
        let (app, clock) = launched(TwoMenusApp())
        #expect(!shows("A1", app), "sanity: every menu closed")
        let bar = app.screen[0]
        #expect(app.send(KeyEvent(key: .f10)))
        clock.frame(app)
        #expect(!shows("A1", app), "F10 opens no menu: \(rows(app))")
        // The same titles, drawn differently: the first lit, the letters underlined.
        #expect(app.screen[0].stripped == bar.stripped && app.screen[0] != bar, "\(app.screen[0].debugDescription)")
        app.send(KeyEvent(key: .down))
        clock.frame(app)
        #expect(shows("A1", app) && shows("A2", app), "\(rows(app))")
        app.send(KeyEvent(key: .enter))
        clock.frame(app)
        #expect(OpeningProbe.shared.log == ["a1"])
        #expect(!shows("A1", app), "choosing closed the menu: \(rows(app))")
    }

    @Test("In the bar mode Right moves along the titles and Return opens the one highlighted")
    func barModeArrows() {
        let (app, clock) = launched(TwoMenusApp())
        for key: Key in [.f10, .right, .enter] {
            app.send(KeyEvent(key: key))
            clock.frame(app)
        }
        #expect(shows("B1", app) && !shows("A1", app), "\(rows(app))")
        app.send(KeyEvent(key: .enter))
        #expect(OpeningProbe.shared.log == ["b1"], "a keyboard-opened menu highlights its first item")
    }

    @Test("In the bar mode a title's letter opens its menu, without Option")
    func barModeLetter() {
        let (app, clock) = launched(TwoMenusApp())
        app.send(KeyEvent(key: .f10))
        clock.frame(app)
        app.send(KeyEvent(key: .character("b")))
        clock.frame(app)
        #expect(shows("B1", app), "\(rows(app))")
    }

    @Test("Escape, F10 and any other key leave the bar mode, and the page does not hear the key")
    func barModeLeaves() {
        for key: Key in [.escape, .f10, .character("x"), .tab] {
            let (app, clock) = launched(TwoMenusApp())
            app.send(KeyEvent(key: .f10))
            clock.frame(app)
            app.send(KeyEvent(key: key))
            clock.frame(app)
            // Out of the mode: Down goes to the page again, and opens nothing.
            app.send(KeyEvent(key: .down))
            clock.frame(app)
            #expect(!shows("A1", app), "\(key): \(rows(app))")
            app.send(KeyEvent(key: .enter))
            #expect(OpeningProbe.shared.log.allSatisfy { $0.hasPrefix("page") }, "\(key): \(OpeningProbe.shared.log)")
        }
    }

    @Test("A click away from the titles leaves the bar mode and is spent on it; a click on a title opens it")
    func barModePointer() throws {
        let (app, clock) = launched(TwoMenusApp())
        app.send(KeyEvent(key: .f10))
        clock.frame(app)
        let page = try #require(rows(app).firstIndex { $0.contains("PageA") })
        let column = try #require(rows(app)[page].range(of: "PageA")).lowerBound.utf16Offset(in: rows(app)[page])
        app.send(MouseEvent(button: .left, phase: .pressed, x: column + 1, y: page))
        app.send(MouseEvent(button: .left, phase: .released, x: column + 1, y: page))
        clock.frame(app)
        #expect(OpeningProbe.shared.log.isEmpty, "the click left the mode and pressed nothing")
        app.send(KeyEvent(key: .down))
        clock.frame(app)
        #expect(!shows("A1", app), "out of the mode: \(rows(app))")
        app.send(KeyEvent(key: .f10))
        clock.frame(app)
        let beta = try title("Beta", app)
        app.send(MouseEvent(button: .left, phase: .pressed, x: beta, y: 0))
        app.send(MouseEvent(button: .left, phase: .released, x: beta, y: 0))
        clock.frame(app)
        #expect(shows("B1", app), "\(rows(app))")
    }

    @Test("Down moves the highlight; Escape closes the menu and the page has its focus back")
    func escapeRestoresTheFocus() {
        let (app, clock) = launched(TwoMenusApp())
        app.send(KeyEvent(key: .f10))
        clock.frame(app)
        app.send(KeyEvent(key: .down))
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
        app.send(KeyEvent(key: .down))
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
        app.send(KeyEvent(key: .down))
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

    /// Ghostty's default Option setting types `ƒ` for ⌥F, and reports the
    /// key it was made with (the owner, 2026-10-28, afternoon list #36).
    @Test("A character Option composed opens the menu of the letter Option was held with")
    func optionComposedLetterOpens() {
        let (app, clock) = launched(TwoMenusApp())
        let composed = KeyEvent(
            key: .character("∫"), pasteAttachments: [], optionComposedKey: .character("b"))
        #expect(app.send(composed))
        clock.frame(app)
        #expect(shows("B1", app), "\(rows(app))")
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

    /// Where `text` first shows below the bar's row: its first cell.
    private func cell<A: App>(of text: String, _ app: HeadlessApp<A>) throws -> (x: Int, y: Int) {
        let screen = rows(app)
        let y = try #require(screen.indices.dropFirst().first { screen[$0].contains(text) }, "\(screen)")
        let x = try #require(screen[y].range(of: text)).lowerBound.utf16Offset(in: screen[y])
        return (x, y)
    }

    /// The first cell of the title `name` on the bar's row.
    private func title<A: App>(_ name: String, _ app: HeadlessApp<A>) throws -> Int {
        let bar = rows(app)[0]
        return try #require(bar.range(of: name)).lowerBound.utf16Offset(in: bar)
    }

    @Test("A press on a title, dragged down its menu and let go on an item, runs the item and closes the menu")
    func pressDragReleaseChooses() throws {
        let (app, clock) = launched(TwoMenusApp())
        let alpha = try title("Alpha", app)
        app.send(MouseEvent(button: .left, phase: .pressed, x: alpha, y: 0))
        clock.frame(app)
        let item = try cell(of: "A2", app)
        app.send(MouseEvent(button: .left, phase: .dragged, x: item.x, y: item.y))
        clock.frame(app)
        app.send(MouseEvent(button: .left, phase: .released, x: item.x, y: item.y))
        clock.frame(app)
        #expect(OpeningProbe.shared.log == ["a2"])
        #expect(!shows("A1", app), "choosing closed the menu: \(rows(app))")
    }

    @Test("A press on a title let go where it went down leaves the menu open, nothing chosen")
    func pressReleaseInPlaceLeavesItOpen() throws {
        let (app, clock) = launched(TwoMenusApp())
        let alpha = try title("Alpha", app)
        app.send(MouseEvent(button: .left, phase: .pressed, x: alpha, y: 0))
        clock.frame(app)
        app.send(MouseEvent(button: .left, phase: .released, x: alpha, y: 0))
        clock.frame(app)
        #expect(shows("A1", app), "\(rows(app))")
        #expect(OpeningProbe.shared.log.isEmpty)
    }

    @Test("A press on a title dragged off every row and let go closes the menu, nothing chosen")
    func pressDragAwayCloses() throws {
        let (app, clock) = launched(TwoMenusApp())
        let alpha = try title("Alpha", app)
        app.send(MouseEvent(button: .left, phase: .pressed, x: alpha, y: 0))
        clock.frame(app)
        #expect(shows("A1", app), "sanity: the menu is open: \(rows(app))")
        app.send(MouseEvent(button: .left, phase: .dragged, x: 30, y: 9))
        clock.frame(app)
        app.send(MouseEvent(button: .left, phase: .released, x: 30, y: 9))
        clock.frame(app)
        #expect(!shows("A1", app), "\(rows(app))")
        #expect(OpeningProbe.shared.log.isEmpty)
    }

    @Test("With a menu open, the pointer moved onto another title opens that menu instead, highlighting nothing")
    func hoverFollowsWhileOpen() throws {
        let (app, clock) = launched(TwoMenusApp())
        let alpha = try title("Alpha", app)
        let beta = try title("Beta", app)
        app.send(MouseEvent(button: .left, phase: .pressed, x: alpha, y: 0))
        app.send(MouseEvent(button: .left, phase: .released, x: alpha, y: 0))
        clock.frame(app)
        app.send(MouseEvent(button: .none, phase: .moved, x: alpha + 1, y: 0))
        clock.frame(app)
        #expect(shows("A1", app), "the open menu's own title changes nothing: \(rows(app))")
        app.send(MouseEvent(button: .none, phase: .moved, x: beta, y: 0))
        clock.frame(app)
        #expect(shows("B1", app) && !shows("A1", app), "\(rows(app))")
        app.send(MouseEvent(button: .none, phase: .moved, x: 30, y: 9))
        clock.frame(app)
        #expect(shows("B1", app), "off the bar, the menu stays: \(rows(app))")
        app.send(KeyEvent(key: .enter))
        #expect(OpeningProbe.shared.log.isEmpty, "the pointer opened it, so nothing is highlighted")
    }

    @Test("With every menu closed, the pointer passing over a title opens nothing")
    func hoverOpensNothingWhenClosed() throws {
        let (app, clock) = launched(TwoMenusApp())
        app.send(MouseEvent(button: .none, phase: .moved, x: try title("Beta", app), y: 0))
        clock.frame(app)
        #expect(!shows("B1", app), "\(rows(app))")
    }

    @Test("A held press dragged from one title onto another opens its menu, and let go on an item runs it")
    func heldDragSwitchesMenus() throws {
        let (app, clock) = launched(TwoMenusApp())
        let alpha = try title("Alpha", app)
        app.send(MouseEvent(button: .left, phase: .pressed, x: alpha, y: 0))
        clock.frame(app)
        app.send(MouseEvent(button: .left, phase: .dragged, x: try title("Beta", app), y: 0))
        clock.frame(app)
        #expect(shows("B1", app) && !shows("A1", app), "\(rows(app))")
        let item = try cell(of: "B1", app)
        app.send(MouseEvent(button: .left, phase: .dragged, x: item.x, y: item.y))
        clock.frame(app)
        app.send(MouseEvent(button: .left, phase: .released, x: item.x, y: item.y))
        clock.frame(app)
        #expect(OpeningProbe.shared.log == ["b1"])
    }

    @Test("A held press let go on a title leaves that title's menu open")
    func heldReleaseOnATitleLeavesItOpen() throws {
        let (app, clock) = launched(TwoMenusApp())
        let beta = try title("Beta", app)
        app.send(MouseEvent(button: .left, phase: .pressed, x: try title("Alpha", app), y: 0))
        clock.frame(app)
        app.send(MouseEvent(button: .left, phase: .dragged, x: beta, y: 0))
        clock.frame(app)
        app.send(MouseEvent(button: .left, phase: .released, x: beta, y: 0))
        clock.frame(app)
        #expect(shows("B1", app), "\(rows(app))")
        #expect(OpeningProbe.shared.log.isEmpty)
    }

    @Test("With a menu open, a click on another title opens that title's menu")
    func clickOnAnotherTitleSwitches() throws {
        let (app, clock) = launched(TwoMenusApp())
        let beta = try title("Beta", app)
        app.send(KeyEvent(key: .f10))
        clock.frame(app)
        app.send(KeyEvent(key: .down))
        clock.frame(app)
        app.send(MouseEvent(button: .left, phase: .pressed, x: beta, y: 0))
        app.send(MouseEvent(button: .left, phase: .released, x: beta, y: 0))
        clock.frame(app)
        #expect(shows("B1", app) && !shows("A1", app), "\(rows(app))")
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
        app.send(KeyEvent(key: .down))
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

    @Test("Behind a modal, a click on a title opens nothing")
    func clickUnderAModal() throws {
        OpeningProbe.shared.showsSheet = true
        let (app, clock) = launched(SheetLaterApp())
        clock.frame(app)
        #expect(shows("SHEET", app), "sanity: the sheet is up: \(rows(app))")
        let bar = rows(app)[0]
        let column = try #require(bar.range(of: "Alpha")).lowerBound.utf16Offset(in: bar)
        app.send(MouseEvent(button: .left, phase: .pressed, x: column, y: 0))
        app.send(MouseEvent(button: .left, phase: .released, x: column, y: 0))
        clock.frame(app)
        clock.frame(app)
        #expect(!shows("A1", app), "\(rows(app))")
    }

    @Test("A menu open when a modal comes up closes, and stays closed when it goes")
    func modalClosesTheOpenMenu() {
        OpeningProbe.shared.showsSheet = false
        let (app, clock) = launched(SheetLaterApp())
        app.send(KeyEvent(key: .f10))
        clock.frame(app)
        app.send(KeyEvent(key: .down))
        clock.frame(app)
        #expect(shows("A1", app), "sanity: the menu is open: \(rows(app))")
        OpeningProbe.shared.showsSheet = true
        clock.frame(app)
        clock.frame(app)
        #expect(shows("SHEET", app) && !shows("A1", app), "\(rows(app))")
        OpeningProbe.shared.showsSheet = false
        clock.frame(app)
        clock.frame(app)
        #expect(!shows("SHEET", app) && !shows("A1", app), "\(rows(app))")
    }

    @Test(
        "What a key does in the bar mode",
        arguments: [
            (KeyEvent(key: .left), _MenuBarCore.BarModeAction.highlight(2)),
            (KeyEvent(key: .right), .highlight(1)),
            (KeyEvent(key: .down), .open(0)),
            (KeyEvent(key: .enter), .open(0)),
            (KeyEvent(key: .character("e")), .open(1)),
            (KeyEvent(key: .character("F"), alt: true), .open(2)),
            (KeyEvent(key: .character("q")), .leave),
            (KeyEvent(key: .character("e"), ctrl: true), .leave),
            (KeyEvent(key: .escape), .leave),
            (KeyEvent(key: .f10), .leave),
        ])
    func barModeActions(event: KeyEvent, action: _MenuBarCore.BarModeAction) {
        // The app's menu (no letter), Edit, and File.
        #expect(_MenuBarCore.barModeAction(for: event, highlighted: 0, mnemonics: [nil, "e", "f"]) == action)
    }

    @Test("The page's own F10 handler is asked before the menu bar")
    func pageF10Wins() {
        let (app, clock) = launched(PageF10App())
        clock.frame(app)
        #expect(app.send(KeyEvent(key: .f10)))
        clock.frame(app)
        #expect(OpeningProbe.shared.log == ["page f10"])
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
