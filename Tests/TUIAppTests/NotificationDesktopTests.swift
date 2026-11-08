//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationDesktopTests.swift
//
//  A toast posted to the desktop too: sent through the terminal as `OSC 9`
//  with the frame that draws it, where the terminal posts one, and never as
//  the bell.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIChrome
@testable import TUIFoundation
import TUITesting

private struct ToastApp: App {
    var body: some Scene {
        WindowGroup { Text("page") }
    }
}

@MainActor
@Suite("Notifications posted to the desktop", .serialized)
struct NotificationDesktopTests {
    /// Empties `service` at once and puts an empty one in its place as the
    /// shared service, so no toast of this suite's — not even one fading out —
    /// is drawn over another suite's app in this process.
    private static func release(_ service: NotificationService) {
        service.clear()
        NotificationService.current = NotificationService()
    }

    private var now: Int64 = 0

    private static func notification(_ text: String) -> String { "\u{1B}]9;\(text)\u{1B}\\" }

    /// An app drawing a fresh shared service, on a terminal that posts
    /// notifications or not, after its first frame.
    private mutating func launched(postsNotifications: Bool) -> (TestApp, NotificationService) {
        let service = NotificationService()
        NotificationService.current = service
        let app = TestApp(ToastApp(), width: 50, height: 10)
        app.services.terminalFeatures = TerminalFeatures(showsProgress: false, postsNotifications: postsNotifications)
        frame(app)
        return (app, service)
    }

    private mutating func frame(_ app: TestApp) {
        now += 20_000_000
        app.frame(atNanos: now)
    }

    @Test("desktop: .always sends the message with the next frame, once")
    mutating func always() {
        let (app, service) = launched(postsNotifications: true)
        defer { Self.release(service) }
        service.post("Build finished", desktop: .always)
        frame(app)
        #expect(app.hostWrites == [Self.notification("Build finished")])
        frame(app)
        #expect(app.hostWrites.count == 1, "once")
        #expect(app.bellsWritten == 0)
    }

    @Test("A toast not posted to the desktop sends nothing")
    mutating func never() {
        let (app, service) = launched(postsNotifications: true)
        defer { Self.release(service) }
        service.post("Saved")
        frame(app)
        #expect(app.hostWrites.isEmpty)
    }

    @Test("A terminal that posts no notifications is sent nothing, and no bell: the system's notifications get it")
    mutating func noBellInstead() throws {
        let (app, service) = launched(postsNotifications: false)
        defer { Self.release(service) }
        service.post("Build finished", desktop: .always)
        frame(app)
        #expect(app.hostWrites.isEmpty)
        #expect(app.bellsWritten == 0)
        let system = try #require(app.services.systemNotifier as? InMemorySystemNotifier)
        #expect(system.posted == ["Build finished"])
    }

    @Test("A terminal that posts notifications gets the toast's, and the system's notifications nothing: never twice")
    mutating func neverTwice() throws {
        let (app, service) = launched(postsNotifications: true)
        defer { Self.release(service) }
        service.post("Build finished", desktop: .always)
        frame(app)
        #expect(app.hostWrites == [Self.notification("Build finished")])
        let system = try #require(app.services.systemNotifier as? InMemorySystemNotifier)
        #expect(system.posted.isEmpty)
    }

    @Test(
        "whenInactive delivers only while the scene is not active",
        arguments: [(ScenePhase.active, false), (.inactive, true), (.background, true)])
    func whenInactive(phase: ScenePhase, delivers: Bool) {
        #expect(NotificationDesktopDelivery.whenInactive.delivers(in: phase) == delivers)
        #expect(NotificationDesktopDelivery.always.delivers(in: phase))
        #expect(!NotificationDesktopDelivery.never.delivers(in: phase))
    }

    @Test("A service nothing draws keeps a bounded queue of desktop requests")
    func boundedQueue() {
        let service = NotificationService()
        for index in 0..<100 {
            let message = "Toast \(index)"
            service.post(message, desktop: .always)
        }
        let requests = service.takeDesktopRequests()
        #expect(requests.count == NotificationService.desktopQueueLimit)
        #expect(requests.last?.message == "Toast 99")
        #expect(service.takeDesktopRequests().isEmpty)
    }
}
