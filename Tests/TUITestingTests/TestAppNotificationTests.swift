//  🖥️ TUI — A Terminal UI framework for Swift
//  TestAppNotificationTests.swift
//
//  A `TestApp`'s toasts: its own queue, on its own clock, so a toast lives on
//  the test's time alone and no two apps draw each other's (tuidisk's
//  feedback, Milestone 1 items 1 and 2).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUITesting

/// Six full rows, and a toast posted through the window's service as they
/// appear.
private struct Page: View {
    let message: String
    @Environment(\.notificationService) private var notifications

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<6, id: \.self) { row in
                Text(verbatim: "row \(row) " + String(repeating: "x", count: 60))
            }
        }
        .onAppear { notifications?.post(message) }
    }
}

private struct PageApp: App {
    let message: String

    init() { message = "" }
    init(_ message: String) { self.message = message }

    var body: some Scene {
        WindowGroup { Page(message: message) }
    }
}

@MainActor
@Suite("A TestApp's toasts")
struct TestAppNotificationTests {
    /// Whether every row shows all its cells: no toast, and no box where one was.
    private static func rowsWhole(_ screen: TestScreen) -> Bool {
        (0..<6).allSatisfy { screen.contains("row \($0) " + String(repeating: "x", count: 60)) }
    }

    @Test("A toast lives on the test's clock: shown once faded in, gone after its time with nothing left behind")
    func testClock() {
        let app = TestApp(PageApp("Hello from a toast"), width: 80, height: 12)
        _ = app.screen
        app.advance(by: .milliseconds(500))
        #expect(app.screen.contains("Hello from a toast"), "\(app.screen)")
        app.advance(by: .seconds(10))
        #expect(!app.screen.contains("Hello from a toast"))
        #expect(Self.rowsWhole(app.screen), "the rows, whole again: \(app.screen)")
    }

    @Test("Two apps in one test each draw only their own toasts")
    func ownQueue() {
        let first = TestApp(PageApp("From the first app"), width: 80, height: 12)
        let second = TestApp(PageApp("From the second app"), width: 80, height: 12)
        _ = first.screen
        _ = second.screen
        first.advance(by: .milliseconds(500))
        second.advance(by: .milliseconds(500))
        #expect(first.screen.contains("From the first app"), "\(first.screen)")
        #expect(!first.screen.contains("From the second app"), "\(first.screen)")
        #expect(second.screen.contains("From the second app"), "\(second.screen)")
        #expect(!second.screen.contains("From the first app"), "\(second.screen)")
    }
}
