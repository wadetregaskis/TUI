//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationLayer.swift
//
//  Where a toast goes against the sheets, alerts and dialogs presented over
//  the window, and whose a toast is: the window or presentation it was posted
//  from.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - Notification Layer

/// Where a toast is drawn against the sheets, alerts, dialogs and popovers
/// presented over the window: above them, reachable while one is up, or
/// beneath them, out of reach and waiting until it closes.
///
/// ```swift
/// // Over anything presented: the person can act on it now.
/// NotificationService.current.post("Connection lost", style: .error, layer: .abovePresentations)
/// ```
///
/// A post that names none takes it from where it was posted from. One through
/// ``NotificationService/current`` belongs to no window, and goes
/// ``abovePresentations``: whatever is up, it is news about the app. One
/// through a view's `@Environment(\.notificationService)` belongs to the
/// window the view is in — or to the sheet, alert or dialog it is in, where it
/// is in one — and goes ``belowPresentations``: under whatever is presented
/// over what posted it, and on top while nothing is.
///
/// TUI-specific: SwiftUI has no toast.
public enum NotificationLayer: Hashable, Sendable {
    /// Over every sheet, alert, dialog and popover, whoever posted it, with
    /// its buttons reachable — F6 moves the focus to them — while one is up.
    /// Escape still closes the presentation, unless the toast has the focus.
    case abovePresentations

    /// Under anything presented over what posted it — its window, or the
    /// sheet, alert or dialog it was posted from — and on top while nothing is.
    ///
    /// While something covers it, its buttons are out of reach and its timer
    /// waits: a toast with three seconds to show still has three when the
    /// sheet over it closes. One posted for a window not in front waits the
    /// same way, and is drawn when its window comes to the front.
    case belowPresentations
}

// MARK: - Owner

/// Whose a notification is: the window it was posted from, and the
/// presentation in it, if it was posted from inside one — what a view's
/// `@Environment(\.notificationService)` stamps on its posts. `nil` for one
/// posted through ``NotificationService/current``, which belongs to no window.
package struct NotificationOwner: Hashable, Sendable {
    /// The window's serial, as the scene presenter numbers its windows, or
    /// `nil` where it is not known (a scene drawn outside an app).
    package var window: Int?

    /// The focus section of the sheet, alert or dialog the post came from,
    /// or `nil` for the window's own content.
    package var presentation: String?

    package init(window: Int?, presentation: String?) {
        self.window = window
        self.presentation = presentation
    }
}

private struct NotificationOwnerKey: EnvironmentKey {
    static let defaultValue: NotificationOwner? = nil
}

extension EnvironmentValues {
    /// Whose a post through this environment's ``notificationService`` is: set
    /// by the scene presenter for a window's views and by a sheet, alert or
    /// dialog for its content.
    ///
    /// A value beside the service, not a service object made per window: the
    /// environment then holds the same service every frame, and this compares
    /// equal frame to frame, so a body the plain memo keeps stays kept. An
    /// object made in each frame's render was a new value each frame, and
    /// nothing was ever served (`PlainMemoRegistryTests`).
    package var notificationOwner: NotificationOwner? {
        get { self[NotificationOwnerKey.self] }
        set { self[NotificationOwnerKey.self] = newValue }
    }
}
