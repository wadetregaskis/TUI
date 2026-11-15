//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyboardShortcutHintTests.swift
//
//  `keyboardShortcutHint(_:)`, as an app writes it, with no `@testable`: a
//  menu item shows a key that something else binds, and the key does not run
//  the item (tuitree's feedback, Milestone 2 item 8).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIMenus
import TUITesting

@MainActor
private final class Deleted {
    var runs = 0
}

private struct NodeMenu: View {
    let deleted: Deleted

    var body: some View {
        Menu("Node") {
            Button("Delete Node") { deleted.runs += 1 }
                .keyboardShortcutHint(KeyboardShortcut("d", modifiers: .control))
        }
    }
}

@MainActor
@Suite("A menu item's key that something else binds")
struct KeyboardShortcutHintTests {
    @Test("The open menu shows the key beside the item")
    func menuShowsTheKey() throws {
        let app = TestApp(width: 40, height: 8) { NodeMenu(deleted: Deleted()) }
        app.press(.space)
        let row = try #require(app.screen.line(containing: "Delete Node"), "\(app.screen)")
        #expect(row.contains("⌃D"), "\(app.screen)")
    }

    @Test("The key does not run the item")
    func keyRunsNothing() {
        let deleted = Deleted()
        let app = TestApp(width: 40, height: 8) { NodeMenu(deleted: deleted) }
        app.press(.character("d"), modifiers: .control)
        #expect(deleted.runs == 0)
    }
}
