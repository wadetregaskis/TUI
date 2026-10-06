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
    /// A quirk table, so the default is the one that cannot hurt, as for the
    /// cursor-advance quirks: a host is assumed to alias until measured not
    /// to. xterm, VTE (GNOME Terminal and its kin), Konsole and the Linux
    /// console do, by their tables of the encoding (unmeasured), and the
    /// assumption covers them. Where a host is wrongly taken to alias, the
    /// cost is small: a ⌃\ nothing took is offered as ⌃4, ⌃| and ⌃⇧\ before
    /// it quits, and a binding on one of those masks the driver's quit
    /// (`Terminal.maskQuitKey(for:)`).
    static let keepsQuitByteChordsApart: Set<Program> = []

    /// Whether `program` may send ⌃\'s byte, 0x1C, for ⌃4, ⌃| and ⌃⇧\ in its
    /// legacy encoding — every host but one in ``keepsQuitByteChordsApart``.
    /// Under the kitty keyboard protocol the chords arrive apart everywhere.
    static func mayAliasQuitByte(_ program: Program) -> Bool {
        !keepsQuitByteChordsApart.contains(program)
    }
}
