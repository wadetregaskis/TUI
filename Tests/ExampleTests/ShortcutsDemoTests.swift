//  🖥️ TUI — A Terminal UI framework for Swift
//  ShortcutsDemoTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import Example
import TUI
@testable import TUIApp

extension ShortcutsDemo: ExamplePageContent {}

@MainActor
@Suite("The Menus page's ⌘ shortcuts section")
struct ShortcutsDemoTests {
    @Test("The 'Chose' read-out clears as the pop-up opens, so a choice made twice reads as two")
    func choseClearsOnOpen() {
        let driver = ExamplePageDriver(ExamplePageApp<ShortcutsDemo>())
        func chose() -> String? {
            driver.lines.first { $0.contains("page.menus.chose") }?.trimmingCharacters(in: .whitespaces)
        }
        #expect(chose()?.hasSuffix("—") == true, "starts cleared: \(driver.lines)")

        driver.click("page.menus.shortcutsFile")
        guard let menu = driver.position(of: "page.menus.shortcutsFile") else {
            Issue.record("no menu button: \(driver.lines)")
            return
        }
        #expect(driver.click("page.menus.shortcuts.save", fromRow: menu.row + 1), "the pop-up is open")
        #expect(chose()?.hasSuffix("page.menus.shortcuts.save") == true, "\(chose() ?? "none")")

        driver.click("page.menus.shortcutsFile")
        #expect(chose()?.hasSuffix("—") == true, "opening the pop-up again clears it: \(chose() ?? "none")")
    }
}
