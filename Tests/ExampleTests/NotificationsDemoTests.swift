//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationsDemoTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// Only where the package can depend on the app (see Package.swift).
#if canImport(Example)

import Foundation
import Testing

@testable import Example
import TUI
import TUIApp
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

    /// The app's own queue of toasts, made the process's too for the test, as
    /// the page posts most of its toasts through `NotificationService.current`
    /// (belonging to no window, they go above a sheet), which a `TestApp` does
    /// not draw.
    private static func sharedQueue(of app: TestApp) -> NotificationService {
        let service = app.headless.notificationService
        NotificationService.current = service
        return service
    }

    @Test("Under a sheet posts the window's toast, below the sheet; Over a sheet posts one above it")
    func presentations() throws {
        let app = TestApp(width: 100, height: 30) { NotificationsDemo() }
        let service = Self.sharedQueue(of: app)
        defer { Self.release(service) }
        try app.click("page.overlays.notifications.underSheet")
        #expect(service.activeEntries().map(\.layer) == [.belowPresentations])
        #expect(app.screen.contains("page.overlays.notifications.sheetExplain"))
        _ = app.press(.escape)
        #expect(!app.screen.contains("page.overlays.notifications.sheetExplain"))
        try app.click("page.overlays.notifications.overSheet")
        #expect(service.activeEntries().last?.layer == .abovePresentations)
    }

    @Test("The Undo toast's button is reached with F6 and chosen with Return, with no host in the app")
    func undoFromTheKeyboard() throws {
        let app = TestApp(width: 100, height: 30) { NotificationsDemo() }
        let service = Self.sharedQueue(of: app)
        defer { Self.release(service) }
        try app.click("page.overlays.notifications.undo")
        let posted = service.activeEntries()
        #expect(posted.map(\.message) == ["page.overlays.notifications.undoMessage"])
        #expect(posted.first?.actions.count == 1)
        app.advance(by: .milliseconds(500))
        _ = app.press(.f6)
        _ = app.press(.enter)
        #expect(service.activeEntries().map(\.message).last == "page.overlays.notifications.restored")
    }
}

#endif
