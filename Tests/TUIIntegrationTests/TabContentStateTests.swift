//  🖥️ TUI — A Terminal UI framework for Swift
//  TabContentStateTests.swift
//
//  A tab's content keeps its `@State` while another tab is shown, as
//  SwiftUI's does and as `TabView`'s documentation says: a counter keeps its
//  count, and a navigation stack the screen it had pushed. A hidden tab was
//  neither drawn nor retained, so the prune at the end of the frame took its
//  state, and coming back to it started it over.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
import TUITesting

/// A button that counts its presses in its own `@State`.
private struct Counter: View {
    @State private var count = 0

    var body: some View {
        Button("Count \(String(count))") { count += 1 }
    }
}

/// Two tabs: the first with a counter over a navigation stack, the second
/// with nothing to keep.
private struct TwoTabs: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            Tab("One", systemImage: "1.circle", value: 0) {
                VStack {
                    Counter()
                    NavigationStack {
                        NavigationLink("Push", value: 5)
                            .navigationDestination(for: Int.self) { Text(verbatim: "PUSHED \($0)") }
                    }
                }
            }
            Tab("Two", systemImage: "2.circle", value: 1) { Text(verbatim: "SECOND TAB") }
        }
    }
}

@MainActor
@Suite("A tab's content keeps its state while another tab is shown")
struct TabContentStateTests {
    @Test("A counter in a tab keeps its count across a visit to another tab")
    func counterKeepsItsCount() throws {
        let app = TestApp(width: 50, height: 12) { TwoTabs() }
        try app.click("Count 0")
        try app.click("Count 1")
        try app.click("Two")
        #expect(app.screen.contains("SECOND TAB"), "\(app.screen)")
        try app.click("One")
        #expect(app.screen.contains("Count 2"), "\(app.screen)")
    }

    @Test("A navigation stack in a tab keeps its pushed screen, whether the tab is left by click or by key")
    func stackKeepsItsScreen() throws {
        let app = TestApp(width: 50, height: 12) { TwoTabs() }
        try app.click("Push")
        #expect(app.screen.contains("PUSHED 5"), "\(app.screen)")
        try app.click("Two")
        try app.click("One")
        #expect(app.screen.contains("PUSHED 5"), "\(app.screen)")
        // With the strip focused, the arrows switch tabs.
        try app.click("Two")
        app.press(.left)
        #expect(app.screen.contains("PUSHED 5"), "\(app.screen)")
    }
}
