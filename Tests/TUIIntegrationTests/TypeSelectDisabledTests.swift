//  🖥️ TUI — A Terminal UI framework for Swift
//  TypeSelectDisabledTests.swift
//
//  `.typeSelectDisabled()` (the owner's APPFB-3, 2026-11-14): with type select
//  off, a focused list's or table's, an open `Picker` drop-down's and an open
//  pop-up menu's typed character moves nothing and goes on to the next
//  handler — a bare `.keyboardShortcut`, a status-bar item's action, a menu
//  row's bare key equivalent — where with it on, type select keeps it
//  (B77-KEYTIME). Each container is played through the input handler's whole
//  chain, as a person types.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUI
import TUITesting

@MainActor
private final class Log {
    var fired: [String] = []
    var selection: String?
    var choice = "Apple"
    var selectionBinding: Binding<String?> { Binding(get: { self.selection }, set: { self.selection = $0 }) }
    var choiceBinding: Binding<String> { Binding(get: { self.choice }, set: { self.choice = $0 }) }
}

private struct Row: Identifiable, Hashable, Sendable {
    let id: String
}

private let names = ["alpha", "bravo", "kilo", "zulu"]

/// A bare `k` shortcut beside `content`, which has the focus.
@MainActor
private func page(_ log: Log, @ViewBuilder _ content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        content()
        Button("Kill") { log.fired.append("k") }
            .keyboardShortcut("k", modifiers: [])
    }
}

/// A table, alone in its window, and a status bar with an item whose action is
/// on `n`.
private struct StatusBarApp: App {
    var log = Log()
    var disabled = false

    var body: some Scene {
        WindowGroup {
            Table(names.map(Row.init), selection: log.selectionBinding) {
                TableColumn("Name", value: \Row.id)
            }
            .typeSelectDisabled(disabled)
            .statusBarItems {
                StatusBarItem(shortcut: "n", label: "renew") { log.fired.append("n") }
            }
            .toolbar { ToolbarItem(placement: .bottomBar) { StatusBar() } }
        }
    }
}

@MainActor
@Suite("Type select disabled")
struct TypeSelectDisabledTests {
    /// Presses Return or Space on the cursor's row and answers the selection.
    private func selectCursor(_ app: TestApp, _ log: Log) -> String? {
        app.press(.space)
        return log.selection
    }

    @Test("A List with type select off gives a bare letter to the page's shortcut and moves no cursor", arguments: [true, false])
    func list(disabled: Bool) {
        let log = Log()
        let app = TestApp(width: 40, height: 12) {
            page(log) {
                List(names, id: \.self, selection: log.selectionBinding) { Text($0) }
                    .typeSelectDisabled(disabled)
            }
        }
        app.press(.character("k"))
        #expect(log.fired == (disabled ? ["k"] : []), "\(log.fired)")
        #expect(selectCursor(app, log) == (disabled ? "alpha" : "kilo"))
    }

    @Test("A Table with type select off gives a bare letter to the page's shortcut and moves no cursor", arguments: [true, false])
    func table(disabled: Bool) {
        let log = Log()
        let app = TestApp(width: 40, height: 12) {
            page(log) {
                Table(names.map(Row.init), selection: log.selectionBinding) {
                    TableColumn("Name", value: \Row.id)
                }
                .typeSelectDisabled(disabled)
            }
        }
        app.press(.character("k"))
        #expect(log.fired == (disabled ? ["k"] : []), "\(log.fired)")
        #expect(selectCursor(app, log) == (disabled ? "alpha" : "kilo"))
    }

    @Test("A focused table with type select off shows and fires a status-bar item on a bare letter", arguments: [true, false])
    func statusBarItem(disabled: Bool) {
        let log = Log()
        let app = TestApp(StatusBarApp(log: log, disabled: disabled), width: 60, height: 12)
        #expect(app.screen.contains("renew") == disabled, "\(app.screen)")
        app.press(.character("n"))
        #expect(log.fired == (disabled ? ["n"] : []), "\(log.fired)")
    }

    @Test("The nearest setting wins: .typeSelectDisabled(false) turns it back on inside a subtree that has it off")
    func nearestWins() {
        let log = Log()
        let app = TestApp(width: 40, height: 12) {
            page(log) {
                List(names, id: \.self, selection: log.selectionBinding) { Text($0) }
                    .typeSelectDisabled(false)
            }
            .typeSelectDisabled()
        }
        app.press(.character("k"))
        #expect(log.fired.isEmpty, "\(log.fired)")
        #expect(selectCursor(app, log) == "kilo")
    }

    @Test("An open Picker drop-down with type select off gives a bare letter to the page's shortcut", arguments: [true, false])
    func picker(disabled: Bool) {
        let log = Log()
        let app = TestApp(width: 40, height: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Picker("Fruit", selection: log.choiceBinding) {
                    Text("Apple").tag("Apple")
                    Text("Date").tag("Date")
                }
                .typeSelectDisabled(disabled)
                Button("Delete") { log.fired.append("d") }
                    .keyboardShortcut("d", modifiers: [])
            }
        }
        app.press(.enter)  // opens the focused picker's drop-down
        app.press(.character("d"))
        #expect(log.fired == (disabled ? ["d"] : []), "\(log.fired)")
        if !disabled {
            app.press(.enter)
            #expect(log.choice == "Date", "type select found Date: \(log.choice)")
        }
    }

    @Test("An open pop-up menu with type select off gives a bare letter to its row's key equivalent", arguments: [true, false])
    func menu(disabled: Bool) {
        let log = Log()
        let app = TestApp(width: 50, height: 16) {
            Menu("File") {
                Button("Open") { log.fired.append("Open") }
                Button("Export") { log.fired.append("Export") }
                    .keyboardShortcut("x", modifiers: [])
                Button("Xerox") { log.fired.append("Xerox") }
            }
            .typeSelectDisabled(disabled)
        }
        app.press(.enter)  // opens the focused menu, its first row highlighted
        app.press(.character("x"))
        if disabled {
            #expect(log.fired == ["Export"], "the row's key equivalent fired: \(log.fired)")
        } else {
            #expect(log.fired.isEmpty, "type select kept the key: \(log.fired)")
            app.press(.enter)
            #expect(log.fired == ["Xerox"], "type select found Xerox: \(log.fired)")
        }
    }
}
