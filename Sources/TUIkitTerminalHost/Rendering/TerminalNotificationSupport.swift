//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalNotificationSupport.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - Which terminals post a notification

extension TerminalClient {

    /// Whether `program` is documented to **post** a desktop notification for
    /// iTerm2's `OSC 9 ; message`, which TUIkit sends for an app's
    /// `requestAttention(_:)`; where it is not, the request rings the bell.
    ///
    /// A capability, so the default is "no", as ``honoursProgressReports(_:)``
    /// has it — and here the cost of a wrong "yes" is plain: the request is
    /// lost, where the bell it replaced would have been heard.
    ///
    /// ## The table
    ///
    /// | Host | Posts it | Evidence |
    /// |---|---|---|
    /// | Ghostty | yes | `desktop-notifications` (default `true`): "applications running in the terminal can show desktop notifications using certain escape sequences such as OSC 9 or OSC 777" (its configuration reference, 1.3.1) |
    /// | iTerm2 | yes | the sequence is its own; its triggers name "a notification … posted by a control sequence (OSC 9)" (3.7.6's help text), and its profiles' notifications are on by default |
    /// | tmux | no | passes no `OSC 9` on to the terminal it is drawn in, and does pass a bell (measured, 3.7c, `progress_probe.py`) |
    /// | Apple Terminal | no | nothing in the app |
    /// | Warp | no | nothing in its binary names the sequence |
    /// | unidentified | no | the bell, which every terminal has |
    ///
    /// kitty posts it too (its desktop-notifications documentation), but has
    /// no ``Program``; `TUIKIT_NOTIFICATIONS=1` turns it on there. See
    /// `Documentation/Terminals/Terminal compatibility survey.md`, "Progress
    /// and attention".
    public static func honoursNotifications(_ program: Program) -> Bool {
        switch program {
        case .ghostty, .iTerm2: true
        case .tmux, .appleTerminal, .warp, .gnomeTerminal, .unidentified: false
        }
    }

    /// Whether the terminal in front of the user posts a notification: the
    /// environment, then the table (``honoursNotifications(_:)``).
    ///
    /// Reads the DETECTED program, never ``simulated``, as
    /// ``progressReportsSupported`` does.
    @MainActor public static var notificationsSupported: Bool {
        notificationsSupported(environment: ProcessInfo.processInfo.environment, program: current.program)
    }

    /// The ladder behind ``notificationsSupported``, posed on its inputs:
    /// `TUIKIT_NOTIFICATIONS` — `1` for on, `0` for off, which is how a user
    /// keeps every request to the bell, or turns notifications on for a
    /// terminal TUIkit does not know — then the table.
    static func notificationsSupported(
        environment: [String: String], program: @autoclosure () -> Program
    ) -> Bool {
        switch environment["TUIKIT_NOTIFICATIONS"] {
        case "1": return true
        case "0": return false
        default: return honoursNotifications(program())
        }
    }
}
