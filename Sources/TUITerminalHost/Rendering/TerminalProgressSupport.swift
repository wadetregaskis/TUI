//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalProgressSupport.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore

// MARK: - Which terminals draw a progress report

extension TerminalClient {

    /// Whether `program` is documented to **take** a progress report — ConEmu's
    /// `OSC 9 ; 4`, which TUI sends for a view's `.terminalProgress(_:)` —
    /// drawing it as a bar on its tab, its window or its pane, or, for tmux,
    /// keeping it for the pane and passing it on to a client that draws one.
    ///
    /// A capability, so the default is "no", for the reason
    /// ``honoursHyperlinks(_:)`` gives: an unmeasured terminal gets the answer
    /// that cannot hurt. TUI sends the report only where this says yes.
    /// Whether the person then SEES it is `\.terminalCapabilities`'
    /// ``TerminalCapabilities/Feature/progressReports``, which is not
    /// supported wherever this says no, and under tmux asks tmux which
    /// clients it passes the bar on to; where it says no an app draws its
    /// progress itself.
    ///
    /// ## The table
    ///
    /// | Host | Takes it | Evidence |
    /// |---|---|---|
    /// | Ghostty | yes, and draws it | `progress-style` (default `true`): "graphical progress bars using the ConEmu OSC 9;4 escape sequence" (its configuration reference, 1.3.1) |
    /// | iTerm2 | yes, and draws it | its "Enable Progress Bars" setting, and its triggers' "progress protocol (OSC 9;4)" (3.7.6's own help text) |
    /// | tmux | yes, and passes it on to a client that can draw it | keeps a bar per pane (`#{pane_pb_state}`, "can be set by application"), hands it to a client that attaches later, and passes each change — never a repeat — to a client with the `progressbar` feature, which tmux 3.7c gives iTerm2 and nothing else of these four (its manual and its built-in table; measured, `progress_probe.py`) |
    /// | Apple Terminal | no | nothing in the app |
    /// | Warp | no | nothing in the app names either sequence |
    /// | unidentified | no | an unmeasured host gets the answer that cannot hurt |
    ///
    /// kitty draws it too, from 0.47.0 (its changelog), but TUI has no
    /// ``Program`` for kitty, and before 0.38 kitty posted any `OSC 9` as a
    /// notification, a progress report's digits included; `TUIKIT_PROGRESS=1`
    /// turns it on there. See `Documentation/Terminals/Terminal compatibility
    /// survey.md`, "Progress and attention".
    public static func honoursProgressReports(_ program: Program) -> Bool {
        switch program {
        case .ghostty, .iTerm2, .tmux: true
        case .appleTerminal, .warp, .gnomeTerminal, .unidentified: false
        }
    }

    /// Whether TUI sends the terminal in front of the user a progress
    /// report: the environment, then the table (``honoursProgressReports(_:)``).
    ///
    /// Reads the DETECTED program, never ``simulated``, as
    /// ``clipboardWrites`` does: simulating a terminal changes how the app is
    /// drawn, and a progress report goes to the terminal actually there.
    @MainActor public static var progressReportsSupported: Bool {
        progressReportsSupported(
            environment: ProcessInfo.processInfo.environment, program: current.program)
    }

    /// The ladder behind ``progressReportsSupported``, posed on its inputs so
    /// it can be asked without a terminal: `TUIKIT_PROGRESS` — `1` for on, `0`
    /// for off, which is how a user turns progress on for a terminal TUI
    /// does not know, or off for one it does — then the table.
    static func progressReportsSupported(
        environment: [String: String], program: @autoclosure () -> Program
    ) -> Bool {
        switch environment["TUIKIT_PROGRESS"] {
        case "1": return true
        case "0": return false
        default: return honoursProgressReports(program())
        }
    }
}
