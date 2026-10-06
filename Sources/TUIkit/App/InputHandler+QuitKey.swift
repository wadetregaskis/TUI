//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InputHandler+QuitKey.swift
//
//  The user's quit key in the input chain: which Control chord a legacy
//  encoding sends as which C0 byte, so the chain can tell the quit key's
//  chord when it reaches it; which other chords some terminals send ⌃\'s
//  byte for; and whether the app's bindings need the driver's quit masked.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Whether the driver keeps the quit key

extension InputHandler {
    /// Whether the driver's quit has to be masked (`Terminal.maskQuitKey`)
    /// so the user's quit key's byte reaches the app: whether a binding the
    /// app DECLARED is on a chord the byte could be for. Asked after every
    /// frame, whose render registered the bindings.
    ///
    /// The owner's rule (2026-10-06): ⌃\ is a hung app's way out, and stays
    /// the driver's unless the app binds it — or binds ⌃4, ⌃| or ⌃⇧\ where
    /// the terminal may send ⌃\'s byte for them (`aliasing`). With the
    /// byte, the chords count with Option too: a legacy encoding sends
    /// Option as an ESC before the byte, which the driver still acts on.
    ///
    /// Declared is what the framework can know without running the app's
    /// code (``declaresBinding(forAnyOf:)``). A handler that hears every key —
    /// `onKeyEvent`, `onKeyPress(phases:action:)` — cannot be known, and does
    /// not hear the quit key's byte while the driver has it.
    ///
    /// - Parameters:
    ///   - byte: The user's quit key's byte (`Terminal.quitKeyByte`), or
    ///     `nil` where there is none: then nothing needs masking.
    ///   - aliasing: Whether ⌃4, ⌃| and ⌃⇧\ may arrive as ⌃\'s byte
    ///     (``quitByteAliasing``): the legacy encoding, on a host not
    ///     measured to send them apart.
    func quitKeyNeedsMasking(byte: UInt8?, aliasing: Bool) -> Bool {
        guard let byte, let chord = KeyEvent.controlChord(sending: byte) else { return false }
        let plain = aliasing ? [chord] + chord.quitByteAliases : [chord]
        let chords = plain + plain.map {
            KeyEvent(key: $0.key, ctrl: $0.ctrl, alt: true, shift: $0.shift)
        }
        return declaresBinding(forAnyOf: chords)
    }

    /// Whether a binding the app declared takes one of `events` — what the
    /// framework can know without running the app's code:
    ///
    /// - a `.keyboardShortcut` (resolved through `.commandKey`, as
    ///   registered), a menu item's among them, or a framework default;
    /// - an `onKeyPress` on keys or characters, on the path to the focused
    ///   view;
    /// - a status-bar item with an action, and the status bar's quit key;
    /// - the scene's undo and redo keys.
    func declaresBinding(forAnyOf events: [KeyEvent]) -> Bool {
        if events.contains(where: keyboardShortcuts.hasShortcut(for:)) { return true }
        if events.contains(where: { statusBar.item(taking: $0) != nil || statusBar.quitShortcut.matches($0) }) {
            return true
        }
        if undoManager != nil, events.contains(where: { undoKeys.command(for: $0) != nil }) { return true }
        if focusPathHearsKeys, let focused = focusManager.focusedIdentity {
            return keyEventDispatcher.declaresFocusPathBinding(forAnyOf: events, focusedIdentity: focused)
        }
        return false
    }
}

// MARK: - The quit key's chords

extension KeyEvent {
    /// The C0 byte a legacy encoding sends for this Control chord — Ctrl with
    /// `@`, a letter, `[`, `\`, `]`, `^` or `_` — or `nil` for any other
    /// event. Option does not change it (a legacy encoding sends the byte
    /// after an ESC, and the driver acts on the byte); Shift does.
    var legacyControlByte: UInt8? {
        guard ctrl, !shift, case .character(let character) = key, let ascii = character.asciiValue else {
            return nil
        }
        switch ascii {
        case 0x61...0x7A: return ascii - 0x60  // a–z: 0x01–0x1A
        case 0x40, 0x5B...0x5F: return ascii - 0x40  // @ [ \ ] ^ _: 0x00, 0x1B–0x1F
        default: return nil
        }
    }

    /// The chords a terminal in its legacy encoding may have meant by this
    /// ⌃\: ⌃4, ⌃| and ⌃⇧\, for which xterm, VTE (GNOME Terminal and its
    /// kin), Konsole and the Linux console send ⌃\'s 0x1C too, by their tables
    /// of the encoding (not measured). Option kept, as the ESC before the
    /// byte keeps it; empty for any other event.
    ///
    /// ⌃\ is the reading the parser gives the byte, so it is the one a
    /// binding on both gets: on a terminal that aliases them they cannot be
    /// told apart.
    var quitByteAliases: [KeyEvent] {
        guard ctrl, !shift, key == .character("\\") else { return [] }
        return [
            KeyEvent(key: .character("4"), ctrl: true, alt: alt, phase: phase),
            KeyEvent(key: .character("|"), ctrl: true, alt: alt, phase: phase),
            KeyEvent(key: .character("\\"), ctrl: true, alt: alt, shift: true, phase: phase),
        ]
    }

    /// The Control chord a legacy encoding sends `byte` for — Ctrl with `@`,
    /// a letter, `[`, `\`, `]`, `^` or `_` (``legacyControlByte``'s
    /// inverse) — or `nil` for any other byte.
    static func controlChord(sending byte: UInt8) -> KeyEvent? {
        let character: UInt8
        switch byte {
        case 0x01...0x1A: character = byte + 0x60  // a–z
        case 0x00, 0x1B...0x1F: character = byte + 0x40  // @ [ \ ] ^ _
        default: return nil
        }
        return KeyEvent(key: .character(Character(UnicodeScalar(character))), ctrl: true)
    }
}
