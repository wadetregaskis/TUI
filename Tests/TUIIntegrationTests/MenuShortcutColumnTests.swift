//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuShortcutColumnTests.swift
//
//  A menu's shortcut column, as an app writes its menus: a table's selection
//  menu is wide enough for each title and its key, as `.contextMenu`'s is
//  (tuidisk's feedback, Milestone 3 item 10), and every key a menu item can
//  name has a symbol, Return and Escape included (item 11).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
import TUITesting

private struct Row: Identifiable {
    let id: Int
}

@MainActor
@Suite("A menu's shortcut column")
struct MenuShortcutColumnTests {
    /// The table of the report: two rows, a selection menu whose second item
    /// names a key something else binds.
    private func tableApp(width: Int, hintBoth: Bool = false) -> TestApp {
        TestApp(width: width, height: 12) {
            Table([Row(id: 1), Row(id: 2)]) {
                TableColumn("Name") { (row: Row) in Text(verbatim: "row \(row.id)") }
            }
            .contextMenu(forSelectionType: Int.self) { _ in
                if hintBoth {
                    Button("Move to Trash…") {}.keyboardShortcutHint(KeyboardShortcut("t", modifiers: .control))
                } else {
                    Button("Move to Trash…") {}
                }
                Button("Show in Finder") {}.keyboardShortcutHint(KeyboardShortcut("n", modifiers: .control))
            }
        }
    }

    @Test("A table's selection menu is wide enough for each title and its key")
    func tableMenuFitsTitleAndKey() throws {
        for hintBoth in [false, true] {
            let app = tableApp(width: 60, hintBoth: hintBoth)
            app.press(.down)
            app.press(.f10, modifiers: .shift)
            let finder = try #require(app.screen.line(containing: "Show in"), "\(app.screen)")
            #expect(finder.contains("Show in Finder ⌃N"), "\(app.screen)")
            let trash = try #require(app.screen.line(containing: "Move to"), "\(app.screen)")
            #expect(trash.contains("Move to Trash…"), "\(app.screen)")
            if hintBoth { #expect(trash.contains("Move to Trash… ⌃T"), "\(app.screen)") }
        }
    }

    @Test("The same items in a button's context menu are as wide")
    func buttonMenuAgrees() throws {
        let app = TestApp(width: 60, height: 12) {
            Button("target") {}
                .contextMenu {
                    Button("Move to Trash…") {}
                    Button("Show in Finder") {}.keyboardShortcutHint(KeyboardShortcut("n", modifiers: .control))
                }
        }
        app.press(.f10, modifiers: .shift)
        let finder = try #require(app.screen.line(containing: "Show in"), "\(app.screen)")
        #expect(finder.contains("Show in Finder ⌃N"), "\(app.screen)")
    }

    @Test(
        "A menu item names every key that types nothing with macOS's symbol, Return and Escape included",
        arguments: [
            (KeyEquivalent.return, "↩"), (.escape, "⎋"), (.tab, "⇥"), (.delete, "⌫"), (.deleteForward, "⌦"),
            (.upArrow, "↑"), (.downArrow, "↓"), (.leftArrow, "←"), (.rightArrow, "→"),
            (.pageUp, "⇞"), (.pageDown, "⇟"), (.home, "↖"), (.end, "↘"), (.space, "Space"),
        ])
    func bareKeysHaveSymbols(key: KeyEquivalent, symbol: String) throws {
        let app = TestApp(width: 40, height: 10) {
            Button("target") {}
                .contextMenu {
                    Button("Act") {}.keyboardShortcutHint(KeyboardShortcut(key, modifiers: []))
                }
        }
        app.press(.f10, modifiers: .shift)
        let row = try #require(app.screen.line(containing: "Act"), "\(app.screen)")
        #expect(row.contains(" \(symbol) "), "\(app.screen)")
    }

    @Test("A bound Return or Escape is named too, as the roles they are")
    func boundRolesAreNamed() throws {
        let app = TestApp(width: 40, height: 10) {
            Button("target") {}
                .contextMenu {
                    Button("Open Folder") {}.keyboardShortcut(.defaultAction)
                    Button("Up a Level") {}.keyboardShortcut(.cancelAction)
                }
        }
        app.press(.f10, modifiers: .shift)
        #expect(try #require(app.screen.line(containing: "Open Folder")).contains("↩"), "\(app.screen)")
        #expect(try #require(app.screen.line(containing: "Up a Level")).contains("⎋"), "\(app.screen)")
    }
}
