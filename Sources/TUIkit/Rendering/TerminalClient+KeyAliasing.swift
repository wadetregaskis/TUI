//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalClient+KeyAliasing.swift
//
//  Which chords each terminal sends ⌃\'s byte for in its legacy encoding.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - ⌃\'s byte, and the chords that may share it

extension TerminalClient {
    /// The chords other than ⌃\\ that a terminal may send ⌃\\'s byte, 0x1C,
    /// for in its legacy encoding: what the user's quit key's byte may have
    /// been (`InputHandler.quitKeyBindings(byte:hostAliases:)`), one set of
    /// them for each host (``quitByteAliases(_:)``).
    struct QuitByteAliases: OptionSet, Hashable, Sendable {
        let rawValue: UInt8

        /// ⌃4.
        static let controlFour = Self(rawValue: 1 << 0)

        /// ⌃⇧\\ — on a US layout the same chord as ⌃|, so the key events ⌃⇧\\
        /// and ⌃| both: measured as the one chord typed.
        static let controlShiftBackslash = Self(rawValue: 1 << 1)

        /// Both: what a host not measured is taken to send.
        static let all: Self = [.controlFour, .controlShiftBackslash]

        /// Every set of them, by raw value — `[]` first, ``all`` last — for a
        /// table made once for each (`QuitKeyChords`).
        static let everySet: [Self] = (0...all.rawValue).map(Self.init(rawValue:))
    }

    /// The chords `program` may send ⌃\\'s byte for in its legacy encoding.
    /// Under the kitty keyboard protocol the chords arrive apart everywhere.
    ///
    /// The owner's `cat -v` readings of 2026-10-06 (Terminal-compatibility.md,
    /// "The three that share ⌃\\'s 0x1C"), on a US keyboard:
    ///
    /// - Apple Terminal 2.14: ⌃⇧\\ sends 0x1C; ⌃4 sends nothing at all.
    /// - iTerm2 3.7.3 and Warp 0.2026.09.30: ⌃4 and ⌃⇧\\ both send 0x1C.
    /// - Ghostty 1.3.1: ⌃4 sends 0x1C; ⌃⇧\\ sends `CSI 124;5u`, apart.
    ///
    /// A host not measured — tmux, which re-encodes whatever terminal it runs
    /// in, and one not identified — is taken to send ⌃\\'s byte for both, as
    /// xterm, VTE (GNOME Terminal and its kin), Konsole and the Linux console
    /// do by their tables of the encoding (unmeasured): the assumption that
    /// covers the hosts known to alias. Taken wrongly of a chord a host sends
    /// apart, it costs that host's users their quit key wherever the app binds
    /// the chord — an app with a ⌘4 shortcut (⌃4 under `.commandKey(.control)`)
    /// has the driver's quit masked (`Terminal.maskQuitKey(for:)`), so the
    /// user's ⌃\\ arrives as a key that nothing takes as ⌃\\, is offered as
    /// ⌃4, and runs the ⌘4 shortcut instead of quitting; and a hung app cannot
    /// be quit by ⌃\\ at all while such a binding is on screen. Measuring a
    /// host, per chord, and listing it here gives it both back.
    static func quitByteAliases(_ program: Program) -> QuitByteAliases {
        switch program {
        case .appleTerminal: .controlShiftBackslash
        case .iTerm2, .warp: .all
        case .ghostty: .controlFour
        case .tmux, .unidentified: .all
        }
    }
}
