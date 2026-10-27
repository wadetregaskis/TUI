//  🖥️ TUI — A Terminal UI framework for Swift
//  InputHandler+QuitKey.swift
//
//  The user's quit key in the input chain: which Control chord a legacy
//  encoding sends as which C0 byte, so the chain can tell the quit key's
//  chord when it reaches it; which other chords some terminals send ⌃\'s
//  byte for; and whether the app's bindings need the driver's quit masked.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - Whether the driver keeps the quit key

/// Which of the chords the user's quit key's byte could be the app declares a
/// binding on (`InputHandler.quitKeyBindings(byte:hostAliases:)`): what
/// decides whether the driver's quit is masked, and in which encoding
/// (`Terminal.maskQuitKey(for:)`).
enum QuitKeyBindings: Equatable {
    /// None: the driver keeps the quit in every encoding.
    case unbound

    /// ⌃4, ⌃| or ⌃⇧\ (with or without Option), on a host that may send
    /// ⌃\\'s byte for the chord in its legacy encoding, and not the quit key's
    /// own chord. The quit is masked in the legacy encoding, where the byte may
    /// be one of them; not under the kitty keyboard protocol, where each
    /// arrives as itself and ⌃\ is a report the driver never sees. But a pop
    /// of the protocol's flags puts the terminal in its legacy encoding,
    /// where the driver would quit the app on the binding's key — so the
    /// stall watchdog, whose pop that would be, is not armed for these
    /// (`Terminal.refreshStallWatch()`).
    case aliasOnly

    /// The quit key's own chord, with or without Option: masked in every
    /// encoding.
    case ownChord

    /// Whether the driver's quit is masked for these bindings in the
    /// terminal's legacy encoding (`legacyEncoding`), or under the kitty
    /// keyboard protocol.
    func masksQuitKey(inLegacyEncoding legacyEncoding: Bool) -> Bool {
        switch self {
        case .unbound: false
        case .aliasOnly: legacyEncoding
        case .ownChord: true
        }
    }
}

extension InputHandler {
    /// Which of the chords the user's quit key's byte could be the app
    /// DECLARES a binding on: what decides whether the driver's quit has to
    /// be masked (`Terminal.maskQuitKey(for:)`) so the byte reaches the app.
    /// Asked after every frame, whose render registered the bindings.
    ///
    /// The owner's rule (2026-10-06): ⌃\ is a hung app's way out, and stays
    /// the driver's unless the app binds it — or binds ⌃4, ⌃| or ⌃⇧\ where
    /// the terminal may send ⌃\\'s byte for that chord (`hostAliases`). With
    /// the byte, the chords count with Option too: a legacy encoding sends
    /// Option as an ESC before the byte, which the driver still acts on.
    ///
    /// Answered for the terminal's legacy encoding whatever the terminal
    /// speaks now: under the kitty keyboard protocol only ``QuitKeyBindings/ownChord``
    /// masks, but the stall watchdog's pop would put the terminal back in
    /// its legacy encoding, where ⌃4 may be ⌃\\'s byte again.
    ///
    /// Declared is what the framework can know without running the app's
    /// code (``declaresBinding(forAnyOf:)``). A handler that hears every key —
    /// `onKeyEvent`, `onKeyPress(phases:action:)` — cannot be known, and does
    /// not hear the quit key's byte while the driver has it.
    ///
    /// - Parameters:
    ///   - byte: The user's quit key's byte (`Terminal.quitKeyByte`), or
    ///     `nil` where there is none: then nothing is bound to it.
    ///   - hostAliases: The chords the host may send ⌃\\'s byte for in its
    ///     legacy encoding, as measured of it or assumed of one not measured
    ///     (`TerminalClient.quitByteAliases(_:)`).
    func quitKeyBindings(byte: UInt8?, hostAliases: TerminalClient.QuitByteAliases) -> QuitKeyBindings {
        guard let byte, let chords = QuitKeyChords.of(byte) else { return .unbound }
        if declaresBinding(forAnyOf: chords.own) { return .ownChord }
        let aliases = chords.aliases(on: hostAliases)
        guard !aliases.isEmpty else { return .unbound }
        return declaresBinding(forAnyOf: aliases) ? .aliasOnly : .unbound
    }

    /// Whether a binding the app declared takes one of `events` — what the
    /// framework can know without running the app's code:
    ///
    /// - a `.keyboardShortcut` (resolved through `.commandKey`, as
    ///   registered), a menu item's among them, or a framework default;
    /// - an `onKeyPress` on keys, on the path to the focused view, and for a
    ///   Control chord only on a key that names one
    ///   (``KeyEquivalent/namesControlChord``: `"|"` declares ⌃|, `"4"` does
    ///   not declare ⌃4) — not one on a set of characters, which asks for
    ///   typed text, not chords (Control is not looked at, so `.decimalDigits`
    ///   would claim ⌃4);
    /// - a status-bar item with an action, and the status bar's quit key;
    /// - the scene's undo and redo keys.
    /// Whether a paste of `mimeType` would be taken by a paste command on the
    /// path to the focused view — `onPasteCommand(of:)`, whose types it
    /// conforms to. What an OSC 5522 paste asks of each type the clipboard
    /// lists, to read only what something will take.
    func acceptsPaste(ofMIMEType mimeType: String) -> Bool {
        guard let focused = focusManager.focusedIdentity else { return false }
        let paste = KeyEvent(key: .paste(""), pasteAttachments: [PasteAttachment(type: mimeType, bytes: [])])
        return keyEventDispatcher.declaresFocusPathBinding(forAnyOf: [paste], focusedIdentity: focused, stage: .command)
    }

    func declaresBinding(forAnyOf events: [KeyEvent]) -> Bool {
        if events.contains(where: keyboardShortcuts.hasShortcut(for:)) { return true }
        if statusBar.takesAny(of: events) || events.contains(where: statusBar.quitShortcut.matches) { return true }
        if undoManager != nil, events.contains(where: { undoKeys.command(for: $0) != nil }) { return true }
        if focusPathHearsKeys, let focused = focusManager.focusedIdentity {
            return keyEventDispatcher.declaresFocusPathBinding(forAnyOf: events, focusedIdentity: focused)
        }
        return false
    }

    /// Offers `event` to the bindings the app declared for it and to nothing
    /// else — those ``declaresBinding(forAnyOf:)`` counts, in the chain's
    /// order: the focus path's `onKeyPress` on keys, the status bar's items,
    /// the app's shortcuts, the status bar's quit key, the undo keys. The
    /// shortcuts by the pane rule layer 3.5 fires them by: a pane's — a live
    /// sheet's — only with the focus in it, and the page's from a pane only
    /// where it does not bind the key and no modal section holds the focus
    /// (`KeyboardShortcutRegistry.trigger(for:activePane:reachesPage:)`).
    ///
    /// What a ⌃\\ nothing took goes round as, where it may have been ⌃4, ⌃|
    /// or ⌃⇧\\ (``handle(_:)``): only a binding on one of those can have
    /// meant it. Everything else in the chain heard the key once already, as
    /// ⌃\\ — a handler that hears every key (`onKeyEvent`,
    /// `onKeyPress(phases:action:)`) and one on a set of characters among
    /// them — and offered it again as ⌃4, a number field's `.decimalDigits`
    /// would type a 4 for the user's quit key (the coordinator's ruling,
    /// round 6).
    ///
    /// - Returns: Whether one of them took it.
    func dispatchToDeclaredBindings(_ event: KeyEvent) -> Bool {
        if focusPathHearsKeys, let focused = focusManager.focusedIdentity,
            keyEventDispatcher.dispatchDeclaredFocusPath(event, focusedIdentity: focused)
        {
            return true
        }
        if statusBar.handleKeyEvent(event)
            || keyboardShortcuts.trigger(
                for: event, activePane: focusManager.activePaneID, reachesPage: !focusManager.activeSectionIsModal,
                modalSection: focusManager.activeModalSectionID)
        {
            return true
        }
        return runQuitShortcut(event) || runUndoKey(event)
    }
}

// MARK: - The quit key's chords

/// The chords the user's quit key's byte could be, which
/// `InputHandler.quitKeyBindings(byte:hostAliases:)` asks the app's bindings
/// about after every frame: the byte's own Control chord, and for ⌃\\'s 0x1C
/// the chords the host may send it for too, each with and without Option
/// (the byte after an ESC, which the driver still acts on).
///
/// Made once for each byte — and each set of chords a host may alias — and
/// kept, rather than after every frame: the byte is the user's, from the
/// termios raw mode was made from, so it does not change while the app runs.
struct QuitKeyChords {
    /// The byte's own chord, and with Option.
    let own: [KeyEvent]

    /// For each set of chords a host may send ⌃\\'s byte for, by its raw
    /// value: those of ⌃4, ⌃| and ⌃⇧\\ (``KeyEvent/quitByteAliases(on:)``),
    /// and with Option; all empty for any other byte.
    private let aliasesByHost: [[KeyEvent]]

    /// The chords the byte could be on a host that may send ⌃\\'s byte for
    /// `host`'s, and with Option: ⌃4, ⌃| and ⌃⇧\\ for ⌃\\'s byte where the
    /// host may alias them all; empty for any other byte.
    func aliases(on host: TerminalClient.QuitByteAliases) -> [KeyEvent] {
        aliasesByHost[Int(host.rawValue)]
    }

    /// The chords for `byte`, or `nil` for one no Control chord sends.
    static func of(_ byte: UInt8) -> Self? {
        Int(byte) < table.count ? table[Int(byte)] : nil
    }

    /// Every C0 byte's chords, made at first use.
    private static let table: [Self?] = (0...0x1F).map { byte in
        KeyEvent.controlChord(sending: UInt8(byte)).map { chord in
            Self(
                own: withOption([chord]),
                aliasesByHost: TerminalClient.QuitByteAliases.everySet.map {
                    withOption(chord.quitByteAliases(on: $0))
                })
        }
    }

    /// `chords`, and each with Option.
    private static func withOption(_ chords: [KeyEvent]) -> [KeyEvent] {
        chords + chords.map { KeyEvent(key: $0.key, ctrl: $0.ctrl, alt: true, shift: $0.shift) }
    }
}

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
    /// ⌃\\, of those `host` may send ⌃\\'s 0x1C for
    /// (`TerminalClient.quitByteAliases(_:)`): ⌃4, and ⌃| and ⌃⇧\\ — one chord
    /// on a US layout — in that order. Option kept, as the ESC before the
    /// byte keeps it; empty for any other event.
    ///
    /// ⌃\ is the reading the parser gives the byte, so it is the one a
    /// binding on both gets: on a terminal that aliases them they cannot be
    /// told apart.
    func quitByteAliases(on host: TerminalClient.QuitByteAliases) -> [KeyEvent] {
        guard ctrl, !shift, key == .character("\\") else { return [] }
        var aliases: [KeyEvent] = []
        if host.contains(.controlFour) {
            aliases.append(KeyEvent(key: .character("4"), ctrl: true, alt: alt, phase: phase))
        }
        if host.contains(.controlShiftBackslash) {
            aliases.append(KeyEvent(key: .character("|"), ctrl: true, alt: alt, phase: phase))
            aliases.append(KeyEvent(key: .character("\\"), ctrl: true, alt: alt, shift: true, phase: phase))
        }
        return aliases
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
