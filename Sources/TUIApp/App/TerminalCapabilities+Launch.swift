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
    @MainActor
    static func atLaunch(
        features: TerminalFeatures, reporting: KeyboardReporting,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Self {
        let program = TerminalHost.program
        return textDecorations(of: program)
            .settling(negotiatedKeyboard, from: keyboard(reporting))
            .settling(.pictures, as: picturesStatus(environment: environment))
            .settling(.hyperlinks, as: hyperlinksStatus(environment: environment))
            .settling(.clipboardWrites, as: clipboardWritesStatus(program: program, environment: environment))
            .settling(
                .notifications,
                as: status(
                    uses: features.postsNotifications,
                    forced: isForced(override: nil, variable: "TUI_NOTIFICATIONS", in: environment),
                    evidence: program == .unidentified ? .unidentified : .known))
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
        if isForced(override: TerminalClient.graphicsSupport, variable: "TUI_GRAPHICS", in: environment) {
            return TerminalClient.graphicsSupported ? .supported : .unsupported
        }
        switch TerminalClient.detectedGraphics {
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
            case .appleTerminal, .iTerm2, .ghostty, .warp, .gnomeTerminal: .known
            }
        return status(
            uses: TerminalClient.hyperlinksSupported,
            forced: isForced(override: TerminalClient.hyperlinkSupport, variable: "TUI_HYPERLINKS", in: environment),
            evidence: evidence)
    }

    /// The clipboard ladder (`TerminalClient.clipboardWrites`): honoured is
    /// supported, unconfirmed undetermined, unsupported unsupported — but on a
    /// terminal TUI did not identify, which the table answers "no" for
    /// safety. Under tmux, unless forced, undetermined without asking: tmux's
    /// options decide at each copy, and asking them costs a subprocess.
    @MainActor
    static func clipboardWritesStatus(program: TerminalClient.Program, environment: [String: String]) -> Status {
        let forced = isForced(
            override: TerminalClient.clipboardWriteSupport, variable: "TUI_OSC52", in: environment)
        if program == .tmux, !forced { return .undetermined }
        switch TerminalClient.clipboardWrites {
        case .honoured: return .supported
        case .unconfirmed: return .undetermined
        case .unsupported: return program == .unidentified && !forced ? .undetermined : .unsupported
        }
    }

    /// How far the pointer-shape table (decisions O12) reaches `program`: the
    /// hosts it documents, Apple Terminal and Warp, which document none, and
    /// not GNOME Terminal or tmux, whose rows are unmeasured.
    static func pointerShapesEvidence(_ program: TerminalClient.Program) -> HostEvidence {
        switch program {
        case .appleTerminal, .iTerm2, .ghostty, .warp: .known
        case .gnomeTerminal, .tmux: .unknown
        case .unidentified: .unidentified
        }
    }

    /// What a progress bar that does not show says of the terminal, for
    /// ``Feature/progressReports``, which is supported where it shows:
    /// unsupported where `TUI_PROGRESS` turned it off, on a terminal TUI
    /// knows draws none, and under tmux, which was asked about the terminals
    /// attached; undetermined on a terminal TUI did not identify.
    static func progressAbsence(program: TerminalClient.Program, environment: [String: String]) -> Status {
        let forced = isForced(override: nil, variable: "TUI_PROGRESS", in: environment)
        return program == .unidentified && !forced ? .undetermined : .unsupported
    }
}
