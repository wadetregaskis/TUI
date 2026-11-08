//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationEntry.swift
//
//  One notification as the service keeps it.
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIFoundation

// MARK: - Notification Entry

/// A single notification in the service queue.
///
/// Each entry carries the message, timing, and a unique identifier
/// for lifecycle tracking. Entries are created by ``NotificationService``'s `post` methods
/// and drawn by ``NotificationOverlay``.
struct NotificationEntry: Identifiable, Sendable {
    /// Unique identifier for this notification: what its post returned.
    let id: NotificationID

    /// The notification message text.
    let message: String

    /// What it is about, which its colour and glyph say.
    let style: NotificationStyle

    /// How long the notification stays visible (in seconds): infinite for
    /// one that stays until it is dismissed, and cut short by a dismissal
    /// (``dismissed(atNanos:)``).
    var duration: TimeInterval

    /// When this notification was posted, in nanoseconds on the service's clock —
    /// ``MonotonicClock`` in an app, the clock the frames are stamped with.
    let postedAtNanos: UInt64

    /// Creates a notification entry.
    ///
    /// - Parameters:
    ///   - message: The notification message text.
    ///   - style: What it is about.
    ///   - duration: Display duration in seconds.
    ///   - postedAtNanos: The service clock's reading at the post.
    init(message: String, style: NotificationStyle = .plain, duration: TimeInterval, postedAtNanos: UInt64) {
        self.id = NotificationID()
        self.message = message
        self.style = style
        // A NaN duration has no end to count to: taken as none, so the toast
        // fades in and straight back out. An infinite one stays, and the
        // clock saturates at its end (``AnimationClock/nanoseconds(_:)``).
        self.duration = duration.isNaN ? 0 : duration
        self.postedAtNanos = postedAtNanos
    }

    /// Seconds from the post to `now`, on the same clock; zero for a `now` before it.
    ///
    /// Saturating because the two readings can come from different moments of one
    /// frame: a toast posted while a frame renders is younger than that frame's stamp.
    func age(atNanos now: UInt64) -> TimeInterval {
        now > postedAtNanos ? Double(now - postedAtNanos) / 1_000_000_000 : 0
    }

    /// This notification, dismissed at `now`: its visible stretch ends there,
    /// so it fades out from `now` — or from the end of its fade-in, for one
    /// dismissed while it fades in. One already fading out, or gone, is
    /// unchanged.
    func dismissed(atNanos now: UInt64) -> Self {
        var dismissed = self
        dismissed.duration = min(duration, max(0, age(atNanos: now) - NotificationTiming.fadeInDuration))
        return dismissed
    }

    /// The service clock's reading at which this notification has finished fading out.
    var expiresAtNanos: UInt64 {
        let lifetime = NotificationTiming.fadeInDuration + duration + NotificationTiming.fadeOutDuration
        return postedAtNanos &+ UInt64(clamping: AnimationClock.nanoseconds(lifetime))
    }
}
