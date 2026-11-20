//  🖥️ TUI — A Terminal UI framework for Swift
//  TestAppTerminalOutputTests.swift
//
//  `TestApp.terminalProgress` and `TestApp.desktopNotifications`: what the app
//  sends the terminal beyond its cells, read as an app's tests read it, with
//  no `@testable` (tuidisk's feedback, Milestone 1 item 3).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUITesting

/// A scan a key starts and another ends: a progress bar while it runs, and a
/// toast for the desktop, while the window is in the background, when it ends.
private struct Scanner: View {
    @State private var isScanning = false
    @Environment(\.notificationService) private var notifications

    var body: some View {
        let notifications = notifications
        VStack {
            Button("Scan") { isScanning = true }
            Button("Finish") {
                isScanning = false
                notifications?.post("Scan finished", desktop: .whenInactive)
            }
        }
        .terminalProgress(isScanning ? .indeterminate : nil)
    }
}

@MainActor
@Suite("What a TestApp's app sends the terminal")
struct TestAppTerminalOutputTests {
    @Test("terminalProgress is what the views state, nil once none does")
    func progress() throws {
        let app = TestApp { Scanner() }
        #expect(app.terminalProgress == nil)
        try app.click("Scan")
        #expect(app.terminalProgress == .indeterminate)
        try app.click("Finish")
        #expect(app.terminalProgress == nil)
    }

    @Test("desktopNotifications has a whenInactive toast once the window is in the background")
    func desktop() throws {
        let app = TestApp { Scanner() }
        try app.click("Finish")
        #expect(app.desktopNotifications.isEmpty, "the window has the focus")
        app.reportFocus(false)
        try app.click("Finish")
        #expect(app.desktopNotifications == ["Scan finished"])
    }
}
