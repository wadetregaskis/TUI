//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalCapabilities+Hosts.swift
//
//  What TUI's tables of terminals settle, and how a feature's switches
//  and its table combine into one answer.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The text decorations' table

extension TerminalCapabilities {
    /// What the table of measured terminals says of `program`'s text
    /// decorations, every other feature undetermined.
    ///
    /// The four terminals the owner read `line_style_card.py` in (2026-10-18)
    /// are settled, from `TerminalHost.lineStyles(for:)`, which is what the
    /// renderer reduces a style by, so the two cannot disagree; and the
    /// strikethrough from the same reading, where Apple Terminal alone drew
    /// none. Every other terminal is undetermined: GNOME Terminal has not been
    /// read, an unidentified one cannot be, and tmux draws a style in each
    /// terminal attached that can and a plain line in the others. See
    /// *Terminal compatibility survey*, "Underline shapes and colours".
    package static func textDecorations(of program: TerminalClient.Program) -> Self {
        switch program {
        case .appleTerminal, .iTerm2, .ghostty, .warp:
            let styles = TerminalHost.lineStyles(for: program)
            return nothingKnown
                .settling(.doubleUnderline, drawn: styles.doubleUnderline)
                .settling(.patternedUnderline, drawn: styles.patternedUnderlines)
                .settling(.underlineColor, drawn: styles.underlineColour)
                .settling(.strikethrough, drawn: program != .appleTerminal)
                .settling(.strikethroughColor, drawn: styles.strikethroughColour)
        case .gnomeTerminal, .tmux, .unidentified:
            return nothingKnown
        }
    }

    /// These capabilities with `features` supported where `drawn`, else
    /// unsupported.
    package func settling(_ features: Feature, drawn: Bool) -> Self {
        settling(features, as: drawn ? .supported : .unsupported)
    }
}

// MARK: - A switch, then a table

extension TerminalCapabilities {
    /// How far a table of terminals reaches the one in front of the person,
    /// for one feature.
    package enum HostEvidence: Sendable {
        /// The table's row for this terminal is measured or documented: what
        /// TUI decided is the answer.
        case known
        /// The terminal is named but its row is not known: nobody has
        /// measured it, or what the person sees depends on something TUI
        /// cannot ask (the terminals attached to tmux).
        case unknown
        /// The terminal was not identified. Where something else recognised
        /// it (kitty by its variables, say) TUI uses the feature, and it is
        /// supported; otherwise nobody knows.
        case unidentified
    }

    /// The answer for a feature TUI turns on or off by a ladder — an app's
    /// override, then the user's `TUIKIT_*` switch, then a table of
    /// terminals: `uses`, whether it ended up on; `forced`, whether the
    /// override or the switch decided it; `evidence`, how far the table
    /// reaches this terminal.
    ///
    /// A forced answer is settled whichever terminal this is: on, the app or
    /// the person says it works; off, TUI does not send it.
    package static func status(uses: Bool, forced: Bool, evidence: HostEvidence) -> Status {
        if forced { return uses ? .supported : .unsupported }
        switch evidence {
        case .known: return uses ? .supported : .unsupported
        case .unknown: return .undetermined
        case .unidentified: return uses ? .supported : .undetermined
        }
    }

    /// Whether the app's `override` or the user's `TUIKIT_*` switch
    /// `variable`, set to `1` or `0` in `environment`, decides a feature — the
    /// two rungs every ladder here starts with.
    package static func isForced(override: Bool?, variable: String, in environment: [String: String]) -> Bool {
        override != nil || environment[variable] == "1" || environment[variable] == "0"
    }
}
