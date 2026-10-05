//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KittyKeyboardFlags.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Flags

/// The kitty keyboard protocol's progressive enhancements, as the bits an
/// application pushes with `CSI > flags u` and a terminal reports with
/// `CSI ? flags u`.
///
/// See <https://sw.kovidgoyal.net/kitty/keyboard-protocol/>. Each flag widens
/// what the terminal reports, and each has a reason TUIkit asks for it:
///
/// | Flag | Enhancement | What TUIkit needs it for |
/// |---|---|---|
/// | 1 | disambiguate escape codes | Escape, and Ctrl-H/I/J/M/[ as themselves rather than Backspace, Tab, Return and Escape |
/// | 2 | report event types | a held key's repeats, and releases |
/// | 4 | report alternate keys | the shifted key of a Control or Option chord (Ctrl-Shift-Z as `Z`), and a non-Latin layout's key by its Latin position |
/// | 8 | report all keys as escape codes | a modifier key pressed alone, Caps Lock on every key, the keypad's digits |
/// | 16 | report associated text | the text a key typed, which flag 8 would otherwise take away |
///
/// Flag 16 is what keeps typing byte-identical under flag 8: with 8 on, every
/// key, a plain letter included, arrives as an escape code rather than as the
/// text it typed, and only 16 puts that text back into the report. So a
/// shifted character, a dead key's accented letter, a non-US layout's letters
/// and an input method's composed text all arrive as the terminal composed
/// them, as they do in a legacy encoding. Without 16, 8 is not asked for (see
/// the negotiation in `Terminal`).
package struct KittyKeyboardFlags: OptionSet, Hashable, Sendable {
    package let rawValue: Int
    package init(rawValue: Int) { self.rawValue = rawValue }

    /// Flag 1: Escape, and every Control, Option and Control-Option chord on a
    /// key that types ASCII, arrive as `CSI u` reports rather than as the
    /// legacy bytes that collide with other keys.
    package static let disambiguateEscapeCodes = Self(rawValue: 1)
    /// Flag 2: a repeat and a release are reported, as event types 2 and 3.
    package static let reportEventTypes = Self(rawValue: 2)
    /// Flag 4: the shifted key and the base-layout key are reported beside the
    /// key itself.
    package static let reportAlternateKeys = Self(rawValue: 4)
    /// Flag 8: every key is an escape code, the modifier keys included, and
    /// the lock states are reported on every key.
    package static let reportAllKeysAsEscapeCodes = Self(rawValue: 8)
    /// Flag 16: a key that typed text carries that text in its report.
    package static let reportAssociatedText = Self(rawValue: 16)

    /// What TUIkit asks a terminal for: all five.
    package static let requested: Self = [
        .disambiguateEscapeCodes, .reportEventTypes, .reportAlternateKeys,
        .reportAllKeysAsEscapeCodes, .reportAssociatedText,
    ]
}
