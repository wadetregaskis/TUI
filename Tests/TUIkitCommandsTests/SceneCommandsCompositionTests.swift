//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SceneCommandsCompositionTests.swift
//
//  An app of several scenes has one menu bar: every scene's commands, in
//  declaration order, as SwiftUI's main menu has them (measured on macOS 15.8,
//  session notes `O9/probe/scenes.swift`), and a modifier written on several
//  scenes at once counted once.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitCommands
@testable import TUIkitFoundation

// MARK: - Fixtures

/// Each scene declares a menu; the second scene is not drawn.
private struct TwoScenesApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("PAGE") }
            .commandsRemoved()
            .commands { CommandMenu("Alpha") {} }
        WindowGroup { Text("OTHER") }
            .commandsRemoved()
            .commands { CommandMenu("Beta") {} }
    }
}

/// A menu declared around a group of two scenes that declare their own.
private struct GroupedApp: App {
    init() {}
    var body: some Scene {
        Group {
            WindowGroup { Text("PAGE") }.commands { CommandMenu("Alpha") {} }
            WindowGroup { Text("OTHER") }.commands { CommandMenu("Beta") {} }
        }
        .commandsReplaced { CommandMenu("Gamma") {} }
        .commands { CommandMenu("Delta") {} }
    }
}

// MARK: - Tests

@MainActor
@Suite("The commands of several scenes", .serialized)
struct SceneCommandsCompositionTests {
    /// `app` after two frames, as its rows, stripped.
    private func screen<A: App>(_ app: HeadlessApp<A>) -> [String] {
        app.frame(atNanos: 0)
        app.frame(atNanos: 20_000_000)
        return app.screen.map(\.stripped)
    }

    @Test("Every scene's commands stand in the menu bar, in declaration order")
    func everySceneInOrder() {
        let rows = screen(HeadlessApp(TwoScenesApp(), width: 40, height: 6))
        #expect(rows[0].hasPrefix(" Alpha  Beta"), "\(rows)")
        #expect(rows.contains { $0.contains("PAGE") }, "the first scene is drawn: \(rows)")
    }

    @Test("A modifier on a group of scenes applies once, to all of them: one taking theirs away takes both")
    func groupModifierOnce() {
        let rows = screen(HeadlessApp(GroupedApp(), width: 40, height: 6))
        #expect(rows[0].hasPrefix(" Gamma  Delta"), "\(rows)")
        #expect(!rows[0].contains("Alpha") && !rows[0].contains("Beta"), "\(rows)")
    }
}
