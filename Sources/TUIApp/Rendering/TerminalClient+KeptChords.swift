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
    ///   nothing (Terminal compatibility survey.md, "Keys"); with
    ///   the protocol on it is unmeasured, and taken to be kept too, as a
    ///   binding is matched before the key is encoded at all. Its other
    ///   default bindings (⌃=, ⌃- and ⌃0 for the font size, ⌃V, the ⌃⇧ chords
    ///   for tabs, panes and find, Alt-arrows for panes) are not listed: a
    ///   person can rebind any of them, so a list could be wrong for them, and
    ///   whether to list them is the owner's call (Windows port.md).
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
