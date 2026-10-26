//  🖥️ TUI — A Terminal UI framework for Swift
//  SceneOnChangeWindowsTests.swift
//
//  A scene's `onChange(of:)` is the scene's, not a window's: compared once a
//  frame, its action runs once for a change however many of the scene's
//  windows are open — none included — and `initial` runs it once, at launch,
//  not again for each window opened.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIFoundation

// MARK: - Fixtures

/// The value the scenes watch, and what their actions saw.
@MainActor
private enum WatchProbe {
    static var value = 1
    static var log: [String] = []

    static func record(_ old: Int, _ new: Int) {
        log.append("\(old)→\(new)")
    }
}

/// Two scenes under one `onChange`.
private struct GroupWatchApp: App {
    init() {}
    var body: some Scene {
        Group {
            WindowGroup(id: "main") { Text("main window") }
            Window("Inspector", id: "inspector") { Text("inspector window") }
        }
        .onChange(of: WatchProbe.value, initial: true) { old, new in WatchProbe.record(old, new) }
    }
}

/// An `onChange` on a scene whose window is not open.
private struct ClosedWatchApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("main window") }
        Window("Inspector", id: "inspector") { Text("inspector window") }
            .onChange(of: WatchProbe.value) { old, new in WatchProbe.record(old, new) }
    }
}

// MARK: - Tests

@MainActor
@Suite("A scene's onChange with several windows", .serialized)
struct SceneOnChangeWindowsTests {
    private var now: Int64 = 0

    private mutating func frame<A: App>(_ app: HeadlessApp<A>) {
        now += 20_000_000
        app.frame(atNanos: now)
    }

    private mutating func launched<A: App>(_ app: A) -> HeadlessApp<A> {
        WatchProbe.value = 1
        WatchProbe.log = []
        let headless = HeadlessApp(app, width: 40, height: 6)
        frame(headless)
        frame(headless)
        return headless
    }

    @Test("Its action runs once for a change, however many of its windows are open, and initial only at launch")
    mutating func oncePerScene() {
        let app = launched(GroupWatchApp())
        #expect(WatchProbe.log == ["1→1"])
        app.scenes.open(WindowTarget(id: "inspector"))
        frame(app)
        app.scenes.open(WindowTarget(id: "main"))
        frame(app)
        frame(app)
        #expect(app.scenes.windows.count == 3, "precondition: three windows open")
        #expect(WatchProbe.log == ["1→1"], "a window opening is not the scene appearing")
        WatchProbe.value = 2
        frame(app)
        frame(app)
        #expect(WatchProbe.log == ["1→1", "1→2"], "once, not once a window")
    }

    @Test("Its action runs with none of its scene's windows open")
    mutating func closedScene() {
        let app = launched(ClosedWatchApp())
        #expect(app.scenes.windows.count == 1, "precondition: the inspector is not open")
        WatchProbe.value = 2
        frame(app)
        #expect(WatchProbe.log == ["1→2"])
    }
}
