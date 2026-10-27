//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalProgressSupportTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUITerminalHost

/// Which hosts are sent a progress report (`OSC 9 ; 4`), and how the answer is
/// reached: the user's `TUI_PROGRESS`, then the table of hosts documented
/// to draw one. Asked on its inputs, so nothing here sets anything a whole
/// process reads.
@Suite("Terminal progress support")
struct TerminalProgressSupportTests {

    /// Documented, 2026-10-19: Ghostty's configuration reference, iTerm2's own
    /// help text, tmux's manual (and its forwarding measured). See
    /// `Documentation/Terminals/Terminal compatibility survey.md`, "Progress and
    /// attention".
    @Test(
        "The table holds the hosts documented to draw a progress report",
        arguments: [
            (TerminalClient.Program.ghostty, true),
            (.iTerm2, true),
            (.tmux, true),
            (.appleTerminal, false),
            (.warp, false),
            (.unidentified, false),
        ])
    func table(program: TerminalClient.Program, draws: Bool) {
        #expect(TerminalClient.honoursProgressReports(program) == draws)
    }

    @Test("TUI_PROGRESS outranks the table both ways, and anything else leaves it to the table")
    func environmentOutranksTheTable() {
        #expect(TerminalClient.progressReportsSupported(environment: ["TUI_PROGRESS": "1"], program: .appleTerminal))
        #expect(!TerminalClient.progressReportsSupported(environment: ["TUI_PROGRESS": "0"], program: .ghostty))
        #expect(TerminalClient.progressReportsSupported(environment: ["TUI_PROGRESS": "yes"], program: .iTerm2))
        #expect(!TerminalClient.progressReportsSupported(environment: [:], program: .warp))
    }

    @Test("The switch answers without reading the host")
    func switchLeavesTheHostUnread() {
        var read = false
        let program: () -> TerminalClient.Program = {
            read = true
            return .ghostty
        }
        _ = TerminalClient.progressReportsSupported(environment: ["TUI_PROGRESS": "0"], program: program())
        #expect(!read)
    }
}
