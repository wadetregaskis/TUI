//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalClient+KeptChords.swift
//
//  The chords each terminal keeps for its own bindings, which never reach the
//  app.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension TerminalClient {
    /// The chords `program` keeps for bindings of its own, in every encoding,
    /// so the app never hears them: what TUI does not name a key by
    /// (``KeyboardReporting/keptChords``), offering another where it has one
    /// (Settings… shows F2).
    ///
    /// - Windows Terminal: ⌃, opens its settings, a default binding. Pressed
    ///   without the kitty keyboard protocol, 2026-11-17, it arrived as
    ///   nothing, and with all 31 flags, 2026-11-19 (1.25.3131.0), as
    ///   Control's own press and release alone (Terminal compatibility
    ///   survey.md, "Keys" and "Keys under the kitty protocol"). Its other
    ///   default bindings (⌃=, ⌃- and ⌃0 for the font size, ⌃V, the ⌃⇧ chords
    ///   for tabs, panes and find, Alt-arrows and ⌥⇧- for panes) are not
    ///   listed: a person can rebind any of them, so a list could be wrong for
    ///   them (the owner, 2026-11-17: "Just ⌃, for now"). ⌃- and ⌥⇧- were
    ///   kept in that run too: ⌃-'s release alone arrived, and ⌥⇧-'s
    ///   modifiers.
    ///
    /// Every other host is taken to keep none: a chord it does keep is still
    /// bound, and named where nothing arrives.
    static func keptChords(_ program: Program) -> Set<KeyboardShortcut.Trigger> {
        switch program {
        case .windowsTerminal: [KeyboardShortcut(",", modifiers: .control).trigger]
        case .appleTerminal, .iTerm2, .ghostty, .warp, .gnomeTerminal, .xtermJS, .windowsConsole, .tmux,
            .unidentified:
            []
        }
    }
}
