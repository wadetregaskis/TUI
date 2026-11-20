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
    /// A chord listed here is never shown where the app names its keys (the
    /// menu bar, the status bar, F1's list): one that works is shown instead,
    /// or none (the owner, 2026-11-19: a shortcut that does not work in a
    /// terminal is not listed there, and the one that does is). Each is a
    /// default binding of the host's that took the chord in a measured run,
    /// whatever the app had pressed it for; a binding the host gives up when
    /// it has nothing to do (Windows Terminal's Alt-arrows, which move between
    /// panes, arrived where there was one pane) is not listed. A person can
    /// rebind any of them, which this cannot see.
    ///
    /// - Windows Terminal 1.25.3131.0, with all 31 kitty flags, 2026-11-19
    ///   (Terminal compatibility survey.md, "Keys under the kitty protocol"):
    ///   ⌃, (its settings) arrived as Control's own press and release alone,
    ///   as it arrived as nothing without the protocol, 2026-11-17 ("Keys");
    ///   ⌥⇧- (a split pane) as its modifiers alone; ⌃- (the font size) and
    ///   ⌃⇧V (its paste) as their releases alone. ⌃- is one of undo's keys and
    ///   ⌥⇧- one of redo's, so their hints name ⌃Z and ⌃⇧Z there. In a second
    ///   run that day, ⌃⇧P (its command palette), ⌃⇧N (a new window) and ⌃⇧D
    ///   (a duplicate tab) arrived as Shift's press alone, ⌃⇧A (select all)
    ///   and ⌃⇧. (its suggestions) as their releases alone, where ⌃⇧G, ⌃⇧H
    ///   and ⌃⇧O arrived whole: a file panel's Preview, New Folder, Desktop,
    ///   Applications and hidden files (``FilePanelCommand``), whose status
    ///   bar names none of them there. ⌃⇧. is listed in both its spellings,
    ///   as the panel binds both.
    /// - The same, 2026-11-20, the rest of its default bindings that TUI's
    ///   own keys share, with one tab, one pane and no selection: ⌥↩ (full
    ///   screen; a vertical field's newline, which ⌃J also types), ⌃⇧↑ ⌃⇧↓
    ///   (a line's scroll), ⌃⇧Home ⌃⇧End ⌃⇧PgUp ⌃⇧PgDn (scrolling) and ⌃⇧K
    ///   arrived as their releases alone; ⌃⇧F (its search) and ⌃⇧T (a new tab)
    ///   as their modifiers' presses alone, ⌃Tab and ⌃⇧Tab (its tab switcher)
    ///   likewise, even with one tab; and ⌃⇧W closed the window. TUI reads
    ///   each of those as a key it also takes without the extra modifier, or
    ///   by another (⌃F, Tab, ⌃J), and names none, so listing them changes no
    ///   hint. ⌥⇧↑ ⌥⇧↓ ⌥⇧← ⌥⇧→ (a pane's resize) and ⌃⇧C (its copy, with
    ///   nothing selected) arrived whole, and are not listed.
    ///
    /// Every other host is taken to keep none: a chord it does keep is still
    /// bound, and named, as nothing here knows it does not arrive.
    static func keptChords(_ program: Program) -> Set<KeyboardShortcut.Trigger> {
        switch program {
        case .windowsTerminal:
            Set(
                [
                    KeyboardShortcut(",", modifiers: .control), KeyboardShortcut("-", modifiers: .control),
                    KeyboardShortcut("_", modifiers: .option), KeyboardShortcut("v", modifiers: [.control, .shift]),
                    KeyboardShortcut("p", modifiers: [.control, .shift]),
                    KeyboardShortcut("n", modifiers: [.control, .shift]),
                    KeyboardShortcut("d", modifiers: [.control, .shift]),
                    KeyboardShortcut("a", modifiers: [.control, .shift]),
                    KeyboardShortcut(".", modifiers: [.control, .shift]), KeyboardShortcut(">", modifiers: .control),
                ].map(\.trigger) + Self.windowsTerminalNavigationChords)
        case .appleTerminal, .iTerm2, .ghostty, .warp, .gnomeTerminal, .xtermJS, .windowsConsole, .tmux,
            .unidentified:
            []
        }
    }

    /// Windows Terminal's kept chords measured on 2026-11-20 (above): its
    /// full screen, scrolling, search, tabs and window.
    private static let windowsTerminalNavigationChords: [KeyboardShortcut.Trigger] = [
        KeyboardShortcut(.return, modifiers: .option),
        KeyboardShortcut(.upArrow, modifiers: [.control, .shift]),
        KeyboardShortcut(.downArrow, modifiers: [.control, .shift]),
        KeyboardShortcut(.home, modifiers: [.control, .shift]),
        KeyboardShortcut(.end, modifiers: [.control, .shift]),
        KeyboardShortcut(.pageUp, modifiers: [.control, .shift]),
        KeyboardShortcut(.pageDown, modifiers: [.control, .shift]),
        KeyboardShortcut(.tab, modifiers: .control), KeyboardShortcut(.tab, modifiers: [.control, .shift]),
        KeyboardShortcut("f", modifiers: [.control, .shift]), KeyboardShortcut("k", modifiers: [.control, .shift]),
        KeyboardShortcut("t", modifiers: [.control, .shift]), KeyboardShortcut("w", modifiers: [.control, .shift]),
    ].map(\.trigger)
}
