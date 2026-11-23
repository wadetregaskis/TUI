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

import Foundation
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

/// A `Hashable` class with no description of its own: every instance prints
/// as its type's name, so a tab keyed by its value's description gave every
/// tab over one of these the same identity.
private final class Document: Hashable {
    static func == (lhs: Document, rhs: Document) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// Two tabs over `values`, each with a counter of its own.
private struct CounterTabs<Value: Hashable>: View {
    let values: [Value]
    @State private var selection: Value

    init(values: [Value]) {
        self.values = values
        _selection = State(initialValue: values[0])
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Alpha", value: values[0]) { Counter() }
            Tab("Beta", value: values[1]) { Counter() }
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

    /// Bumps the first tab's counter twice, then shows the second tab.
    private func bumpFirstThenShowSecond(_ app: TestApp) throws {
        try app.click("Count 0")
        try app.click("Count 1")
        try app.click("Beta")
    }

    @Test("Tabs over distinct instances of a description-less class keep separate state")
    func classValuedTabsKeepSeparateState() throws {
        // Made once: the closure runs every frame, and new instances are new tabs.
        let documents = [Document(), Document()]
        let app = TestApp(width: 50, height: 12) { CounterTabs(values: documents) }
        try bumpFirstThenShowSecond(app)
        #expect(app.screen.contains("Count 0"), "\(app.screen)")
        try app.click("Alpha")
        #expect(app.screen.contains("Count 2"), "\(app.screen)")
    }

    @Test("Tabs over two Dates within one second, which describe alike, keep separate state")
    func dateValuedTabsKeepSeparateState() throws {
        let first = Date(timeIntervalSinceReferenceDate: 0)
        let second = Date(timeIntervalSinceReferenceDate: 0.5)
        #expect(first.description == second.description)  // the premise: they print alike
        let app = TestApp(width: 50, height: 12) { CounterTabs(values: [first, second]) }
        try bumpFirstThenShowSecond(app)
        #expect(app.screen.contains("Count 0"), "\(app.screen)")
        try app.click("Alpha")
        #expect(app.screen.contains("Count 2"), "\(app.screen)")
    }
}
