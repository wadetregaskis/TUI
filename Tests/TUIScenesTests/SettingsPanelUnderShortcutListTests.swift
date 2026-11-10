//  🖥️ TUI — A Terminal UI framework for Swift
//  SettingsPanelUnderShortcutListTests.swift
//
//  F2 while F1's list of shortcuts is up over the settings panel: the list
//  holds the keyboard, so F2 leaves the panel under it alone. It closed the
//  panel, out of sight, and Escape then showed the page.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
import TUIFoundation
import TUITesting

/// A page and nothing else: F2's panel holds TUI's own tabs.
private struct PlainApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("PAGE") }
    }
}

@MainActor
@Suite("The settings panel under the list of shortcuts")
struct SettingsPanelUnderShortcutListTests {
    @Test("F2 under the list leaves the panel up; Escape takes the list down to it")
    func f2UnderTheList() {
        let app = TestApp(PlainApp(), width: 70, height: 22)
        app.press(.f2)
        #expect(app.screen.contains("Accessibility"), "the panel is up: \(app.screen)")
        app.press(.f1)
        #expect(app.screen.contains("Keyboard Shortcuts"), "the list is up: \(app.screen)")
        app.press(.f2)
        app.press(.escape)
        #expect(app.screen.contains("Accessibility"), "the panel is still up: \(app.screen)")
    }
}
