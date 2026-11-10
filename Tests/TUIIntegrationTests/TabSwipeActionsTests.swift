//  🖥️ TUI — A Terminal UI framework for Swift
//  TabSwipeActionsTests.swift
//
//  `TabContent.swipeActions(edge:allowsFullSwipe:content:)`: a tab's row in a
//  `.sidebarAdaptable` sidebar reveals its actions as a list row does
//  (A48, `SwipeActionsTests`); a strip shows none.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

@Observable
@MainActor
private final class Folders {
    var selected = 1
    var ran: [String] = []
}

private struct FoldersApp: App {
    let folders: Folders?
    let sidebar: Bool

    init() {
        folders = nil
        sidebar = true
    }

    init(_ folders: Folders, sidebar: Bool) {
        self.folders = folders
        self.sidebar = sidebar
    }

    var body: some Scene {
        WindowGroup {
            if let folders { FoldersPage(folders: folders, sidebar: sidebar) }
        }
        .mouseSupport(.full)
    }
}

private struct FoldersPage: View {
    @Bindable var folders: Folders
    let sidebar: Bool

    var body: some View {
        let tabs = TabView(selection: $folders.selected) {
            // Titles wider than the buttons: the sidebar is as wide as its
            // titles, and actions wider than a row are drawn shortened.
            Tab("Inbox messages", value: 1) { Text("inbox content") }
                .swipeActions {
                    Button("Empty") { folders.ran.append("empty") }
                }
                .swipeActions(edge: .leading) {
                    Button("Pin") { folders.ran.append("pin") }
                }
                // Written further from the tab: the nearer one wins.
                .swipeActions {
                    Button("Ignored") { folders.ran.append("ignored") }
                }
            Tab("Drafts messages", value: 2) { Text("drafts content") }
        }
        if sidebar {
            tabs.tabViewStyle(.sidebarAdaptable)
        } else {
            tabs
        }
    }
}

@MainActor
private final class Harness {
    let folders = Folders()
    let app: TestApp
    private var now: Int64 = 0

    init(sidebar: Bool = true) {
        app = TestApp(FoldersApp(folders, sidebar: sidebar), width: 60, height: 10)
        frame()
        frame()
    }

    func frame() {
        now += 16_666_667
        app.frame(atNanos: now)
    }

    func key(_ key: Key, shift: Bool = false) {
        app.send(KeyEvent(key: key, shift: shift))
        frame()
    }

    func shows(_ text: String) -> Bool { app.screen.contains(text) }

    func row(of text: String) -> Int? { app.screen.styledLines.firstIndex { $0.stripped.contains(text) } }

    var screen: String { app.screen.lines.joined(separator: "\n") }
}

@MainActor
@Suite("A tab's swipe actions", .serialized)
struct TabSwipeActionsTests {
    @Test("⇧← reveals a sidebar row's trailing actions on its line, and Return presses the first")
    func trailing() throws {
        let harness = Harness()
        #expect(!harness.shows("Empty"), "\(harness.screen)")
        harness.key(.left, shift: true)
        let empty = try #require(harness.row(of: "Empty"), "not revealed: \(harness.screen)")
        #expect(empty == harness.row(of: "Inbox"), "\(harness.screen)")
        #expect(!harness.shows("Ignored"), "the set further from the tab was revealed: \(harness.screen)")
        harness.key(.enter)
        #expect(harness.folders.ran == ["empty"])
        #expect(!harness.shows("Empty"), "pressing slid them away: \(harness.screen)")
    }

    @Test("⇧→ reveals the leading actions; the same chord again is the full swipe")
    func leadingFullSwipe() {
        let harness = Harness()
        harness.key(.right, shift: true)
        #expect(harness.shows("Pin"), "\(harness.screen)")
        harness.key(.right, shift: true)
        #expect(harness.folders.ran == ["pin"])
    }

    @Test("A tab without actions reveals none")
    func noActions() {
        let harness = Harness()
        harness.key(.down)
        harness.key(.left, shift: true)
        #expect(!harness.shows("Empty") && !harness.shows("Pin"), "\(harness.screen)")
        #expect(harness.folders.ran.isEmpty)
    }

    @Test("A strip has no rows to swipe, so it shows none")
    func stripShowsNone() {
        let harness = Harness(sidebar: false)
        harness.key(.left, shift: true)
        harness.key(.right, shift: true)
        #expect(!harness.shows("Empty") && !harness.shows("Pin"), "\(harness.screen)")
        #expect(harness.folders.ran.isEmpty)
    }
}
