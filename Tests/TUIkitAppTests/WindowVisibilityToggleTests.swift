//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WindowVisibilityToggleTests.swift
//
//  `WindowVisibilityToggle`: "Show *Title*" while its `Window` scene's window
//  is not in front, which opens it or brings it there; "Hide *Title*" while it
//  is, which closes it; disabled for an identifier no `Window` scene has.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitFoundation

// MARK: - Fixtures

private struct ToggleApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            VStack {
                Text("main window")
                WindowVisibilityToggle(windowID: "library")
                WindowVisibilityToggle(windowID: "no-such-window")
            }
        }
        Window("Library", id: "library") {
            VStack {
                Text("library window")
                WindowVisibilityToggle(windowID: "library")
            }
        }
    }
}

// MARK: - Tests

@MainActor
@Suite("Window visibility toggles", .serialized)
struct WindowVisibilityToggleTests {
    private var now: Int64 = 0

    private mutating func launched() -> HeadlessApp<ToggleApp> {
        let app = HeadlessApp(ToggleApp(), width: 50, height: 10)
        frame(app)
        frame(app)
        return app
    }

    private mutating func frame(_ app: HeadlessApp<ToggleApp>) {
        now += 20_000_000
        app.frame(atNanos: now)
    }

    private mutating func press(_ key: Key, in app: HeadlessApp<ToggleApp>) {
        app.send(KeyEvent(key: key))
        frame(app)
        frame(app)
    }

    private func screen(_ app: HeadlessApp<ToggleApp>) -> String {
        app.screen.map(\.stripped).joined(separator: "\n")
    }

    @Test("Its label shows the window while it is not in front, and choosing it shows it")
    mutating func showsTheWindow() {
        let app = launched()
        #expect(screen(app).contains("Show Library"), "\(screen(app))")
        press(.enter, in: app)
        #expect(screen(app).contains("library window"), "\(screen(app))")
        #expect(app.scenes.windows.count == 2)
    }

    @Test("In front, its label hides the window, and choosing it closes the window")
    mutating func hidesTheWindow() {
        let app = launched()
        press(.enter, in: app)
        #expect(screen(app).contains("Hide Library"), "\(screen(app))")
        press(.enter, in: app)
        #expect(screen(app).contains("main window"), "\(screen(app))")
        #expect(app.scenes.windows.count == 1)
    }

    @Test("An identifier no Window scene has leaves the toggle disabled")
    mutating func unknownIdentifierIsDisabled() {
        let app = launched()
        #expect(screen(app).contains("Show no-such-window"), "\(screen(app))")
        // Tab passes over it: the focus comes back to the first toggle.
        press(.tab, in: app)
        press(.enter, in: app)
        #expect(app.scenes.windows.count == 2, "\(screen(app))")
        #expect(!app.scenes.isShowingWindow("no-such-window"))
    }
}
