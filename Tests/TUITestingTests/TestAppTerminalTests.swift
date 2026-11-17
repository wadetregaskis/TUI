//  🖥️ TUI — A Terminal UI framework for Swift
//  TestAppTerminalTests.swift
//
//  What a test can say about the terminal around a `TestApp`: its window
//  losing and gaining the focus. Without `@testable`, as an app's tests are
//  written.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUITesting

private struct PhaseWatcher: View {
    @Environment(\.scenePhase) private var phase
    @Environment(\.appearsActive) private var appearsActive
    @State private var pauses = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "phase \(String(describing: phase))")
            Text(verbatim: "appears \(appearsActive ? "active" : "inactive")")
            Text(verbatim: "pauses \(pauses)")
        }
        .onChange(of: phase) { _, phase in
            if phase != .active { pauses += 1 }
        }
    }
}

@MainActor
@Suite("TestApp: the terminal around the app")
struct TestAppTerminalTests {
    @Test("A focus report moves the scene's phase, as a running app's does")
    func focusMovesThePhase() {
        let app = TestApp(width: 30, height: 3) { PhaseWatcher() }
        #expect(app.screen.contains("phase active"))
        #expect(app.screen.contains("appears active"))
        app.reportFocus(false)
        #expect(app.screen.contains("phase inactive"))
        #expect(app.screen.contains("appears inactive"))
        #expect(app.screen.contains("pauses 1"))
        app.reportFocus(false)
        #expect(app.screen.contains("pauses 1"), "a report of the focus the window has changes nothing")
        app.reportFocus(true)
        #expect(app.screen.contains("phase active"))
        #expect(app.screen.contains("appears active"))
        #expect(app.screen.contains("pauses 1"))
    }
}
