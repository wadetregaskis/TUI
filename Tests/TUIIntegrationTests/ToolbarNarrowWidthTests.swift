//  🖥️ TUI — A Terminal UI framework for Swift
//  ToolbarNarrowWidthTests.swift
//
//  A top bar too narrow for its items: an item the bar has no cell left for
//  is drawn nowhere, so it takes no focus and no click, and its keyboard
//  shortcut still works.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
import TUITesting

/// What the bar's buttons did, reachable from an `App`.
@MainActor private final class CrowdedBarLog {
    static let shared = CrowdedBarLog()
    var actions: [String] = []
}

/// A window whose top bar holds a back button, a long title and two actions,
/// the first with a shortcut.
private struct CrowdedBarApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("PAGE")
                .navigationTitle("A long window title")
                .toolbar {
                    ToolbarItem(placement: .navigation) { Button("Back") {}.focusID("back") }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Add") { CrowdedBarLog.shared.actions.append("add") }
                            .focusID("add")
                            .keyboardShortcut("k", modifiers: .control)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Remove") { CrowdedBarLog.shared.actions.append("remove") }.focusID("remove")
                    }
                }
        }
    }
}

@MainActor
@Suite("A crowded top bar", .serialized)
struct ToolbarNarrowWidthTests {
    @Test("An item cut off by the bar's width takes no focus, and its shortcut still works")
    func cutOffItemTakesNoFocus() {
        CrowdedBarLog.shared.actions = []
        // Back, Add and Remove are 8, 7 and 10 cells, with a cell between each:
        // more than the 22 a 24-column bordered bar holds. The row cuts its
        // trailing items to nothing, and Tab still went to them: the focus on
        // a button nobody could see, and Return pressing it.
        let app = TestApp(CrowdedBarApp(), width: 24, height: 8)
        #expect(!app.screen.contains("Remove"), "the case this pins: \(app.screen)")
        var visited: Set<String> = []
        for _ in 0..<4 {
            app.press(.tab)
            if let id = app.focusedID { visited.insert(id) }
        }
        #expect(visited == ["back"], "\(visited)")
        app.press(.character("k"), modifiers: .control)
        #expect(CrowdedBarLog.shared.actions == ["add"])

        // Given the room, they are controls again.
        app.resize(width: 80, height: 8)
        visited = []
        for _ in 0..<3 {
            app.press(.tab)
            if let id = app.focusedID { visited.insert(id) }
        }
        #expect(visited == ["back", "add", "remove"], "\(visited)")
        app.press(.enter)
        #expect(CrowdedBarLog.shared.actions.last != nil)
    }
}
