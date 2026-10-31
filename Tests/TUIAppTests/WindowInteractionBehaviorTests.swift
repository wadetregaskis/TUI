//  🖥️ TUI — A Terminal UI framework for Swift
//  WindowInteractionBehaviorTests.swift
//
//  `windowDismissBehavior(_:)`: a window whose content disables its dismissal
//  is not closed by the person's ways — Escape, the Window menu's Close
//  Window — and its status bar does not offer Escape to close it; the app can
//  still close it, with `dismissWindow`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIFoundation

// MARK: - Fixtures

/// The main window: a button that opens the welcome window.
private struct MainPage: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("welcome") { openWindow(id: "welcome") }
    }
}

/// A window that only its own button closes.
private struct WelcomePage: View {
    @Environment(\.dismissWindow) private var dismissWindow
    let behavior: WindowInteractionBehavior

    var body: some View {
        VStack {
            Text("welcome window")
            Button("done") { dismissWindow() }
        }
        .toolbar { ToolbarItem(placement: .bottomBar) { StatusBar() } }
        .windowDismissBehavior(behavior)
    }
}

private struct WelcomeApp: App {
    let behavior: WindowInteractionBehavior

    init() { self.init(behavior: .automatic) }

    init(behavior: WindowInteractionBehavior) {
        self.behavior = behavior
    }

    var body: some Scene {
        WindowGroup { MainPage() }
        Window("Welcome", id: "welcome") { WelcomePage(behavior: behavior) }
    }
}

// MARK: - Tests

@MainActor
@Suite("A window's dismiss behavior", .serialized)
struct WindowInteractionBehaviorTests {
    private var now: Int64 = 0

    /// The app with its welcome window opened over the main one, drawn the
    /// one frame.
    private mutating func welcoming(_ behavior: WindowInteractionBehavior) -> HeadlessApp {
        let app = HeadlessApp(WelcomeApp(behavior: behavior), width: 50, height: 10)
        frame(app)
        press(.enter, in: app)
        return app
    }

    private mutating func frame(_ app: HeadlessApp) {
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

    @Test("Disabled, Escape leaves the window open and the status bar does not offer it, from the frame it opens")
    mutating func escapeDoesNotClose() {
        let app = welcoming(.disabled)
        #expect(screen(app).contains("welcome window"), "\(screen(app))")
        #expect(!screen(app).contains("close window"), "\(screen(app))")
        frame(app)
        #expect(!screen(app).contains("close window"), "\(screen(app))")
        press(.escape, in: app)
        frame(app)
        #expect(screen(app).contains("welcome window"), "\(screen(app))")
        #expect(app.scenes.windows.count == 2)
    }

    @Test("Disabled, the Window menu's Close Window is disabled and closes nothing")
    mutating func menuCannotClose() {
        let app = welcoming(.disabled)
        #expect(!app.scenes.canCloseFrontWindow)
        app.scenes.closeFrontWindow()
        frame(app)
        #expect(app.scenes.windows.count == 2)
    }

    @Test("Disabled, dismissWindow still closes the window: the app can")
    mutating func appStillCloses() {
        let app = welcoming(.disabled)
        press(.tab, in: app)
        press(.enter, in: app)
        frame(app)
        #expect(app.scenes.windows.count == 1, "\(screen(app))")
    }

    @Test("Enabled and automatic, Escape closes the window, as the status bar says", arguments: [
        WindowInteractionBehavior.enabled, .automatic,
    ])
    mutating func enabledCloses(_ behavior: WindowInteractionBehavior) {
        let app = welcoming(behavior)
        frame(app)
        #expect(screen(app).contains("close window"), "\(screen(app))")
        #expect(app.scenes.canCloseFrontWindow)
        press(.escape, in: app)
        frame(app)
        #expect(app.scenes.windows.count == 1, "\(screen(app))")
    }
}
