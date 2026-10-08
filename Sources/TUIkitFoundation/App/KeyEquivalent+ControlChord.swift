//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KeyEquivalent+ControlChord.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Which keys name a Control chord

extension KeyEquivalent {
    /// Whether Control held with this key is a chord a legacy encoding sends
    /// a C0 byte of its own for — `@`, a letter, `[`, `\`, `]`, `^` or `_`
    /// (``KeyEvent/legacyControlByte``'s keys, either case), or `|`, which is
    /// ⌃⇧\\ on a US layout and sends ⌃\\'s 0x1C — so that a key-specific
    /// `onKeyPress` on it declares the Control chord as well as the key, for
    /// the user's quit key (`InputHandler.quitKeyBindings(byte:hostAliases:)`,
    /// `InputHandler.dispatchToDeclaredBindings(_:)`).
    ///
    /// Not a digit. A digit key asks for what is typed — a PIN field's
    /// `onKeyPress(keys:)` on "0"…"9" — and ⌃4 has no byte of its own: some
    /// terminals send another key's for it, ⌃\\'s. Matching on the key
    /// alone, such a field hears ⌃4, but it does not declare it, so it
    /// neither masks the quit key nor is offered ⌃\\ again as ⌃4 (the
    /// coordinator's ruling, 2026-10-06).
    var namesControlChord: Bool {
        guard let ascii = character.asciiValue else { return false }
        switch ascii {
        case 0x40...0x5F, 0x61...0x7A, 0x7C: return true  // @ A–Z [ \ ] ^ _, a–z, |
        default: return false
        }
    }
}
