//  🖥️ TUI — A Terminal UI framework for Swift
//  NavigationSplitViewColumnIdentityTests.swift
//
//  Two columns of a split view whose views are of one type are two views:
//  each keeps its own `@State`. By type alone they were one identity, and
//  shared it, side by side and collapsed alike.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
import TUITesting

/// A counter, the same type in two columns.
private struct ColumnCounter: View {
    let name: String
    @State private var count = 0

    var body: some View {
        Button("\(name) \(count)") { count += 1 }
    }
}

@MainActor
@Suite("A split view's columns of one type")
struct NavigationSplitViewColumnIdentityTests {
    @Test("Side by side, each column keeps its own state")
    func eachColumnKeepsItsState() throws {
        let app = TestApp(width: 90, height: 12) {
            NavigationSplitView {
                ColumnCounter(name: "Side")
            } content: {
                ColumnCounter(name: "Middle")
            } detail: {
                Text("detail")
            }
        }
        try app.click("Side 0")
        #expect(app.screen.contains("Side 1"), "\(app.screen)")
        #expect(app.screen.contains("Middle 0"), "\(app.screen)")
    }
}
