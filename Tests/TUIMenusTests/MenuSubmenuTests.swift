//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuSubmenuTests.swift
//
//  A `Menu` written in a pop-up menu, and a `Picker`, are submenus of it, as
//  SwiftUI's are (measured on macOS 15.8,
//  `Tools/SwiftUIProbes/Menu items and alert buttons/pickers.out`): a row with
//  the submenu caret that opens its items beside it. A nested `Menu` drew its
//  own collapsed control on a line of the menu, and choosing it closed the
//  menu it was in; a `Picker` drew a drop-down on a line the menu's arrows
//  walked past.
//
//  Driven through `TestApp`, the whole run loop: keys through the input
//  handler, clicks through the dispatcher in screen coordinates, a frame
//  between events.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUIMenus
import TUITesting
@testable import TUITestSupport

/// What the menus' items did.
@MainActor
private final class Record {
    var chosen: [String] = []
}

/// A menu with a submenu in it, and a context menu with a submenu, on one
/// page. (A `Picker` in a menu: `PickerInMenuTests`, beside the pickers.)
private struct SubmenuApp: App {
    var record = Record()
    var disablesCopy = false

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 0) {
                Menu("Actions") {
                    Button("Rename") { record.chosen.append("Rename") }
                    Menu("Copy") {
                        Button("As Text") { record.chosen.append("As Text") }
                        Button("As Link") { record.chosen.append("As Link") }
                            .keyboardShortcut("l", modifiers: .control)
                    }
                    .disabled(disablesCopy)
                    Button("Delete") { record.chosen.append("Delete") }
                }
                Text(verbatim: "Target").contextMenu {
                    Button("Cut") { record.chosen.append("Cut") }
                    Menu("Share") {
                        Button("Mail") { record.chosen.append("Mail") }
                    }
                }
            }
        }
    }
}

/// A menu at the right edge, two submenus deep.
private struct EdgeApp: App {
    var body: some Scene {
        WindowGroup {
            HStack(spacing: 0) {
                Spacer()
                Menu("Actions") {
                    Button("Rename") {}
                    Menu("Copy") {
                        Button("As Text") {}
                        Menu("Deeper") { Button("Deepest") {} }
                    }
                }
            }
        }
    }
}

@MainActor
@Suite("Submenus")
struct MenuSubmenuTests {
    /// The app, with a clock that steps a frame at a time.
    @MainActor
    private final class Driver<Scene: App> {
        let app: TestApp
        private var now: Int64 = 0

        init(_ scene: Scene, width: Int = 60, height: Int = 20) {
            app = TestApp(scene, width: width, height: height)
            frame()
            frame()
        }

        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }

        func key(_ key: Key, shift: Bool = false) {
            app.send(KeyEvent(key: key, shift: shift))
            frame()
        }

        var text: String { app.screen.lines.joined(separator: "\n") }

        func shows(_ label: String) -> Bool { app.screen.contains(label) }

        /// Where `label` is drawn: its first cell.
        func cell(of label: String) -> (x: Int, y: Int)? {
            for (row, line) in app.screen.styledLines.enumerated() {
                let plain = line.stripped
                if let range = plain.range(of: label) {
                    return (plain.distance(from: plain.startIndex, to: range.lowerBound), row)
                }
            }
            return nil
        }

        /// The line `label` is drawn on, as drawn.
        func line(of label: String) -> String? {
            app.screen.lines.first { $0.contains(label) }
        }

        func click(_ label: String) {
            guard let cell = cell(of: label) else { return }
            for phase in [MousePhase.pressed, .released] {
                app.send(MouseEvent(button: .left, phase: phase, x: cell.x + 1, y: cell.y))
            }
            frame()
        }

        func hover(_ label: String) {
            guard let cell = cell(of: label) else { return }
            app.send(MouseEvent(button: .none, phase: .moved, x: cell.x + 1, y: cell.y))
            frame()
        }

        /// Opens the pop-up menu from the keyboard: its first row highlighted.
        func openMenu() {
            key(.enter)
        }
    }

    @Test("A Menu in a pop-up menu is a row with the submenu caret, its items not yet shown")
    func nestedMenuIsARow() throws {
        let driver = Driver(SubmenuApp(record: Record()))
        driver.openMenu()
        let row = try #require(driver.line(of: "Copy"), "\(driver.text)")
        #expect(row.contains("▸"), "the row carries the caret: \(row)")
        #expect(!driver.shows("As Text"), "the submenu is closed: \(driver.text)")
    }

    @Test("Right opens the submenu beside its row, its first item highlighted, and Return chooses it")
    func rightOpensAndReturnChooses() throws {
        let record = Record()
        let driver = Driver(SubmenuApp(record: record))
        driver.openMenu()
        driver.key(.down)
        driver.key(.right)
        let item = try #require(driver.cell(of: "As Text"), "\(driver.text)")
        let row = try #require(driver.cell(of: "Copy"), "\(driver.text)")
        #expect(item.y == row.y, "the submenu's first item is level with its row: \(driver.text)")
        #expect(item.x > row.x, "…and beside it: \(driver.text)")
        driver.key(.enter)
        #expect(record.chosen == ["As Text"], "Return chose \(record.chosen)")
        #expect(!driver.shows("Rename"), "choosing closed every menu: \(driver.text)")
    }

    @Test("Down in an entered submenu moves in it; Left closes it and leaves its menu open")
    func leftClosesTheSubmenu() {
        let record = Record()
        let driver = Driver(SubmenuApp(record: record))
        driver.openMenu()
        driver.key(.down)
        driver.key(.right)
        driver.key(.down)
        driver.key(.left)
        #expect(!driver.shows("As Text"), "Left closed the submenu: \(driver.text)")
        #expect(driver.shows("Rename"), "…and left its menu up: \(driver.text)")
        // Its row still holds the highlight: Return opens it again, entered.
        driver.key(.enter)
        driver.key(.down)
        driver.key(.enter)
        #expect(record.chosen == ["As Link"], "Down moved in the submenu, then Return chose \(record.chosen)")
    }

    @Test("Escape closes a submenu, and then the menu")
    func escapeClosesOneLevel() {
        let driver = Driver(SubmenuApp(record: Record()))
        driver.openMenu()
        driver.key(.down)
        driver.key(.right)
        driver.key(.escape)
        #expect(!driver.shows("As Text"), "Escape closed the submenu: \(driver.text)")
        #expect(driver.shows("Rename"), "…and only the submenu: \(driver.text)")
        driver.key(.escape)
        #expect(!driver.shows("Rename"), "a second Escape closed the menu: \(driver.text)")
    }

    @Test("Moving the highlight off the submenu's row closes it")
    func movingOffCloses() {
        let driver = Driver(SubmenuApp(record: Record()))
        driver.openMenu()
        driver.key(.down)
        driver.key(.right)
        driver.key(.left)
        driver.key(.down)
        #expect(!driver.shows("As Text"), "\(driver.text)")
        driver.key(.up)
        driver.key(.right)
        #expect(driver.shows("As Text"), "Right opens it again from its row: \(driver.text)")
    }

    @Test("The pointer over the row opens the submenu with nothing in it highlighted, and a click chooses")
    func hoverOpensAndClickChooses() {
        let record = Record()
        let driver = Driver(SubmenuApp(record: record))
        driver.click("Actions")
        driver.hover("Copy")
        #expect(driver.shows("As Link"), "hovering the row opened the submenu: \(driver.text)")
        // The keys are still the menu's: Down moves its highlight off the
        // row, which closes the submenu.
        driver.hover("Rename")
        #expect(!driver.shows("As Link"), "the pointer on another row closed it: \(driver.text)")
        driver.hover("Copy")
        driver.click("As Link")
        #expect(record.chosen == ["As Link"], "the click chose \(record.chosen)")
        #expect(!driver.shows("Rename"), "and closed every menu: \(driver.text)")
    }

    @Test("A click on the submenu's row opens it and leaves the menu up")
    func clickOnTheRowOpens() {
        let record = Record()
        let driver = Driver(SubmenuApp(record: record))
        driver.click("Actions")
        driver.click("Copy")
        #expect(driver.shows("As Text"), "\(driver.text)")
        #expect(driver.shows("Rename"), "the menu is still up: \(driver.text)")
        #expect(record.chosen.isEmpty, "nothing was chosen: \(record.chosen)")
    }

    @Test("A disabled Menu still opens, a submenu of disabled items")
    func disabledMenuOpensDisabledItems() {
        let record = Record()
        let driver = Driver(SubmenuApp(record: record, disablesCopy: true))
        driver.openMenu()
        driver.key(.down)
        driver.key(.right)
        #expect(driver.shows("As Text"), "the submenu opened: \(driver.text)")
        driver.key(.enter)
        #expect(record.chosen.isEmpty, "a disabled item ran: \(record.chosen)")
    }

    @Test("A context menu's submenu opens and chooses, as a pop-up menu's does")
    func contextMenuSubmenu() {
        let record = Record()
        let driver = Driver(SubmenuApp(record: record))
        guard let target = driver.cell(of: "Target") else {
            Issue.record("no target: \(driver.text)")
            return
        }
        for phase in [MousePhase.pressed, .released] {
            driver.app.send(MouseEvent(button: .right, phase: phase, x: target.x + 1, y: target.y))
        }
        driver.frame()
        driver.hover("Share")
        driver.click("Mail")
        #expect(record.chosen == ["Mail"], "\(record.chosen) — \(driver.text)")
    }

    @Test("A submenu with no room on the right opens on its menu's left, and its own submenus go on that way")
    func flipsLeftAtTheEdge() throws {
        let driver = Driver(EdgeApp(), width: 50, height: 16)
        driver.openMenu()
        driver.key(.down)
        driver.key(.right)
        driver.key(.down)
        driver.key(.right)
        let menu = try #require(driver.cell(of: "Rename"), "\(driver.text)")
        let submenu = try #require(driver.cell(of: "As Text"), "\(driver.text)")
        let deeper = try #require(driver.cell(of: "Deepest"), "\(driver.text)")
        #expect(submenu.x < menu.x, "the submenu went to the menu's left: \(driver.text)")
        #expect(deeper.x < submenu.x, "and its own submenu further left, not back over the menu: \(driver.text)")
    }

    @Test("A closed submenu's item's key equivalent works while its menu is up, as the menu's own rows' do")
    func closedSubmenuShortcut() {
        let record = Record()
        let driver = Driver(SubmenuApp(record: record))
        driver.openMenu()
        #expect(!driver.shows("As Link"), "the submenu is closed: \(driver.text)")
        driver.app.send(KeyEvent(key: .character("l"), ctrl: true))
        driver.frame()
        #expect(record.chosen == ["As Link"], "\(record.chosen)")
    }
}
