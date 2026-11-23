//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalCapabilities+Launch.swift
//
//  What the app runner publishes to `\.terminalCapabilities` at launch, once
//  the terminal is named and asked: each feature from the ladder TUI
//  itself decides it by, so that the answer and what is sent cannot disagree.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

extension TerminalCapabilities {
    /// What is known once the terminal has been identified and asked,
    /// before the first frame: the text decorations from the measured table,
    /// pictures from the graphics handshake, the keyboard from the kitty
    /// protocol's negotiation (`reporting`), and the host integration from
    /// what TUI decided to send (`features`, and the ladders behind
    /// hyperlinks and clipboard writes). The progress bar is the render loop's
    /// to publish, as it learns whether it shows (``progressAbsence(program:environment:)``
    /// says what its absence means), and Option as Meta the input's.
    ///
    /// `program` is the terminal TUI identified; a test names one.
    @MainActor
    static func atLaunch(
        features: TerminalFeatures, reporting: KeyboardReporting,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        program: TerminalClient.Program = TerminalHost.program
    ) -> Self {
        textDecorations(of: program)
            .settling(negotiatedKeyboard, from: keyboard(reporting))
            .settling(.pictures, as: picturesStatus(environment: environment))
            .settling(.hyperlinks, as: hyperlinksStatus(environment: environment))
            .settling(.clipboardWrites, as: clipboardWritesStatus(program: program, environment: environment))
            .settling(
                .notifications,
                as: status(
                    uses: features.postsNotifications,
                    forced: isForced(override: nil, variable: "TUI_NOTIFICATIONS", in: environment),
                    evidence: hostIntegrationEvidence(program)))
            .settling(
                .pointerShapes,
                as: status(
                    uses: features.pointerShapes,
                    forced: environment["TUI_POINTER_SHAPES"] == "apps"
                        || isForced(
                            override: TerminalClient.pointerShapeSupport, variable: "TUI_POINTER_SHAPES",
                            in: environment),
                    evidence: pointerShapesEvidence(program)))
    }

    /// The graphics ladder (`TerminalClient.graphicsSupported`): an override
    /// or `TUI_GRAPHICS` settles it; else the handshake's answer, and
    /// undetermined where it never ran.
    @MainActor
    static func picturesStatus(environment: [String: String]) -> Status {
        if isForced(override: TerminalClient.graphicsSupport, variable: "TUI_GRAPHICS", in: environment)
            || environment["TUI_GRAPHICS"] == "classic" || environment["TUI_GRAPHICS"] == "sixel"
            || TerminalClient.sixelInUse
        {
            return TerminalClient.graphicsSupported ? .supported : .unsupported
        }
        switch TerminalClient.detectedPictures {
        case .some(true): return .supported
        case .some(false): return .unsupported
        case .none: return .undetermined
        }
    }

    /// The hyperlink ladder (`TerminalClient.hyperlinksSupported`), which
    /// reads the effective program, so a simulated host moves the answer as
    /// it moves what is sent. Under tmux TUI sends the link, and whether
    /// the person sees it is up to tmux and the terminals attached.
    @MainActor
    static func hyperlinksStatus(environment: [String: String]) -> Status {
        let program = TerminalClient.effective.program
        let evidence: HostEvidence =
            switch program {
            case .tmux: .unknown
            case .unidentified: .unidentified
            case .appleTerminal, .iTerm2, .ghostty, .warp, .gnomeTerminal, .xtermJS, .windowsTerminal, .windowsConsole:
                .known
            }
        return status(
            uses: TerminalClient.hyperlinksSupported,
            forced: isForced(override: TerminalClient.hyperlinkSupport, variable: "TUI_HYPERLINKS", in: environment),
            evidence: evidence)
    }

    /// The clipboard ladder (`TerminalClient.clipboardWrites`): honoured is
    /// supported, unconfirmed undetermined, unsupported unsupported — but on a
    /// terminal TUI did not identify, or whose row is not known
    /// (``hostIntegrationEvidence(_:)``), which the table answers "no" for
    /// safety. Under tmux, unless forced, undetermined without asking: tmux's
    /// options decide at each copy, and asking them costs a subprocess.
    @MainActor
    static func clipboardWritesStatus(program: TerminalClient.Program, environment: [String: String]) -> Status {
        clipboardWritesStatus(
            program: program, writes: TerminalClient.clipboardWrites,
            forced: isForced(override: TerminalClient.clipboardWriteSupport, variable: "TUI_OSC52", in: environment))
    }

    /// The ladder behind ``clipboardWritesStatus(program:environment:)``,
    /// posed on its inputs: `writes`, what the clipboard ladder decided, and
    /// `forced`, whether the app or `TUI_OSC52` decided it.
    static func clipboardWritesStatus(
        program: TerminalClient.Program, writes: TerminalClient.ClipboardWriteSupport, forced: Bool
    ) -> Status {
        if program == .tmux, !forced { return .undetermined }
        switch writes {
        case .honoured: return .supported
        case .unconfirmed: return .undetermined
        case .unsupported: return status(uses: false, forced: forced, evidence: hostIntegrationEvidence(program))
        }
    }

    /// How far the tables of what a terminal does with notifications
    /// (`TerminalClient.honoursNotifications`), progress reports
    /// (`honoursProgressReports`) and clipboard writes
    /// (`TerminalClient.support(of:)`) reach `program`: every host they name
    /// but xterm.js. There each is the page's to handle (an `OSC 9` handler
    /// of its own, its clipboard addon), which nothing can see, and the
    /// survey measured none of them ("What TUI does about it —
    /// `TerminalClient.Program.xtermJS`"). TUI sends none of the three
    /// there, and says it does not know whether the person would see one.
    static func hostIntegrationEvidence(_ program: TerminalClient.Program) -> HostEvidence {
        switch program {
        case .appleTerminal, .iTerm2, .ghostty, .warp, .gnomeTerminal, .windowsTerminal, .windowsConsole, .tmux:
            .known
        case .xtermJS: .unknown
        case .unidentified: .unidentified
        }
    }

    /// How far the pointer-shape table (decisions O12) reaches `program`: the
    /// hosts it documents, Apple Terminal and Warp, which document none, and
    /// not GNOME Terminal or tmux, whose rows are unmeasured.
    static func pointerShapesEvidence(_ program: TerminalClient.Program) -> HostEvidence {
        switch program {
        case .appleTerminal, .iTerm2, .ghostty, .warp: .known
        case .gnomeTerminal, .xtermJS, .windowsTerminal, .windowsConsole, .tmux: .unknown
        case .unidentified: .unidentified
        }
    }

    /// What a progress bar that does not show says of the terminal, for
    /// ``Feature/progressReports``, which is supported where it shows:
    /// unsupported where `TUI_PROGRESS` turned it off, on a terminal TUI
    /// knows draws none, and under tmux, which was asked about the terminals
    /// attached; undetermined on a terminal TUI did not identify, and on
    /// xterm.js, whose page may draw one (``hostIntegrationEvidence(_:)``).
    static func progressAbsence(program: TerminalClient.Program, environment: [String: String]) -> Status {
        status(
            uses: false, forced: isForced(override: nil, variable: "TUI_PROGRESS", in: environment),
            evidence: hostIntegrationEvidence(program))
    }
}
