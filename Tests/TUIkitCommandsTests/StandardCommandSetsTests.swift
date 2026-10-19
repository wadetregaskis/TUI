//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StandardCommandSetsTests.swift
//
//  SwiftUI's opt-in command sets: SidebarCommands, InspectorCommands and
//  ToolbarCommands in the View menu, TextEditingCommands' Find… in Edit — each
//  doing what its key does, titled for the panel's state, disabled where
//  there is nothing to act on.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitApp
@testable import TUIkitCommands
@testable import TUIkitFoundation
import TUIkitNavigation
import TUIkitTextInput

// MARK: - Fixtures

/// The inspector's state, reachable from an `App`.
private final class InspectorProbe: @unchecked Sendable {
    static let shared = InspectorProbe()
    var presented = false
}

private struct SidebarApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { NavigationSplitView { Text("SIDEBAR") } detail: { Text("DETAIL") } }
            .commandsRemoved()
            .commands { SidebarCommands() }
    }
}

private struct NoSplitApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Button("PAGE") {} }
            .commandsRemoved()
            .commands { SidebarCommands() }
    }
}

private struct InspectorApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            Text("PAGE")
                .inspector(
                    isPresented: Binding(
                        get: { InspectorProbe.shared.presented }, set: { InspectorProbe.shared.presented = $0 })
                ) { Text("INSPECTOR") }
        }
        .commandsRemoved()
        .commands { InspectorCommands() }
    }
}

private struct ToolbarApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            Text("PAGE").toolbar { ToolbarItem(placement: .navigation) { Text("HEADER") } }
        }
        .commandsRemoved()
        .commands { ToolbarCommands() }
    }
}

private struct CustomizableToolbarApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            Text("PAGE").toolbar(id: "main") {
                ToolbarItem(id: "header", placement: .navigation) { Text("HEADER") }
                ToolbarItem(id: "extra", placement: .primaryAction) { Text("EXTRA") }
                    .defaultCustomization(.hidden)
            }
        }
        .defaultAppStorage(MemoryStore())
        .commandsRemoved()
        .commands { ToolbarCommands() }
    }
}

/// A store for one test's choices, so none is kept anywhere else.
private final class MemoryStore: StorageBackend, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private var keys: [String: StoredKey] = [:]
    private func stored(_ key: String) -> StoredKey {
        if let found = keys[key] { return found }
        let made = StoredKey()
        keys[key] = made
        return made
    }
    func entry<T: Codable>(forKey key: String, as type: T.Type) -> (value: T?, key: StoredKey) {
        (values[key].flatMap { try? JSONDecoder().decode(T.self, from: $0) }, stored(key))
    }
    func store<T: Codable>(_ value: T, forKey key: String) -> StoredKey {
        values[key] = try? JSONEncoder().encode(value)
        return stored(key)
    }
    func remove(forKey key: String) -> StoredKey? {
        values[key] = nil
        return keys[key]
    }
    func synchronize() {}
}

private struct FindApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { TextEditor(text: .constant("one two one")) }
            .commandsRemoved()
            .commands { TextEditingCommands() }
    }
}

// MARK: - Tests

@MainActor
@Suite("The standard command sets", .serialized)
struct StandardCommandSetsTests {
    private var now: Int64 = 0

    private mutating func frame<A: App>(_ app: HeadlessApp<A>) {
        now += 20_000_000
        app.frame(atNanos: now)
    }

    private func rows<A: App>(_ app: HeadlessApp<A>) -> [String] { app.screen.map(\.stripped) }

    /// A fresh app after two frames (the second adopts any toolbar).
    private mutating func launched<A: App>(_ app: A) -> HeadlessApp<A> {
        let headless = HeadlessApp(app, width: 60, height: 14)
        frame(headless)
        frame(headless)
        return headless
    }

    /// Opens the bar's only menu and chooses its first item.
    private mutating func chooseFirst<A: App>(in app: HeadlessApp<A>) {
        app.send(KeyEvent(key: .f10))
        frame(app)
        app.send(KeyEvent(key: .enter))
        frame(app)
        frame(app)
        frame(app)
    }

    /// The open menu's rows: every row below the bar.
    private mutating func menuRows<A: App>(of app: HeadlessApp<A>) -> [String] {
        app.send(KeyEvent(key: .f10))
        frame(app)
        let shown = Array(rows(app).dropFirst())
        app.send(KeyEvent(key: .escape))
        frame(app)
        return shown
    }

    @Test("SidebarCommands: View ▸ Hide Sidebar presses the split view's chord, and then reads Show Sidebar")
    mutating func sidebar() {
        let app = launched(SidebarApp())
        #expect(rows(app)[0].hasPrefix(" View"), "\(rows(app))")
        #expect(rows(app).contains { $0.contains("SIDEBAR") }, "sanity: the sidebar shows")
        let before = menuRows(of: app)
        #expect(before.contains { $0.contains("Hide Sidebar") && $0.contains("⌃S") }, "\(before)")
        chooseFirst(in: app)
        #expect(!rows(app).contains { $0.contains("SIDEBAR") }, "\(rows(app))")
        let after = menuRows(of: app)
        #expect(after.contains { $0.contains("Show Sidebar") }, "\(after)")
    }

    @Test("SidebarCommands with no split view on the screen: Show Sidebar, disabled")
    mutating func sidebarWithNoSplitView() {
        let app = launched(NoSplitApp())
        let menu = menuRows(of: app)
        #expect(menu.contains { $0.contains("Show Sidebar") }, "\(menu)")
        chooseFirst(in: app)
        #expect(rows(app).contains { $0.contains("PAGE") }, "nothing happened: \(rows(app))")
    }

    @Test("InspectorCommands: View ▸ Show Inspector presents the window's inspector")
    mutating func inspector() {
        InspectorProbe.shared.presented = false
        let app = launched(InspectorApp())
        let menu = menuRows(of: app)
        #expect(menu.contains { $0.contains("Show Inspector") }, "\(menu)")
        chooseFirst(in: app)
        #expect(InspectorProbe.shared.presented)
        #expect(rows(app).contains { $0.contains("INSPECTOR") }, "\(rows(app))")
    }

    @Test("ToolbarCommands: View ▸ Hide Toolbar takes the top bar away, and ⌥⌘T brings it back")
    mutating func toolbar() {
        let app = launched(ToolbarApp())
        #expect(rows(app).contains { $0.contains("HEADER") }, "sanity: the top bar shows")
        chooseFirst(in: app)
        #expect(!rows(app).contains { $0.contains("HEADER") }, "\(rows(app))")
        let menu = menuRows(of: app)
        #expect(menu.contains { $0.contains("Show Toolbar") }, "\(menu)")
        // ⌥⌘T under the default command key is ⌃⌥T.
        app.send(KeyEvent(key: .character("t"), ctrl: true, alt: true))
        frame(app)
        frame(app)
        #expect(rows(app).contains { $0.contains("HEADER") }, "\(rows(app))")
    }

    @Test("ToolbarCommands: View ▸ Customize Toolbar… opens the customizable toolbar's panel")
    mutating func customizeToolbar() {
        let app = launched(CustomizableToolbarApp())
        let menu = menuRows(of: app)
        #expect(menu.contains { $0.contains("Customize Toolbar") }, "\(menu)")
        app.send(KeyEvent(key: .f10))
        frame(app)
        app.send(KeyEvent(key: .down))
        frame(app)
        app.send(KeyEvent(key: .enter))
        frame(app)
        frame(app)
        frame(app)
        #expect(rows(app).contains { $0.contains("□") && $0.contains("EXTRA") }, "the panel: \(rows(app))")
    }

    @Test("TextEditingCommands: Edit ▸ Find… shows the focused editor's find bar")
    mutating func find() {
        let app = launched(FindApp())
        #expect(!rows(app).contains { $0.contains("Done") }, "sanity: no find bar")
        chooseFirst(in: app)
        #expect(rows(app).contains { $0.contains("Done") }, "\(rows(app))")
    }
}
