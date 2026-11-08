//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationsDemoTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import Example
import TUI
@testable import TUIChrome
import TUITesting

@MainActor
@Suite("The Overlays page's notifications section", .serialized)
struct NotificationsDemoTests {
    /// Empties `service` at once and puts an empty one in its place as the
    /// shared service, so no toast of this suite's — not even one fading out —
    /// is drawn over another suite's app in this process.
    private static func release(_ service: NotificationService) {
        service.clear()
        NotificationService.current = NotificationService()
    }

    /// Read from the service rather than the screen: a `TestApp`'s frames run
    /// on its own clock, from zero, and a toast's age on the machine's, so in
    /// a test app a toast never gets past the first instant of its fade-in.
    /// Its buttons are drawn and reached all the same.
    @Test("The Undo toast's button is reached with F6 and chosen with Return, with no host in the app")
    func undoFromTheKeyboard() throws {
        let service = NotificationService()
        NotificationService.current = service
        defer { Self.release(service) }
        let app = TestApp(width: 100, height: 30) { NotificationsDemo() }
        try app.click("page.overlays.notifications.undo")
        let posted = service.activeEntries()
        #expect(posted.map(\.message) == ["page.overlays.notifications.undoMessage"])
        #expect(posted.first?.actions.count == 1)
        _ = app.press(.f6)
        _ = app.press(.enter)
        #expect(service.activeEntries().map(\.message).last == "page.overlays.notifications.restored")
    }
}
