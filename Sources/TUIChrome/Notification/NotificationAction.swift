//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationAction.swift
//
//  A button on a notification: a title, a role and what choosing it does.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - Notification Action

/// A button on a notification: choosing it runs its action and dismisses
/// the toast.
///
/// ```swift
/// NotificationService.current.post(
///     "Deleted 3 files", style: .success,
///     actions: [NotificationAction("Undo") { restore(files) }])
/// ```
///
/// The buttons sit on the toast's last row, in the order given. The keyboard
/// reaches them as it reaches every toast's: **F6** moves the focus to the
/// newest toast with a button, F6 again to the next older one, and past the
/// oldest back where it was; Tab reaches them too, after the page. Return
/// chooses the focused button, Escape dismisses its toast. The status bar
/// names F6 while a toast has a button. A toast's buttons answer a click as
/// well, and its fade waits while one of them has the focus.
///
/// The action runs on the main actor, at the moment of the choice. It is
/// `@Sendable` because a post may come from any thread.
///
/// TUI-specific: SwiftUI has no toast. The initializers follow `Button`'s.
public struct NotificationAction: Sendable {
    /// The button's title, looked up already where it was a key.
    let title: String

    /// What the button means, as a `Button`'s role does: a destructive one
    /// is drawn as such.
    let role: ButtonRole?

    /// What choosing it does, before the toast is dismissed.
    let handler: @MainActor @Sendable () -> Void

    /// A button titled with `titleKey`, a key looked up in the app's
    /// localizations as a `Text` literal's is.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the button's title.
    ///   - role: What the button means (default: none).
    ///   - action: What choosing it does, before the toast is dismissed.
    public init(
        _ titleKey: LocalizedStringKey, role: ButtonRole? = nil, action: @escaping @MainActor @Sendable () -> Void
    ) {
        self.init(verbatim: titleKey.localized, role: role, action: action)
    }

    /// A button titled with `title`, as written.
    ///
    /// - Parameters:
    ///   - title: The button's title.
    ///   - role: What the button means (default: none).
    ///   - action: What choosing it does, before the toast is dismissed.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S, role: ButtonRole? = nil, action: @escaping @MainActor @Sendable () -> Void
    ) {
        self.init(verbatim: String(title), role: role, action: action)
    }

    /// The one initializer the public ones funnel through.
    init(verbatim title: String, role: ButtonRole?, action: @escaping @MainActor @Sendable () -> Void) {
        self.title = title
        self.role = role
        self.handler = action
    }
}
