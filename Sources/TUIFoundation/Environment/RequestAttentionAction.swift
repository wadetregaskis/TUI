//  🖥️ TUI — A Terminal UI framework for Swift
//  RequestAttentionAction.swift
//
//  Asking for the person's attention from a terminal app: a desktop
//  notification where the terminal posts one, its bell elsewhere.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// MARK: - Request Attention Action

/// An action that asks for the person's attention: a desktop notification
/// carrying a message, where the terminal posts one, and the terminal's bell
/// everywhere else.
///
/// For something the person is waiting on that finished while they were
/// looking elsewhere — another tab, another window, another app. Read it from
/// the environment and call it, typically when the scene is not active
/// (mode 1004 tells TUI when the terminal's window loses the focus):
///
/// ```swift
/// @Environment(\.requestAttention) private var requestAttention
/// @Environment(\.scenePhase) private var scenePhase
///
/// func buildFinished() {
///     if scenePhase != .active { requestAttention("Build finished") }
/// }
/// ```
///
/// The request is written with the next frame, which it asks for: as iTerm2's
/// `OSC 9` notification (`ESC ] 9 ; message ESC \`) on a terminal documented to
/// post one — Ghostty and iTerm2 — and as `BEL` on every other, which the
/// terminal sounds, flashes or marks as its user has set it. tmux passes no
/// notification on (measured), so inside tmux it is the bell, which tmux
/// passes on. Requests made between two frames are written together: each
/// message once, and the bell once. Nothing reports whether the person saw
/// it. ``EnvironmentValues/terminalCapabilities``' ``TerminalCapabilities/Feature/notifications`` says
/// which this terminal gets, and `TUIKIT_NOTIFICATIONS=1` or `0` is the
/// user's switch.
///
/// TUI-specific, with no SwiftUI counterpart: a Mac app would bounce its Dock
/// icon or post a notification itself, neither of which a program in a
/// terminal can reach. See `Documentation/Terminals/Terminal compatibility
/// survey.md`, "Progress and attention".
public struct RequestAttentionAction: Sendable {
    /// Where the request is queued for the next frame: the running app's
    /// bell, or `nil` outside a running app, where nothing could hear it.
    private let bell: TerminalBell?

    /// The action that queues its requests on `bell`.
    package init(bell: TerminalBell?) {
        self.bell = bell
    }

    /// Asks for the person's attention with `message`, a key looked up in the
    /// app's localizations as a `Text` literal's is: posted as a notification
    /// where the terminal posts one, and otherwise ringing the bell.
    ///
    /// The message goes to the terminal as text: its control characters are
    /// dropped, its line breaks and tabs become spaces, and one that leaves
    /// nothing rings the bell instead. One that starts with a digit is sent
    /// after a space, so that no terminal can read its digits as another of
    /// the commands `OSC 9` carries (ConEmu's `OSC 9 ; 4` is a progress
    /// report).
    @MainActor
    public func callAsFunction(_ message: LocalizedStringKey) {
        bell?.requestAttention(message.localized)
    }

    /// Asks for the person's attention with `message`, as it is.
    @MainActor
    @_disfavoredOverload
    public func callAsFunction<S: StringProtocol>(_ message: S) {
        bell?.requestAttention(String(message))
    }
}

// MARK: - Environment

extension EnvironmentValues {
    /// An action that asks for the person's attention: a desktop notification
    /// where the terminal posts one, its bell elsewhere — see
    /// ``RequestAttentionAction``.
    ///
    /// Read-only: the running app's own, which reaches every view it draws.
    /// Outside a running app — a test, a snapshot — it does nothing.
    public var requestAttention: RequestAttentionAction {
        RequestAttentionAction(bell: terminalBell)
    }
}
