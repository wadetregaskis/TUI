//  🖥️ TUI — A Terminal UI framework for Swift
//  SettingsSceneTests.swift
//
//  The `Settings` scene (lane O9; decisions A26's settings scene): presented as
//  a sheet over the window in front by `openSettings` and `SettingsLink`,
//  closed by Escape or `dismiss()`, its own modifiers reaching its content
//  alone; and nothing at all where the app declares none.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIFoundation
import TUIPresentation
@testable import TUIScenes

// MARK: - Fixtures

/// A value a scene's environment carries.
private struct SceneNoteKey: EnvironmentKey {
    static let defaultValue = "unset"
}

extension EnvironmentValues {
    fileprivate var sceneNote: String {
        get { self[SceneNoteKey.self] }
        set { self[SceneNoteKey.self] = newValue }
    }
}

/// The main window: the note it sees, a counter, and the ways to the
/// settings.
private struct MainPage: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.sceneNote) private var note
    @State private var count = 0

    var body: some View {
        VStack {
            Text("main note=\(note) count=\(count)")
            Button("bump") { count += 1 }
            Button("settings") { openSettings() }
            SettingsLink()
        }
    }
}

/// The settings' content.
private struct SettingsPage: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sceneNote) private var note

    var body: some View {
        VStack {
            Text("settings note=\(note)")
            Button("done") { dismiss() }
        }
    }
}

private struct SettingsApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { MainPage() }
        Settings { SettingsPage() }
            .environment(\.sceneNote, "settings-only")
    }
}

private struct NoSettingsApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { MainPage() }
    }
}

// MARK: - Tests

@MainActor
@Suite("The Settings scene", .serialized)
struct SettingsSceneTests {
    private var now: Int64 = 0

    private mutating func frame(_ app: HeadlessApp) {
        now += 20_000_000
        app.frame(atNanos: now)
        now += 20_000_000
        app.frame(atNanos: now)
    }

    private mutating func press(_ key: Key, in app: HeadlessApp) {
        app.send(KeyEvent(key: key))
        frame(app)
    }

    private func screen(_ app: HeadlessApp) -> String {
        app.screen.map(\.stripped).joined(separator: "\n")
    }

    private mutating func launched<A: App>(_ app: A) -> HeadlessApp {
        let headless = HeadlessApp(app, width: 60, height: 14)
        frame(headless)
        return headless
    }

    @Test("openSettings presents the Settings scene as a sheet over the window, the window behind it")
    mutating func openSettingsPresentsSheet() {
        let app = launched(SettingsApp())
        #expect(!screen(app).contains("settings note"))
        press(.tab, in: app)
        press(.enter, in: app)  // settings
        let text = screen(app)
        #expect(text.contains("settings note=settings-only"), "\(text)")
        #expect(text.contains("main note=unset"), "the window shows through, dimmed: \(text)")
        #expect(app.scenes.isPresentingSettings)
        #expect(app.scenes.windows.count == 1, "a sheet, not a window")
    }

    @Test("Escape closes the settings, and the window's state is as it was")
    mutating func escapeCloses() {
        let app = launched(SettingsApp())
        press(.enter, in: app)  // bump
        press(.tab, in: app)
        press(.enter, in: app)  // settings
        press(.escape, in: app)
        #expect(!app.scenes.isPresentingSettings)
        #expect(screen(app).contains("main note=unset count=1"), "\(screen(app))")
        #expect(app.quitsRequested == 0)
    }

    @Test("dismiss() in the settings closes them, not the app")
    mutating func dismissCloses() {
        let app = launched(SettingsApp())
        press(.tab, in: app)
        press(.enter, in: app)  // settings
        press(.enter, in: app)  // done
        #expect(!app.scenes.isPresentingSettings)
        #expect(!screen(app).contains("settings note"))
        #expect(app.quitsRequested == 0)
    }

    @Test("A SettingsLink presents the settings, under its default label")
    mutating func settingsLink() {
        let app = launched(SettingsApp())
        #expect(screen(app).contains("Settings…"), "\(screen(app))")
        press(.tab, in: app)
        press(.tab, in: app)
        press(.enter, in: app)  // the link
        #expect(screen(app).contains("settings note=settings-only"), "\(screen(app))")
    }

    @Test("With no Settings scene, openSettings presents nothing and says so")
    mutating func noSettingsScene() {
        let app = launched(NoSettingsApp())
        press(.tab, in: app)
        press(.enter, in: app)
        #expect(!app.scenes.isPresentingSettings)
        #expect(!OpenSettingsAction(handler: app.scenes.actions).isAvailable)
        let withSettings = launched(SettingsApp())
        #expect(OpenSettingsAction(handler: withSettings.scenes.actions).isAvailable)
        withExtendedLifetime(withSettings) {}
    }
}
