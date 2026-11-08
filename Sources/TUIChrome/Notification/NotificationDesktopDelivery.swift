//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationDesktopDelivery.swift
//
//  Whether a notification is also sent to the desktop, through the
//  terminal, as well as drawn as a toast.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - Notification Desktop Delivery

/// Whether a notification is also posted on the desktop — outside the
/// terminal, where the person sees it from another window or app — as well as
/// drawn as a toast.
///
/// ```swift
/// NotificationService.current.post("Build finished", style: .success, desktop: .whenInactive)
/// ```
///
/// It goes through the terminal, as `requestAttention(_:)`'s notification
/// does: written with the next frame as iTerm2's `OSC 9`, to a terminal
/// documented to post one (Ghostty and iTerm2; `TUI_NOTIFICATIONS=1` or `0`
/// overrides). Where the terminal posts none, this machine posts it itself —
/// `osascript` on macOS, `notify-send` on a Linux desktop — but only where the
/// person is at this machine (never over ssh, nor in a tmux attached from
/// elsewhere; `TUI_SYSTEM_NOTIFICATIONS=0` turns it off). One route or the
/// other, never both, so it arrives once. Unlike `requestAttention`, it never
/// rings the bell instead: the toast is already on the screen. It is one-way
/// — nothing reports whether the person saw it, and its buttons are the
/// toast's alone — and carries the message as text, with its control
/// characters dropped. ``EnvironmentValues/terminalCapabilities``'
/// `.notifications` says whether this terminal posts one. See
/// `Documentation/Terminals/Terminal compatibility survey.md`, "Progress and
/// attention".
///
/// TUI-specific: SwiftUI has no toast, and a Mac app posts its own
/// notifications, which a program in a terminal cannot reach.
public enum NotificationDesktopDelivery: Hashable, Sendable {
    /// Drawn as a toast only: the default.
    case never
    /// Posted on the desktop too while the terminal's window does not have
    /// the focus (``ScenePhase/active`` is the scene's phase while it does,
    /// as the terminal reports it, mode 1004), where the toast goes unseen.
    case whenInactive
    /// Posted on the desktop too, whatever has the focus.
    case always
}

extension NotificationDesktopDelivery {
    /// Whether a notification posted with this delivery goes to the desktop
    /// while the scene is in `phase`.
    func delivers(in phase: ScenePhase) -> Bool {
        switch self {
        case .never: false
        case .whenInactive: phase != .active
        case .always: true
        }
    }
}
