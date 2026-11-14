//  🖥️ TUI — A Terminal UI framework for Swift
//  TypeSelectGivesWayToOnKeyPressTests.swift
//
//  An app that puts commands on bare letters (`k` to kill, as `htop` does) and
//  shows a table: an `onKeyPress` on the table hears its letter ahead of type
//  select, as SwiftUI's does on macOS (measured:
//  `Tools/SwiftUIProbes/Table keys, type select and expansion (APPFB)`), and a
//  letter it does not take still reaches type select. This is the route the
//  status bar guide and the list and table guide give for a command on a bare
//  letter beside a table.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUIApp
@testable import TUICore
@testable import TUIFoundation
import TUITables
import TUITesting

private struct Process: Identifiable, Hashable, Sendable {
    let id: String
}

@Observable
@MainActor
private final class Commands {
    var killed: [String] = []
    var selection: String?
}

@MainActor
@Suite("Type select gives way to the table's own onKeyPress")
struct TypeSelectGivesWayToOnKeyPressTests {
    private let rows = ["alpha", "bravo", "kilo", "tango", "zulu"].map(Process.init)

    private func app(_ commands: Commands) -> TestApp {
        let app = TestApp(width: 40, height: 12) {
            Table(rows, selection: Binding(get: { commands.selection }, set: { commands.selection = $0 })) {
                TableColumn("Name", value: \Process.id)
            }
            .onKeyPress("k") {
                commands.killed.append(commands.selection ?? "none")
                return .handled
            }
        }
        app.press(.tab)
        return app
    }

    @Test("A bare letter the table's onKeyPress takes runs it and moves no cursor")
    func handlerFirst() {
        let commands = Commands()
        let app = app(commands)
        app.press(.down)
        app.press(.space)  // bravo
        app.press(.character("k"))
        #expect(commands.killed == ["bravo"])
        // The cursor is still on bravo, not on kilo: Down takes it to kilo.
        app.press(.down)
        app.press(.space)
        #expect(commands.selection == "kilo")
    }

    @Test("A letter it doesn't take still reaches type select")
    func otherLettersTypeSelect() {
        let commands = Commands()
        let app = app(commands)
        app.press(.character("z"))
        app.advance(by: .milliseconds(20))
        app.press(.space)
        #expect(commands.selection == "zulu")
        #expect(commands.killed.isEmpty)
    }
}
