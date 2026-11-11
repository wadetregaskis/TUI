//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuBarKeyboardTests.swift
//
//  The keyboard in the menu bar's menus (the owner, 2026-11-10, MENUBAR-KEYS):
//  a menu the keyboard opens draws its first ENABLED item lit, on the frame
//  that opens it, as macOS does
//  (`Tools/SwiftUIProbes/Menu keyboard walk (1110E)`).
//
//  The highlight is read from the DRAWN frame, against the same menu opened
//  by the pointer (nothing highlighted) and drawn at the same instant: the
//  controller had the right row all along, and the frame showed none.
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
private final class KeysProbe: @unchecked Sendable {
    static let shared = KeysProbe()
    var log: [String] = []
}

/// Alpha leads with a disabled item and a divider; Beta's first item is a
/// submenu, the row that caught Right; a pop-up `Menu` on the page leads with
/// a disabled item too.
private struct KeysBarApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            Menu("Pop") {
                Button("P0") { KeysProbe.shared.log.append("p0") }.disabled(true)
                Button("P1") { KeysProbe.shared.log.append("p1") }
                Button("P2") { KeysProbe.shared.log.append("p2") }
            }
        }
        .commandsRemoved()
        .commands {
            CommandMenu("Alpha") {
                Button("A0") { KeysProbe.shared.log.append("a0") }.disabled(true)
                Divider()
                Button("A1") { KeysProbe.shared.log.append("a1") }
                Button("A2") { KeysProbe.shared.log.append("a2") }
            }
            CommandMenu("Beta") {
                Menu("BSub") {
                    Button("BS1") { KeysProbe.shared.log.append("bs1") }
                    Button("BS2") { KeysProbe.shared.log.append("bs2") }
                }
                Button("B1") { KeysProbe.shared.log.append("b1") }
            }
            CommandMenu("Gamma") {
                Button("G1") { KeysProbe.shared.log.append("g1") }
            }
        }
    }
}

@MainActor
@Suite("The keyboard in the menu bar's menus", .serialized)
struct MenuBarKeyboardTests {
    private static let width = 50
    private static let height = 14

    @MainActor
    private final class Driver {
        let app = TestApp(KeysBarApp(), width: MenuBarKeyboardTests.width, height: MenuBarKeyboardTests.height)
        /// The instant the last frame was drawn at.
        private(set) var drawnAt: Int64 = 0
        private var now: Int64 = 0

        init() {
            KeysProbe.shared.log = []
            frame()
        }

        func frame() {
            app.frame(atNanos: now)
            drawnAt = now
            now += 20_000_000
        }

        func key(_ key: Key, times: Int = 1) {
            for _ in 0..<times {
                app.send(KeyEvent(key: key))
                frame()
            }
        }

        var rows: [String] { app.screen.lines }

        /// Whether the screen shows `text` below the bar's row.
        func shows(_ text: String) -> Bool { rows.dropFirst().contains { $0.contains(text) } }
    }

    /// The words of the menu row drawn lit: the one that differs from the same
    /// menu opened by a click on `opener` (nothing highlighted), drawn at the
    /// same instant; `nil` where none is lit.
    private func litRow(_ driver: Driver, openedBy opener: String) throws -> String? {
        let reference = TestApp(KeysBarApp(), width: Self.width, height: Self.height)
        reference.frame(atNanos: 0)
        try reference.click(opener)
        reference.frame(atNanos: driver.drawnAt)
        let drawn = driver.app.screen
        // A menu's rows, between its borders: not the bar, nor a trigger on the page.
        for (index, line) in drawn.styledLines.enumerated().dropFirst()
        where drawn.lines[index].contains("│") && line != reference.screen.styledLines[index] {
            return drawn.lines[index].filter { !"│╭╮╰╯▸".contains($0) }.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    @Test("A menu the keyboard opens draws its first enabled item lit, past a disabled item and a divider")
    func keyboardOpenLightsTheFirstEnabledItem() throws {
        let driver = Driver()
        driver.key(.f10)
        driver.key(.down)
        #expect(try litRow(driver, openedBy: " Alpha ") == "A1", "\(driver.rows)")
        driver.key(.enter)
        #expect(KeysProbe.shared.log == ["a1"])
    }

    @Test("A menu Right steps to draws its first enabled item lit")
    func steppedToMenuLightsItsFirstEnabledItem() throws {
        let driver = Driver()
        driver.key(.f10)
        driver.key(.left)
        driver.key(.down)
        #expect(driver.shows("G1"), "Gamma, the last title: \(driver.rows)")
        driver.key(.right)
        #expect(try litRow(driver, openedBy: " Alpha ") == "A1", "round to Alpha: \(driver.rows)")
    }

    @Test("A pop-up Menu the keyboard opens lights its first enabled item, and Up there stops")
    func popUpMenuMatches() throws {
        let driver = Driver()
        driver.key(.enter)
        #expect(driver.shows("P1"), "Return opened the page's menu: \(driver.rows)")
        #expect(try litRow(driver, openedBy: "Pop") == "P1", "\(driver.rows)")
        driver.key(.up)
        #expect(driver.shows("P1"), "Up on the first item leaves the menu open: \(driver.rows)")
        #expect(try litRow(driver, openedBy: "Pop") == "P1", "and on its first item: \(driver.rows)")
    }
}
