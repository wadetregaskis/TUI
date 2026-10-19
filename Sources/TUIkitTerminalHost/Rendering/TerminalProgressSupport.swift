//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalProgressSupport.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - Which terminals draw a progress report

extension TerminalClient {

    /// Whether `program` is documented to **draw** a progress report — ConEmu's
    /// `OSC 9 ; 4`, which TUIkit sends for a view's `.terminalProgress(_:)` —
    /// as a bar on its tab, its window or its pane.
    ///
    /// A capability, so the default is "no", for the reason
    /// ``honoursHyperlinks(_:)`` gives: an unmeasured terminal gets the answer
    /// that cannot hurt. TUIkit sends the report only where this says yes, and
    /// where it says no an app learns as much from
    /// `TerminalFeatures.showsProgress` and draws its progress itself.
    ///
    /// ## The table
    ///
    /// | Host | Draws it | Evidence |
    /// |---|---|---|
    /// | Ghostty | yes | `progress-style` (default `true`): "graphical progress bars using the ConEmu OSC 9;4 escape sequence" (its configuration reference, 1.3.1) |
    /// | iTerm2 | yes | its "Enable Progress Bars" setting, and its triggers' "progress protocol (OSC 9;4)" (3.7.6's own help text) |
    /// | tmux | yes, for a client that can | keeps a bar per pane (`#{pane_pb_state}`, "can be set by application") and passes it on to a client with the `progressbar` feature, which tmux 3.7c gives iTerm2 and nothing else of these four (its manual; measured, `progress_probe.py`) |
    /// | Apple Terminal | no | nothing in the app |
    /// | Warp | no | nothing in the app names either sequence |
    /// | unidentified | no | an unmeasured host gets the answer that cannot hurt |
    ///
    /// kitty draws it too, from 0.47.0 (its changelog), but TUIkit has no
    /// ``Program`` for kitty, and before 0.38 kitty posted any `OSC 9` as a
    /// notification, a progress report's digits included; `TUIKIT_PROGRESS=1`
    /// turns it on there. See `Documentation/Terminals/Terminal compatibility
    /// survey.md`, "Progress and attention".
    public static func honoursProgressReports(_ program: Program) -> Bool {
        switch program {
        case .ghostty, .iTerm2, .tmux: true
        case .appleTerminal, .warp, .unidentified: false
        }
    }

    /// Whether the terminal in front of the user draws a progress report: the
    /// environment, then the table (``honoursProgressReports(_:)``).
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
    /// for off, which is how a user turns progress on for a terminal TUIkit
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
