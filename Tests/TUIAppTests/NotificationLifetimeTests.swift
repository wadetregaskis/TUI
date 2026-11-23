//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationLifetimeTests.swift
//
//  A toast's life in a running app, on a `TestApp`'s own queue and clock: its
//  action runs once however often it is clicked, and a toast is shown, and
//  goes, whatever happens to what posted it — a window or a sheet that closes,
//  or a burst of toasts too tall for the screen.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUIChrome
@testable import TUIFoundation
import TUITesting

// MARK: - Fixtures

/// A page that posts a toast with an Undo button as it appears.
private struct UndoPage: View {
    let count: ActionCount
    @Environment(\.notificationService) private var notifications

    var body: some View {
        Text("page").onAppear {
            let count = count
            notifications?.post(
                "Deleted", duration: 30, actions: [NotificationAction("Undo") { count.value.withLock { $0 += 1 } }])
        }
    }
}

private struct UndoApp: App {
    let count: ActionCount
    init() { count = ActionCount() }
    init(_ count: ActionCount) { self.count = count }
    var body: some Scene { WindowGroup { UndoPage(count: count) } }
}

// MARK: - Tests

@MainActor
@Suite("A toast's life in a running app")
struct NotificationLifetimeTests {
    @Test("A second click during the fade-out does not run the toast's action again")
    func actionRunsOnce() throws {
        let count = ActionCount()
        let app = TestApp(UndoApp(count), width: 80, height: 12)
        app.advance(by: .milliseconds(500))
        try app.click("Undo")
        app.advance(by: .milliseconds(50))
        #expect(app.screen.contains("Undo"), "still fading out, its button where it was: \(app.screen)")
        try app.click("Undo")
        #expect(count.value.withLock { $0 } == 1)
    }
}
