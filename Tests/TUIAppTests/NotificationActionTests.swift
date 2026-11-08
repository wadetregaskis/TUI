//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationActionTests.swift
//
//  Buttons on toasts, and the keyboard's way to them: F6 into the newest
//  toast and on to the older ones, Return to choose, Escape to dismiss.
//
//  Created by Wade Tregaskis
//  License: MIT

import Synchronization
import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUIChrome
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// How often a toast's action ran.
final class ActionCount: Sendable {
    let value = Mutex(0)
}

@MainActor
@Suite("Notification actions and the keyboard")
struct NotificationActionTests {
    /// A page with one button of its own, which has the focus to begin with.
    private func page() -> some View {
        _WindowChromeHost(content: Button("Page") {}.focusID("page"))
    }

    /// A harness for `service`, with its clock a second past every post.
    private func harness(_ service: NotificationService) -> InputChainHarness {
        InputChainHarness(width: 70, height: 16) { $0.notificationService = service }
    }

    /// A frame, a second past the posts on the service's clock.
    @discardableResult
    private func frame(_ harness: InputChainHarness) -> FrameBuffer {
        harness.now = Int64(MonotonicClock.nowNanoseconds) + 1_000_000_000
        return harness.frame(page())
    }

    @Test("F6 focuses a toast's button, and Return runs its action, dismisses it and goes back")
    func actionFromTheKeyboard() {
        let service = NotificationService()
        defer { service.dismissAll() }
        let count = ActionCount()
        let id = service.post(
            "Deleted 3 files", duration: 30,
            actions: [NotificationAction("Undo") { count.value.withLock { $0 += 1 } }])
        let harness = harness(service)
        frame(harness)
        #expect(harness.focusManager.currentFocusedID == "page")
        harness.press(KeyEvent(key: .f6))
        frame(harness)
        #expect(harness.focusManager.currentFocusedID == NotificationKeyboard.focusID(id, button: 0))
        harness.press(KeyEvent(key: .enter))
        frame(harness)
        #expect(count.value.withLock { $0 } == 1)
        #expect(service.activeEntries().first?.isDismissed == true)
        #expect(harness.focusManager.currentFocusedID == "page")
    }

    @Test("The status bar names F6 while a toast has a button, and Escape over one")
    func statusBar() {
        let service = NotificationService()
        defer { service.dismissAll() }
        let harness = harness(service)
        frame(harness)
        #expect(!harness.statusBar.currentItems.contains { $0.shortcut == Shortcut.f6 })
        service.post("Saved", duration: 30, actions: [NotificationAction("Open") {}])
        frame(harness)
        #expect(harness.statusBar.currentItems.contains { $0.shortcut == Shortcut.f6 })
        harness.press(KeyEvent(key: .f6))
        frame(harness)
        #expect(harness.statusBar.currentItems.contains { $0.shortcut == Shortcut.escape })
    }

    @Test("Escape dismisses the toast holding the focus, and the focus goes back")
    func escapeDismisses() {
        let service = NotificationService()
        defer { service.dismissAll() }
        service.post("Saved", duration: 30, actions: [NotificationAction("Open") {}])
        let harness = harness(service)
        frame(harness)
        harness.press(KeyEvent(key: .f6))
        frame(harness)
        harness.press(KeyEvent(key: .escape))
        frame(harness)
        #expect(service.activeEntries().allSatisfy { $0.isDismissed })
        #expect(harness.focusManager.currentFocusedID == "page")
    }

    @Test("F6 goes newest first, on to the older toast, then back to the page")
    func cycles() {
        let service = NotificationService()
        defer { service.dismissAll() }
        let older = service.post("Older", duration: 30, actions: [NotificationAction("A") {}])
        let newer = service.post("Newer", duration: 30, placement: .bottom, actions: [NotificationAction("B") {}])
        let harness = harness(service)
        frame(harness)
        var visited: [String?] = []
        for _ in 0..<3 {
            harness.press(KeyEvent(key: .f6))
            frame(harness)
            visited.append(harness.focusManager.currentFocusedID)
        }
        #expect(
            visited == [
                NotificationKeyboard.focusID(newer, button: 0), NotificationKeyboard.focusID(older, button: 0), "page",
            ])
    }

    @Test("A toast that stays until dismissed, with no actions, carries a Close button that dismisses it")
    func closeButton() {
        let service = NotificationService()
        defer { service.dismissAll() }
        let id = service.post("Connection lost", duration: nil)
        let harness = harness(service)
        let screen = frame(harness)
        #expect(screen.lines.contains { $0.stripped.contains("Close") })
        harness.press(KeyEvent(key: .f6))
        frame(harness)
        #expect(harness.focusManager.currentFocusedID == NotificationKeyboard.focusID(id, button: 0))
        harness.press(KeyEvent(key: .enter))
        frame(harness)
        #expect(service.activeEntries().allSatisfy { $0.isDismissed })
    }

    @Test("A toast does not start to fade while its button has the focus")
    func focusHoldsTheFade() throws {
        let service = NotificationService()
        defer { service.dismissAll() }
        let id = service.post("Saved", duration: 0.5, actions: [NotificationAction("Open") {}])
        let harness = harness(service)
        frame(harness)
        harness.press(KeyEvent(key: .f6))
        frame(harness)
        let held = try #require(service.activeEntries().first { $0.id == id })
        #expect(held.duration > 0.5, "held visible past its own duration")
    }
}
