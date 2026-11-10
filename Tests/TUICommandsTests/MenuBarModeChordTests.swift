//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuBarModeChordTests.swift
//
//  F10's bar mode and the Control chords: a chord leaves the mode and goes on
//  down the chain, as it goes past an open menu, so a command's shortcut
//  fires and the quit key quits. A bare key is still spent on leaving
//  (`MenuBarOpeningTests`).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
import TUICommands
import TUIFoundation
import TUITesting

/// What the commands and the page did.
@MainActor
private final class ChordLog {
    static let shared = ChordLog()
    var entries: [String] = []
}

/// A menu whose item has ⌃Y, over a page of one button.
private struct ChordApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            Button("Page") { ChordLog.shared.entries.append("page") }
        }
        .commandsRemoved()
        .commands {
            CommandMenu("Alpha") {
                Button("A1") { ChordLog.shared.entries.append("a1") }.keyboardShortcut("y", modifiers: .control)
            }
        }
    }
}

@MainActor
@Suite("The bar mode and Control chords", .serialized)
struct MenuBarModeChordTests {
    @Test("In the bar mode a command's shortcut fires, and leaves the mode")
    func shortcutFires() {
        ChordLog.shared.entries = []
        let app = TestApp(ChordApp(), width: 40, height: 8)
        app.press(.f10)
        app.press(.character("y"), modifiers: .control)
        #expect(ChordLog.shared.entries == ["a1"])
        // Out of the mode: Down opens nothing, and Return presses the page's button.
        app.press(.down)
        #expect(!app.screen.contains("A1"), "\(app.screen)")
        app.press(.enter)
        #expect(ChordLog.shared.entries == ["a1", "page"])
    }

    @Test("In the bar mode the quit key quits, as it does with a menu open")
    func quitKeyQuits() {
        let app = TestApp(ChordApp(), width: 40, height: 8)
        app.press(.f10)
        app.press(.character("q"), modifiers: .control)
        #expect(app.hasRequestedQuit)
    }
}
