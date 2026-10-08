//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalIdentity.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - What the terminal said about itself

/// A terminal's answers to the identity queries in ``TerminalIdentityQuery``.
///
/// Deliberately holds the replies verbatim rather than a verdict: the parse is
/// mechanical and testable, the verdict is a judgement about measured terminal
/// behaviour, and keeping them apart means the judgement can be argued with
/// (and unit-tested) without a terminal in the room.
struct TerminalIdentity: Equatable {
    /// The Primary Device Attributes reply (`ESC[?…c`), verbatim, or `nil` if
    /// the terminal did not answer.
    var primaryAttributes: String?

    /// The Secondary Device Attributes reply (`ESC[>…c`), verbatim, or `nil`.
    var secondaryAttributes: String?

    /// Whether the terminal answered XTVERSION at all. The *content* is not
    /// needed here — under ``TerminalHost/hostProgram(environment:)`` a
    /// terminal that answers XTVERSION either named itself in the environment
    /// or is one tmux's client identification already handles; what matters to
    /// the fingerprint below is that Apple Terminal answers **nothing**.
    var answeredVersion: Bool = false

    /// Whether the status fence's reply, `CSI 0 n`, was seen. The exchange is
    /// complete once it has been: every terminal answers DSR, and it is sent
    /// last, so its arrival means every earlier query has either answered or
    /// declined to.
    var sawFence: Bool = false

    /// Bytes that arrived during the exchange and are not replies to it —
    /// keystrokes typed while the app was starting. They belong to the input
    /// parser, and dropping them would silently eat a keypress.
    var unconsumed: [UInt8] = []
}

// MARK: - The verdict

extension TerminalHost {

    /// The `TERM_PROGRAM`-style name of the terminal that gave these answers,
    /// or `nil` for one they do not positively identify.
    ///
    /// `nil` is the overwhelmingly common answer and the safe one: absent
    /// explicit evidence, a terminal is assumed to render correctly, and every
    /// compensation gated on a host name works around a *measured defect*.
    /// Naming a terminal that does not have those defects would break rows that
    /// were fine, so this identifies exactly one host and does it by
    /// conjunction.
    ///
    /// **Apple Terminal**, measured 2026-08-26 (Terminal.app 455.1, macOS 15.7,
    /// through an ssh hop, `Tools/TerminalProbes/identity_probe.py`):
    ///
    /// | Query | Apple Terminal | Ghostty | Warp | iTerm2 |
    /// |---|---|---|---|---|
    /// | XTVERSION | *silent* | answers | answers | answers |
    /// | DA1 | `ESC[?1;2c` | `ESC[?62;22c` | `ESC[?62c` | `ESC[?62;…c` |
    /// | DA2 | `ESC[>1;95;0c` | `ESC[>1;10;0c` | — | `ESC[>…;…;0c` |
    ///
    /// (Ghostty's and Warp's replies were read out of their shipped binaries;
    /// the XTVERSION column is the measured table in
    /// `Documentation/Terminal-compatibility.md`.)
    ///
    /// All three clauses carry weight, and each excludes something the others
    /// do not:
    ///
    /// - **XTVERSION silence** excludes every terminal that answers it — the
    ///   three above, and kitty, WezTerm, foot and contour besides.
    /// - **DA1 `ESC[?1;2c`** is "VT100 with the Advanced Video Option", a 1978
    ///   feature set. Modern emulators report VT220 or later (`?62`, `?63`,
    ///   `?64`) because applications gate features on it, so this is the clause
    ///   that does most of the work.
    /// - **DA2 `ESC[>1;…;0c`** excludes the multiplexers, which are the real
    ///   collision risk for the DA1 clause: GNU screen also reports VT100+AVO,
    ///   but identifies itself as terminal type 83 (`'S'`), and xterm as 41.
    ///   tmux never reaches here — it is detected from `$TMUX` first — but
    ///   screen is not detected at all, and applying Apple Terminal's
    ///   compensation inside a multiplexer would corrupt its grid.
    ///
    /// The firmware field of DA2 is deliberately **not** pinned to the measured
    /// `95`: it is a version number by definition, and matching it exactly
    /// would mean a macOS update silently switching the compensation back off —
    /// which is precisely the failure this whole path exists to end. The
    /// identifying fields are the terminal type (`1`) and the ROM cartridge
    /// (`0`).
    static func nameFromDeviceAttributes(_ identity: TerminalIdentity) -> String? {
        guard !identity.answeredVersion,
            identity.primaryAttributes == "\u{1B}[?1;2c",
            let secondary = identity.secondaryAttributes,
            secondary.hasPrefix("\u{1B}[>1;"), secondary.hasSuffix(";0c")
        else { return nil }
        return "Apple_Terminal"
    }
}

// MARK: - Seeding what was discovered

extension TerminalHost {

    /// What the startup Device Attributes exchange asked and was told, kept for
    /// the diagnostic surface (``TerminalClient/current``).
    ///
    /// `nil` when the exchange never ran — the environment already named the
    /// host, or we are in a tmux pane, or there is no terminal at all. Nothing
    /// in rendering reads this; the answer itself travels through the
    /// environment (see ``seedDiscoveredHost(_:)``), which is what keeps a
    /// single source of truth for "which terminal is this".
    ///
    /// Written once, by the app's startup (`identify(using:)`, beside its
    /// only caller in App.swift), before anything reads it.
    @MainActor static var startupIdentity: TerminalIdentity?
}
