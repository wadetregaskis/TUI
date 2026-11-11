//  🖥️ TUI — A Terminal UI framework for Swift
//  SceneMenuBarTests.swift
//
//  The menu bar's scene items (lane O9, decisions B-O13-7): the app menu's
//  Settings…, for an app that declares a `Settings` scene, showing its key —
//  ⌘, or its `.keyboardShortcut` — which works with the menus closed or no
//  menu bar at all; and the Window menu — Close Window, the open windows with
//  the one in front checked, the `Window` scenes — for an app that can open
//  more than one window, whether of several scenes or of one window group.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICommands
@testable import TUIFoundation
import TUIPresentation
@testable import TUIScenes
import TUITesting

// MARK: - Fixtures

private struct SettingsMenuApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("main window") }
            .commands { CommandMenu("Note") {} }
        Settings { Text("settings content") }
    }
}

private struct PlainMenuApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("main window") }
            .commands { CommandMenu("Note") {} }
    }
}

/// The same, with TUI's settings tabs hidden: a settings panel with nothing
/// to show.
private struct NoSettingsTabsMenuApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("main window") }
            .commands { CommandMenu("Note") {} }
            .builtInSettingsTab(.view, visibility: .hidden)
            .builtInSettingsTab(.accessibility, visibility: .hidden)
    }
}

/// A Settings scene on a key of its own.
private struct SettingsKeyApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("main window") }
            .commands { CommandMenu("Note") {} }
        Settings { Text("settings content") }
            .keyboardShortcut("p")
    }
}

/// A Settings scene on ⌘H, which a terminal's legacy encoding sends as
/// Backspace: a key that arrives only under the kitty keyboard protocol.
private struct SettingsBackspaceKeyApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("main window") }
            .commands { CommandMenu("Note") {} }
        Settings { Text("settings content") }
            .keyboardShortcut("h")
    }
}

/// A Settings scene with its key taken away.
private struct SettingsNoKeyApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("main window") }
        Settings { Text("settings content") }
            .keyboardShortcut(nil)
    }
}

/// A Settings scene in an app with no menu bar.
private struct SettingsBarlessApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("main window") }
        Settings { Text("settings content") }
    }
}

/// The apps with a Window menu name themselves (`aboutPanel`), or the
/// app menu takes the process's name: the test runner's, which Swift 6.4's
/// SwiftPM on Linux makes `TUIScenesTests-test-runner`, long enough to push
/// the Window menu under the 60-column bar's `»` (CI 103). Every scene names
/// it: the bar reads the environment of the window in front, so a name given
/// only to the main group was lost when the Inspector came forward (CI 105).
private struct WindowsMenuApp: App {
    init() {}
    var body: some Scene {
        WindowGroup("Notes") { Text("main window") }
            .commands { CommandMenu("Note") {} }
            .aboutPanel(applicationName: "Notes")
        Window("Inspector", id: "inspector") { Text("inspector window") }
            .aboutPanel(applicationName: "Notes")
    }
}

/// A visibility toggle in a menu of the app's own.
private struct ToggleMenuApp: App {
    init() {}
    var body: some Scene {
        WindowGroup("Notes") { Text("main window") }
            .commands { CommandMenu("Panels") { WindowVisibilityToggle(windowID: "inspector") } }
            .aboutPanel(applicationName: "Notes")
        Window("Inspector", id: "inspector") { Text("inspector window") }
            .aboutPanel(applicationName: "Notes")
    }
}

/// One window group, which its own button opens more windows of.
private struct DocumentsMenuApp: App {
    init() {}
    var body: some Scene {
        WindowGroup(id: "doc") { DocumentPage() }
            .commands { CommandMenu("Note") {} }
            .aboutPanel(applicationName: "Notes")
    }
}

private struct DocumentPage: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("another") { openWindow(id: "doc") }
    }
}

// MARK: - Tests

@MainActor
@Suite("The menu bar's scene items", .serialized)
struct SceneMenuBarTests {
    private var now: Int64 = 0

    private mutating func frame(_ app: TestApp) {
        now += 20_000_000
        app.frame(atNanos: now)
    }

    private mutating func launched<A: App>(_ app: A, height: Int = 14) -> TestApp {
        let headless = TestApp(app, width: 60, height: height)
        frame(headless)
        frame(headless)
        return headless
    }

    private func rows(_ app: TestApp) -> [String] { app.screen.lines }

    private func screen(_ app: TestApp) -> String { rows(app).joined(separator: "\n") }

    /// Opens the menu titled `title` from the keyboard: F10, Right along the
    /// titles to it, and Down.
    private mutating func open(_ title: String, in app: TestApp) {
        let titles = rows(app)[0].split(separator: " ").map(String.init)
        let index = titles.firstIndex(of: title) ?? 0
        app.send(KeyEvent(key: .f10))
        frame(app)
        for _ in 0..<index {
            app.send(KeyEvent(key: .right))
            frame(app)
        }
        app.send(KeyEvent(key: .down))
        frame(app)
    }

    /// Chooses the item `downs` places past the open menu's first.
    private mutating func choose(item downs: Int, in app: TestApp) {
        for _ in 0..<downs {
            app.send(KeyEvent(key: .down))
            frame(app)
        }
        app.send(KeyEvent(key: .enter))
        frame(app)
        frame(app)
    }

    @Test("An app with a Settings scene has Settings… in its app menu, showing ⌘, as the command key, and it presents them")
    mutating func settingsItem() {
        let app = launched(SettingsMenuApp())
        // Where ⌃, can arrive: under the kitty keyboard protocol.
        app.keyboardReporting = KeyboardReporting(flags: .requested)
        frame(app)
        open(EnvironmentValues().resolvedAboutPanel.name, in: app)
        #expect(screen(app).contains("Settings…") && screen(app).contains("⌃,"), "\(screen(app))")
        choose(item: 1, in: app)  // About, Settings…
        #expect(screen(app).contains("settings content"), "\(screen(app))")
        #expect(app.scenes.isPresentingSettings)
    }

    @Test("Settings…'s key works with every menu closed")
    mutating func settingsKey() {
        let app = launched(SettingsMenuApp())
        app.send(KeyEvent(key: .character(","), ctrl: true))
        frame(app)
        frame(app)
        #expect(app.scenes.isPresentingSettings, "\(screen(app))")
    }

    @Test("A Settings scene's own key presents it, and Settings… shows that key instead of ⌘,")
    mutating func settingsOwnKey() {
        let app = launched(SettingsKeyApp())
        app.send(KeyEvent(key: .character(","), ctrl: true))
        frame(app)
        #expect(!app.scenes.isPresentingSettings, "⌘, is not its key now")
        open(EnvironmentValues().resolvedAboutPanel.name, in: app)
        #expect(screen(app).contains("⌃P") && !screen(app).contains("⌃,"), "\(screen(app))")
        app.send(KeyEvent(key: .escape))
        frame(app)
        app.send(KeyEvent(key: .character("p"), ctrl: true))
        frame(app)
        frame(app)
        #expect(app.scenes.isPresentingSettings, "\(screen(app))")
    }

    /// The rows of F1's list, taken down again.
    private mutating func shortcutList(_ app: TestApp) -> [String] {
        app.send(KeyEvent(key: .f1))
        frame(app)
        let listed = rows(app)
        app.send(KeyEvent(key: .escape))
        frame(app)
        return listed
    }

    /// The open app menu's Settings… row, the menu closed again.
    private mutating func settingsRow(_ app: TestApp) -> String {
        open(EnvironmentValues().resolvedAboutPanel.name, in: app)
        let row = rows(app).first { $0.contains("Settings…") } ?? ""
        app.send(KeyEvent(key: .escape))
        frame(app)
        return row
    }

    @Test("Where the terminal cannot send the Settings key, Settings… and F1's list show F2 instead")
    mutating func undeliverableSettingsKey() {
        let app = launched(SettingsBackspaceKeyApp(), height: 40)
        let row = settingsRow(app)
        #expect(row.contains("F2") && !row.contains("⌃H"), "⌃H arrives as Backspace: \(row)")
        let listed = shortcutList(app)
        #expect(!listed.contains { $0.contains("⌃H") }, "\(listed.joined(separator: "\n"))")
        #expect(listed.contains { $0.contains("F2") && $0.contains("Settings…") }, "\(listed.joined(separator: "\n"))")

        // Under the kitty keyboard protocol it arrives, and both name it.
        let kitty = launched(SettingsBackspaceKeyApp(), height: 40)
        kitty.keyboardReporting = KeyboardReporting(flags: .requested)
        frame(kitty)
        #expect(settingsRow(kitty).contains("⌃H"))
        #expect(shortcutList(kitty).contains { $0.contains("⌃H") && $0.contains("Settings…") })
    }

    // ⌃, has no byte of its own in a legacy encoding. Whether it can arrive
    // is `KeyboardShortcut.isDeliverableInTerminal`'s to say (the menus
    // lane's ebcbd35c1 makes it answer `false`), and the list follows that
    // rule, whatever it answers.
    @Test("⌘,'s Settings… is named ⌃, exactly where the shared rule says the chord can arrive")
    mutating func commaFollowsTheSharedRule() {
        let arrives = KeyboardShortcut(",", modifiers: .control).isDeliverableInTerminal
        let app = launched(SettingsMenuApp(), height: 40)
        let row = settingsRow(app)
        #expect(row.contains("⌃,") == arrives && row.contains("F2") == !arrives, "\(row)")
        let listed = shortcutList(app)
        #expect(listed.contains { $0.contains("⌃,") && $0.contains("Settings…") } == arrives)
        #expect(listed.contains { $0.contains("F2") && $0.contains("Settings…") })
    }

    @Test("A Settings scene's key taken away with nil: ⌘, does nothing")
    mutating func settingsKeyRemoved() {
        let app = launched(SettingsNoKeyApp())
        app.send(KeyEvent(key: .character(","), ctrl: true))
        frame(app)
        #expect(!app.scenes.isPresentingSettings)
    }

    @Test("⌘, presents the Settings scene in an app with no menu bar")
    mutating func settingsKeyWithoutMenuBar() {
        let app = launched(SettingsBarlessApp())
        app.send(KeyEvent(key: .character(","), ctrl: true))
        frame(app)
        frame(app)
        #expect(app.scenes.isPresentingSettings, "\(screen(app))")
        #expect(screen(app).contains("settings content"), "\(screen(app))")
    }

    // Until 2026-11-08 an app with no `Settings` scene had no item: now
    // every app has the settings panel, with TUI's tabs, as SwiftUI adds
    // Settings… to every app menu.
    @Test("An app with no Settings scene has Settings… for TUI's tabs, and none once it hides them")
    mutating func noSettingsItem() {
        let app = launched(PlainMenuApp())
        open(EnvironmentValues().resolvedAboutPanel.name, in: app)
        #expect(screen(app).contains("About") && screen(app).contains("Settings…"), "\(screen(app))")
        let hidden = launched(NoSettingsTabsMenuApp())
        open(EnvironmentValues().resolvedAboutPanel.name, in: hidden)
        #expect(screen(hidden).contains("About") && !screen(hidden).contains("Settings…"), "\(screen(hidden))")
    }

    @Test("An app of one window scene has no Window menu")
    mutating func noWindowMenu() {
        let app = launched(PlainMenuApp())
        #expect(!rows(app)[0].contains("Window"), "\(rows(app)[0])")
    }

    @Test("An app of one window group that opens more of its windows has a Window menu, listing them")
    mutating func windowMenuForOneGroup() {
        let app = launched(DocumentsMenuApp())
        #expect(rows(app)[0].contains("Window"), "\(rows(app)[0])")
        app.send(KeyEvent(key: .enter))
        frame(app)
        frame(app)
        #expect(app.scenes.windows.count == 2, "precondition: a second window open")
        open("Window", in: app)
        // Close Window, then the windows, back to front.
        choose(item: 1, in: app)
        #expect(app.scenes.windows.count == 2, "brought to the front, not closed")
        #expect(app.scenes.windows.last?.serial == 0, "the first window is in front again")
    }

    @Test("The Window menu lists the Window scenes, and opens one")
    mutating func windowMenuOpensScene() {
        let app = launched(WindowsMenuApp())
        #expect(rows(app)[0].contains("Window"), "\(rows(app)[0])")
        open("Window", in: app)
        let text = screen(app)
        #expect(text.contains("Close Window") && text.contains("Notes") && text.contains("Inspector"), "\(text)")
        // Close Window is disabled with one window open, so the highlight
        // starts on the windows: Notes, then Inspector.
        choose(item: 1, in: app)
        #expect(screen(app).contains("inspector window"), "\(screen(app))")
        #expect(app.scenes.windows.count == 2)
    }

    @Test("The Window menu lists the open windows, and brings one to the front")
    mutating func windowMenuFrontsWindow() {
        let app = launched(WindowsMenuApp())
        app.scenes.open(WindowTarget(id: "inspector"))
        frame(app)
        frame(app)
        open("Window", in: app)
        // Close Window, then the windows — Notes, Inspector (in front) — then
        // the Window scenes.
        choose(item: 1, in: app)
        #expect(screen(app).contains("main window"), "\(screen(app))")
        #expect(app.scenes.windows.count == 2, "brought to the front, not closed")
    }

    @Test("A visibility toggle chosen from its menu hides the window in front: the open menu is no presentation that keeps it")
    mutating func toggleFromMenu() {
        let app = launched(ToggleMenuApp())
        app.scenes.open(WindowTarget(id: "inspector"))
        frame(app)
        frame(app)
        open("Panels", in: app)
        #expect(screen(app).contains("Hide Inspector"), "\(screen(app))")
        choose(item: 0, in: app)
        #expect(app.scenes.windows.count == 1, "\(screen(app))")
        #expect(screen(app).contains("main window"), "\(screen(app))")
    }

    @Test("Close Window closes the window in front")
    mutating func closeWindow() {
        let app = launched(WindowsMenuApp())
        app.scenes.open(WindowTarget(id: "inspector"))
        frame(app)
        frame(app)
        open("Window", in: app)
        choose(item: 0, in: app)
        #expect(app.scenes.windows.count == 1)
        #expect(screen(app).contains("main window"), "\(screen(app))")
        #expect(app.quitsRequested == 0)
    }
}
