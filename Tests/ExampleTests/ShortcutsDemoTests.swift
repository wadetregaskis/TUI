//  🖥️ TUI — A Terminal UI framework for Swift
//  ShortcutsDemoTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import Example
import TUI
import TUITesting

@MainActor
@Suite("The Menus page's ⌘ shortcuts section")
struct ShortcutsDemoTests {
    @Test("The 'Chose' read-out clears as the pop-up opens, so a choice made twice reads as two")
    func choseClearsOnOpen() throws {
        let app = TestApp(width: 100, height: 40) { ShortcutsDemo() }
        func chose() -> String? {
            app.screen.line(containing: "page.menus.chose")?.trimmingCharacters(in: .whitespaces)
        }
        #expect(chose()?.hasSuffix("—") == true, "starts cleared: \(app.screen)")

        try app.click("page.menus.shortcutsFile")
        let menu = try #require(app.screen.location(of: "page.menus.shortcutsFile"), "no menu button: \(app.screen)")
        // Below the button: the page may name the command above it too.
        let save = app.screen.locations(of: "page.menus.shortcuts.save").first { $0.y > menu.y }
        app.click(at: try #require(save, "the pop-up is open: \(app.screen)"))
        #expect(chose()?.hasSuffix("page.menus.shortcuts.save") == true, "\(chose() ?? "none")")

        try app.click("page.menus.shortcutsFile")
        #expect(chose()?.hasSuffix("—") == true, "opening the pop-up again clears it: \(chose() ?? "none")")
    }
}
