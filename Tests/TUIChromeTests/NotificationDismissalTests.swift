//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationDismissalTests.swift
//
//  How long a notification stays: its duration, forever where it has none,
//  and until its post's ID dismisses it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIChrome
@testable import TUICore

@Suite("Notification durations and dismissal")
struct NotificationDismissalTests {
    private static let second: UInt64 = 1_000_000_000

    /// A service on a clock the test steps, and the clock.
    private func service() -> (NotificationService, StepClock) {
        let clock = StepClock()
        return (NotificationService(nowNanos: { clock.nanos.withLock { $0 } }), clock)
    }

    @Test("Every post returns an ID of its own")
    func distinctIDs() {
        let (service, _) = service()
        let first = service.post("Same")
        let second = service.post("Same")
        #expect(first != second)
        #expect(service.activeEntries().map(\.id) == [first, second])
    }

    @Test("A notification with no duration stays until it is dismissed")
    func persistent() {
        let (service, clock) = service()
        let id = service.post("Stays", duration: nil)
        clock.nanos.withLock { $0 += 3_600 * Self.second }
        #expect(service.activeEntries().map(\.id) == [id])
        service.dismiss(id)
        clock.nanos.withLock { $0 += Self.second }
        #expect(service.activeEntries().isEmpty)
    }

    @Test("Dismissing one fades it out at once and leaves the others")
    func dismissOne() throws {
        let (service, clock) = service()
        let first = service.post("First", duration: 30)
        let second = service.post("Second", duration: 30)
        clock.nanos.withLock { $0 += Self.second }
        service.dismiss(first)
        let dismissed = try #require(service.activeEntries().first { $0.id == first })
        let now = clock.nanos.withLock { $0 }
        // Fading out from now: still opaque at the instant, gone a fade later.
        let age = dismissed.age(atNanos: now)
        #expect(NotificationTiming.opacity(elapsed: age, visibleDuration: dismissed.duration) == 1)
        let midFade = age + NotificationTiming.fadeOutDuration / 2
        #expect(NotificationTiming.opacity(elapsed: midFade, visibleDuration: dismissed.duration) < 1)
        clock.nanos.withLock { $0 += Self.second / 2 }
        #expect(service.activeEntries().map(\.id) == [second])
    }

    @Test("dismissAll fades out every notification")
    func dismissAll() {
        let (service, clock) = service()
        service.post("One", duration: nil)
        service.post("Two", duration: 30)
        clock.nanos.withLock { $0 += Self.second }
        service.dismissAll()
        clock.nanos.withLock { $0 += Self.second }
        #expect(service.activeEntries().isEmpty)
    }

    @Test("Dismissed while fading in, it fades out from the end of its fade-in")
    func dismissedWhileFadingIn() throws {
        let (service, _) = service()
        let id = service.post("Quick", duration: nil)
        service.dismiss(id)
        let entry = try #require(service.activeEntries().first)
        #expect(entry.duration == 0)
        #expect(entry.id == id)
    }

    @Test("Dismissing a notification that has gone, or twice, changes nothing")
    func dismissGone() throws {
        let (service, clock) = service()
        let gone = service.post("Gone", duration: 1)
        clock.nanos.withLock { $0 += 10 * Self.second }
        let kept = service.post("Kept", duration: 30)
        service.dismiss(gone)
        #expect(service.activeEntries().map(\.id) == [kept])
        clock.nanos.withLock { $0 += Self.second }
        service.dismiss(kept)
        let once = try #require(service.activeEntries().first).duration
        clock.nanos.withLock { $0 += Self.second / 10 }
        service.dismiss(kept)
        #expect(service.activeEntries().first?.duration == once, "a second dismissal must not restart the fade")
    }

    @Test("A wake asks for a frame for a change, and not when it only bounds the sleep")
    func wakeDraws() {
        let shown = [NotificationTiming.Shown(id: NotificationID(), duration: .infinity)]
        // A toast that stays: nothing to change, so the bounding wake draws nothing.
        #expect(!NotificationTiming.wakeDraws(due: .infinity, shown: shown, lastShown: shown))
        #expect(!NotificationTiming.wakeDraws(due: 2.5, shown: shown, lastShown: shown))
        // Mid-fade, or a change no further off than the longest sleep.
        #expect(NotificationTiming.wakeDraws(due: 0, shown: shown, lastShown: shown))
        #expect(NotificationTiming.wakeDraws(due: NotificationTiming.longestSleep, shown: shown, lastShown: shown))
        // A post or a dismissal since the last frame.
        #expect(NotificationTiming.wakeDraws(due: .infinity, shown: shown, lastShown: []))
    }
}
