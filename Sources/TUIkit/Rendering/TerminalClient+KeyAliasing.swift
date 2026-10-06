//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalClient+KeyAliasing.swift
//
//  Which terminals send ⌃\'s byte for other chords in their legacy encoding.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - ⌃\'s byte, and the chords that may share it

extension TerminalClient {
    /// The hosts measured to send ⌃4, ⌃| and ⌃⇧\ apart from ⌃\ in their
    /// legacy encoding, rather than as ⌃\'s 0x1C. **Empty: none has been
    /// measured yet** (2026-10-06; Apple Terminal, iTerm2 and Warp are to be).
    ///
    /// A quirk table, defaulting to the assumption that covers the hosts
    /// known to alias: a host is assumed to alias until measured not to.
    /// xterm, VTE (GNOME Terminal and its kin), Konsole and the Linux console
    /// do, by their tables of the encoding (unmeasured). Taken wrongly of a
    /// host that sends ⌃4 apart — and until hosts are measured, every one is
    /// taken so — it costs that host's users their quit key wherever the app
    /// binds ⌃4, ⌃| or ⌃⇧\: an app with a ⌘4 shortcut (⌃4 under
    /// `.commandKey(.control)`) has the driver's quit masked
    /// (`Terminal.maskQuitKey(for:)`), so the user's ⌃\ arrives as a key
    /// that nothing takes as ⌃\, is offered as ⌃4, and runs the ⌘4
    /// shortcut instead of quitting; and a hung app cannot be quit by ⌃\ at
    /// all while such a binding is on screen. Measuring a host and listing it
    /// here gives it both back.
    static let keepsQuitByteChordsApart: Set<Program> = []

    /// Whether `program` may send ⌃\'s byte, 0x1C, for ⌃4, ⌃| and ⌃⇧\ in its
    /// legacy encoding — every host but one in ``keepsQuitByteChordsApart``.
    /// Under the kitty keyboard protocol the chords arrive apart everywhere.
    static func mayAliasQuitByte(_ program: Program) -> Bool {
        !keepsQuitByteChordsApart.contains(program)
    }
}
