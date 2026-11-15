//  🖥️ TUI — A Terminal UI framework for Swift
//  TestAppWindowTitleTests.swift
//
//  `TestApp.windowTitle`: the title the app has given the terminal's window,
//  which a test reads as an app's tests do, with no `@testable` (tuitree's
//  feedback, Milestone 2 item 9).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUITesting

private struct NotesApp: App {
    init() {}

    var body: some Scene {
        WindowGroup("Notes") { Text("notes window") }
    }
}

private struct PlainApp: App {
    init() {}

    var body: some Scene {
        WindowGroup { Text("plain window") }
    }
}

@MainActor
@Suite("A TestApp's window title")
struct TestAppWindowTitleTests {
    @Test("The scene's title is the window's")
    func sceneTitle() {
        let app = TestApp(NotesApp(), width: 40, height: 8)
        #expect(app.windowTitle == "Notes")
    }

    @Test("An app with no title leaves the window's own, and reads nil")
    func noTitle() {
        let app = TestApp(PlainApp(), width: 40, height: 8)
        #expect(app.windowTitle == nil)
    }
}
