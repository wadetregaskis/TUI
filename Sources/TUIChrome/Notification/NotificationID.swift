//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationID.swift
//
//  The handle a post returns, for dismissing that notification later.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - Notification ID

/// Names one posted notification: what ``NotificationService``'s `post`
/// methods return, for ``NotificationService/dismiss(_:)`` to take it away.
///
/// ```swift
/// let saving = NotificationService.current.post("Saving…", duration: nil)
/// try await document.save()
/// NotificationService.current.dismiss(saving)
/// ```
///
/// Every post makes a new one, so two posts of the same message are two
/// notifications. One whose notification has gone names nothing, and
/// dismissing it does nothing.
public struct NotificationID: Hashable, Sendable {
    /// The identifier, unique to the post.
    let rawValue: UUID

    /// A new identifier, unlike every other.
    init() {
        rawValue = UUID()
    }
}
