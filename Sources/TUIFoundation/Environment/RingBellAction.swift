//  🖥️ TUI — A Terminal UI framework for Swift
//  RingBellAction.swift
//
//  Ringing the terminal's bell from an app's own control, to say that input
//  was refused, as TUI's own controls do.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// MARK: - Ring Bell Action

/// An action that rings the terminal's bell, to say that the input just
/// given was refused.
///
/// TUI's own controls ring it when they turn input away rather than take it —
/// a character a field's ``TextContentType`` does not allow, typed or pasted —
/// so that what was typed is not dropped silently. A control of the app's own
/// does the same with this action: read it from the environment and call it
/// where the input goes nowhere.
///
/// ```swift
/// @Environment(\.ringBell) private var ringBell
///
/// var body: some View {
///     track
///         .focusable()
///         .onKeyPress(.leftArrow) {
///             if position == 0 { ringBell() } else { position -= 1 }
///             return .handled
///         }
/// }
/// ```
///
/// The ring is written with the next frame, which it asks for, as one `BEL`
/// (`0x07`) that the terminal sounds, flashes or marks as its user has set
/// it. However often it is rung between two frames — a paste that drops a
/// dozen characters, a key held down at the end of a track — the frame rings
/// it once, TUI's own controls' rings included: they share one bell.
///
/// Not ``RequestAttentionAction``, which asks for the person's attention to
/// something that finished while they were looking elsewhere, and posts a
/// desktop notification where the terminal posts one. This is the
/// "no" a Mac app says with `NSSound.beep()` when a control refuses a key, and
/// is never a notification. SwiftUI's ``View/sensoryFeedback(_:trigger:)``
/// rings it too, for ``SensoryFeedback/error`` and ``SensoryFeedback/warning``.
///
/// TUI-specific: SwiftUI has no bell, and AppKit's `NSSound.beep()` is not
/// SwiftUI.
public struct RingBellAction {
    /// Where the ring is queued for the next frame: the running app's bell,
    /// or `nil` outside a running app, where nothing could hear it.
    private let bell: TerminalBell?

    /// The action that rings `bell`.
    package init(bell: TerminalBell?) {
        self.bell = bell
    }

    /// Rings the terminal's bell at the next frame.
    @MainActor
    public func callAsFunction() {
        bell?.ring()
    }
}

// MARK: - Environment

extension EnvironmentValues {
    /// An action that rings the terminal's bell, to say that input was
    /// refused — see ``RingBellAction``.
    ///
    /// Read-only: the running app's own, which reaches every view it draws.
    /// Outside a running app — a test, a snapshot — it does nothing.
    public var ringBell: RingBellAction {
        RingBellAction(bell: terminalBell)
    }
}
