//  🖥️ TUI — A Terminal UI framework for Swift
//  StandardCommandSetsTests.swift
//
//  SwiftUI's opt-in command sets: SidebarCommands, InspectorCommands and
//  ToolbarCommands in the View menu, TextEditingCommands' Find… and Find Next
//  in Edit — each doing what its key does, titled for the panel's state,
//  disabled where there is nothing to act on — and the scene's own View ▸
//  Customize Toolbar…, wherever a customizable toolbar shows.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICommands
@testable import TUIFoundation
import TUINavigation
import TUITesting
import TUITextInput

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

/// A page with a customizable toolbar, one of whose items starts out of the
/// bar: the panel lists it unchecked.
private struct CustomizablePage: View {
    var body: some View {
        Text("PAGE").toolbar(id: "main") {
            ToolbarItem(id: "header", placement: .navigation) { Text("HEADER") }
            ToolbarItem(id: "extra", placement: .primaryAction) { Text("EXTRA") }
                .defaultCustomization(.hidden)
        }
    }
}

private struct CustomizableToolbarApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { CustomizablePage() }
            .defaultAppStorage(MemoryStore())
            .commandsRemoved()
            .commands { ToolbarCommands() }
    }
}

/// A customizable toolbar, with the scene's own commands and no
/// `ToolbarCommands`.
private struct OwnCustomizeApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { CustomizablePage() }
            .defaultAppStorage(MemoryStore())
            .commands { CommandMenu("Note") {} }
    }
}

/// The same, with `ToolbarCommands` as well.
private struct OwnAndToolbarCommandsApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { CustomizablePage() }
            .defaultAppStorage(MemoryStore())
            .commands { ToolbarCommands() }
    }
}

/// A toolbar that is not customizable, with the scene's own commands.
private struct OwnPlainToolbarApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            Text("PAGE").toolbar { ToolbarItem(placement: .navigation) { Text("HEADER") } }
        }
        .commands { CommandMenu("Note") {} }
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

/// What the item after Find… and Find Next did.
private final class FindProbe: @unchecked Sendable {
    static let shared = FindProbe()
    var chosen = 0
}

/// A button, then an editor that can find, with an item of the app's after
/// Find… and Find Next: where they are disabled, the menu opens with that
/// item highlighted.
private struct FindElsewhereApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            VStack {
                Button("PAGE") {}
                TextEditor(text: .constant("one two one"))
            }
        }
        .commandsRemoved()
        .commands {
            TextEditingCommands()
            CommandGroup(after: .textEditing) { Button("Probe") { FindProbe.shared.chosen += 1 } }
        }
    }
}

/// The same, with an editor whose find bar is disabled.
private struct FindDisabledApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { TextEditor(text: .constant("one two one")).findDisabled() }
            .commandsRemoved()
            .commands {
                TextEditingCommands()
                CommandGroup(after: .textEditing) { Button("Probe") { FindProbe.shared.chosen += 1 } }
            }
    }
}

// MARK: - Tests

@MainActor
@Suite("The standard command sets", .serialized)
struct StandardCommandSetsTests {
    private var now: Int64 = 0

    private mutating func frame(_ app: TestApp) {
        now += 20_000_000
        app.frame(atNanos: now)
    }

    private func rows(_ app: TestApp) -> [String] { app.screen.lines }

    /// A fresh app after two frames (the second adopts any toolbar).
    private mutating func launched<A: App>(_ app: A) -> TestApp {
        let headless = TestApp(app, width: 60, height: 14)
        frame(headless)
        frame(headless)
        return headless
    }

    /// Opens the bar's only menu and chooses its first item.
    private mutating func chooseFirst(in app: TestApp) {
        app.send(KeyEvent(key: .f10))
        frame(app)
        app.send(KeyEvent(key: .down))
        frame(app)
        app.send(KeyEvent(key: .enter))
        frame(app)
        frame(app)
        frame(app)
    }

    /// The open menu's rows: every row below the bar.
    private mutating func menuRows(of app: TestApp) -> [String] {
        app.send(KeyEvent(key: .f10))
        frame(app)
        app.send(KeyEvent(key: .down))
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
        app.send(KeyEvent(key: .down))
        frame(app)
        app.send(KeyEvent(key: .enter))
        frame(app)
        frame(app)
        frame(app)
        #expect(rows(app).contains { $0.contains("□") && $0.contains("EXTRA") }, "the panel: \(rows(app))")
    }

    /// The View menu's rows, opened from the keyboard: F10, then right to
    /// View, the bar's third menu after the app's and Edit.
    private mutating func viewMenuRows(of app: TestApp) -> [String] {
        #expect(rows(app)[0].contains("  Edit  View  "), "\(rows(app)[0])")
        app.send(KeyEvent(key: .f10))
        frame(app)
        app.send(KeyEvent(key: .down))
        frame(app)
        app.send(KeyEvent(key: .right))
        frame(app)
        app.send(KeyEvent(key: .right))
        frame(app)
        let shown = Array(rows(app).dropFirst())
        app.send(KeyEvent(key: .escape))
        frame(app)
        return shown
    }

    @Test("Without ToolbarCommands, F10 then View ▸ Customize Toolbar… opens the customizable toolbar's panel")
    mutating func ownCustomizeToolbar() {
        let app = launched(OwnCustomizeApp())
        let menu = viewMenuRows(of: app)
        #expect(menu.contains { $0.contains("Customize Toolbar") }, "\(menu)")
        #expect(!rows(app).contains { $0.contains("□") && $0.contains("EXTRA") }, "sanity: no panel yet")
        app.send(KeyEvent(key: .f10))
        frame(app)
        app.send(KeyEvent(key: .down))
        frame(app)
        app.send(KeyEvent(key: .right))
        frame(app)
        app.send(KeyEvent(key: .right))
        frame(app)
        app.send(KeyEvent(key: .enter))
        frame(app)
        frame(app)
        frame(app)
        #expect(rows(app).contains { $0.contains("□") && $0.contains("EXTRA") }, "the panel: \(rows(app))")
    }

    @Test("With no customizable toolbar the scene offers no Customize Toolbar…, and no View menu for it")
    mutating func noOwnCustomizeToolbarWithoutOne() {
        let app = launched(OwnPlainToolbarApp())
        #expect(rows(app).contains { $0.contains("HEADER") }, "sanity: the top bar shows")
        let bar = rows(app)[0]
        #expect(bar.contains("Edit") && bar.contains("Note"), "sanity: \(bar)")
        #expect(!bar.contains("View"), "\(bar)")
    }

    @Test("With ToolbarCommands too, the View menu has one Customize Toolbar…, after Hide Toolbar")
    mutating func oneCustomizeToolbarWithToolbarCommands() {
        let app = launched(OwnAndToolbarCommandsApp())
        let menu = viewMenuRows(of: app)
        let items = menu.indices.filter { menu[$0].contains("Customize Toolbar") }
        #expect(items.count == 1, "\(menu)")
        let hide = menu.firstIndex { $0.contains("Hide Toolbar") } ?? menu.count
        #expect(items.allSatisfy { $0 > hide }, "\(menu)")
    }

    @Test("TextEditingCommands: Edit ▸ Find… (⌃F) shows the focused editor's find bar; Find Next is ⌃G")
    mutating func find() {
        let app = launched(FindApp())
        #expect(!rows(app).contains { $0.contains("Done") }, "sanity: no find bar")
        let shown = menuRows(of: app)
        #expect(shown.contains { $0.contains("Find…") && $0.contains("⌃F") }, "\(shown)")
        #expect(shown.contains { $0.contains("Find Next") && $0.contains("⌃G") }, "\(shown)")
        chooseFirst(in: app)
        #expect(rows(app).contains { $0.contains("Done") }, "\(rows(app))")
    }

    @Test("TextEditingCommands: Find… and Find Next are disabled until an editor that can find has the focus")
    mutating func findDisabledElsewhere() {
        FindProbe.shared.chosen = 0
        let app = launched(FindElsewhereApp())
        chooseFirst(in: app)
        #expect(FindProbe.shared.chosen == 1, "the highlight started past Find… and Find Next")
        #expect(!rows(app).contains { $0.contains("Done") }, "\(rows(app))")
        app.send(KeyEvent(key: .tab))
        frame(app)
        chooseFirst(in: app)
        #expect(FindProbe.shared.chosen == 1)
        #expect(rows(app).contains { $0.contains("Done") }, "the editor has the focus: \(rows(app))")
    }

    @Test("TextEditingCommands: Find… and Find Next are disabled for an editor whose find bar is")
    mutating func findDisabledEditor() {
        FindProbe.shared.chosen = 0
        let app = launched(FindDisabledApp())
        chooseFirst(in: app)
        #expect(FindProbe.shared.chosen == 1, "the highlight started past Find… and Find Next")
    }
}
