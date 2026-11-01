//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuBarSubmenuTests.swift
//
//  A `Menu` in a command menu is a submenu of the bar's menu, as SwiftUI's is
//  (measured on macOS 15.8, `Tools/SwiftUIProbes/Menu items and alert
//  buttons/pickers.out`). The bar's arrows and the submenu's share Left and
//  Right as every desktop shares them: Right on the submenu's row opens it,
//  Right anywhere else steps to the next menu; Left in a submenu closes it,
//  anywhere else steps to the menu before.
//
//  Here rather than beside the bar's own tests because it takes the menus
//  module, which the commands module does not.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICommands
@testable import TUIFoundation
import TUITesting

/// What the menus did, reachable from an `App`.
private final class SubmenuProbe: @unchecked Sendable {
    static let shared = SubmenuProbe()
    var log: [String] = []
}

/// Alpha holds a submenu; Beta is the menu beside it.
private struct SubmenuBarApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Button("Page") {} }
            .commandsRemoved()
            .commands {
                CommandMenu("Alpha") {
                    Button("A1") { SubmenuProbe.shared.log.append("a1") }
                    Menu("More") {
                        Button("M1") { SubmenuProbe.shared.log.append("m1") }
                        Button("M2") { SubmenuProbe.shared.log.append("m2") }
                            .keyboardShortcut("k", modifiers: .control)
                    }
                }
                CommandMenu("Beta") {
                    Button("B1") { SubmenuProbe.shared.log.append("b1") }
                }
            }
    }
}

@MainActor
@Suite("Submenus in the menu bar's menus", .serialized)
struct MenuBarSubmenuTests {
    @MainActor
    private final class Driver {
        let app = TestApp(SubmenuBarApp(), width: 50, height: 12)
        private var now: Int64 = 0

        init() {
            SubmenuProbe.shared.log = []
            frame()
        }

        func frame() {
            app.frame(atNanos: now)
            now += 20_000_000
        }

        func key(_ key: Key) {
            app.send(KeyEvent(key: key))
            frame()
        }

        var rows: [String] { app.screen.lines }

        /// Whether the screen shows `text` below the bar's row.
        func shows(_ text: String) -> Bool { rows.dropFirst().contains { $0.contains(text) } }
    }

    @Test("Right on the submenu's row opens it; Return chooses in it and closes every menu")
    func rightOpensTheSubmenu() {
        let driver = Driver()
        driver.key(.f10)
        driver.key(.down)
        driver.key(.down)
        driver.key(.right)
        #expect(driver.shows("M1") && driver.shows("A1"), "the submenu opened beside Alpha: \(driver.rows)")
        #expect(!driver.shows("B1"), "Right did not step to Beta: \(driver.rows)")
        driver.key(.down)
        driver.key(.enter)
        #expect(SubmenuProbe.shared.log == ["m2"], "\(SubmenuProbe.shared.log)")
        #expect(!driver.shows("A1"), "choosing closed the menus: \(driver.rows)")
    }

    @Test("Right in the submenu steps to the next menu; Left in it closes it and keeps Alpha")
    func arrowsInTheSubmenu() {
        let driver = Driver()
        driver.key(.f10)
        driver.key(.down)
        driver.key(.down)
        driver.key(.right)
        driver.key(.left)
        #expect(!driver.shows("M1") && driver.shows("A1"), "Left closed only the submenu: \(driver.rows)")
        driver.key(.right)
        driver.key(.right)
        #expect(driver.shows("B1") && !driver.shows("A1"), "Right in the submenu stepped to Beta: \(driver.rows)")
    }

    @Test("A submenu item's key equivalent works with every menu closed, as a command's does")
    func submenuShortcutWithMenusClosed() {
        let driver = Driver()
        driver.app.send(KeyEvent(key: .character("k"), ctrl: true))
        driver.frame()
        #expect(SubmenuProbe.shared.log == ["m2"], "\(SubmenuProbe.shared.log)")
    }
}
