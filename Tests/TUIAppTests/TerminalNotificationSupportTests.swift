//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalNotificationSupportTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUITerminalHost

/// Which hosts are sent a desktop notification (`OSC 9`) for
/// `requestAttention(_:)` rather than the bell, and how the answer is reached:
/// the user's `TUIKIT_NOTIFICATIONS`, then the table of hosts documented to
/// post one. Asked on its inputs.
@Suite("Terminal notification support")
struct TerminalNotificationSupportTests {

    /// Documented, 2026-10-19: Ghostty's configuration reference, iTerm2's own
    /// sequence and help text; tmux measured to pass none on. See
    /// `Documentation/Terminals/Terminal compatibility survey.md`, "Progress and
    /// attention".
    @Test(
        "The table holds the hosts documented to post a notification",
        arguments: [
            (TerminalClient.Program.ghostty, true),
            (.iTerm2, true),
            (.tmux, false),
            (.appleTerminal, false),
            (.warp, false),
            (.unidentified, false),
        ])
    func table(program: TerminalClient.Program, posts: Bool) {
        #expect(TerminalClient.honoursNotifications(program) == posts)
    }

    @Test("TUIKIT_NOTIFICATIONS outranks the table both ways, and anything else leaves it to the table")
    func environmentOutranksTheTable() {
        #expect(TerminalClient.notificationsSupported(environment: ["TUIKIT_NOTIFICATIONS": "1"], program: .tmux))
        #expect(!TerminalClient.notificationsSupported(environment: ["TUIKIT_NOTIFICATIONS": "0"], program: .ghostty))
        #expect(TerminalClient.notificationsSupported(environment: ["TUIKIT_NOTIFICATIONS": ""], program: .iTerm2))
        #expect(!TerminalClient.notificationsSupported(environment: [:], program: .appleTerminal))
    }
}
