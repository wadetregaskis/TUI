//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyboardReportingEnvironment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// MARK: - KeyboardReporting

/// What the terminal reports about the keyboard beyond the keys themselves,
/// as the kitty keyboard protocol's negotiation at startup left it.
///
/// A terminal's legacy key encodings report a key going down and nothing
/// else: a held key's repeats arrive as more presses, a release sends
/// nothing, a modifier key pressed alone sends nothing, and Caps Lock and the
/// numeric pad leave no mark. Several terminals also speak the **kitty
/// keyboard protocol**, which reports all of those, and TUI turns it on at
/// startup wherever the terminal answers its query. Which of its enhancements
/// the terminal took decides which of these is `true`.
///
/// TUI's own record, which its input handling and undo hints act on. An
/// app asks `\.terminalCapabilities` instead, whose keyboard features
/// (`.disambiguatedKeys` to `.numericPad`) are built from this.
///
/// Fixed for the run: the terminal is asked once, before the first frame. A
/// user can keep TUI from asking — leaving every terminal in its legacy
/// encodings — with `TUI_KEYBOARD_PROTOCOL=0`.
/// See `Documentation/Terminals/Terminal compatibility survey.md`, "The kitty keyboard
/// protocol", for which terminals say they speak it.
package struct KeyboardReporting: Hashable, Sendable {
    /// Whether the terminal speaks the kitty keyboard protocol and took at
    /// least one of the enhancements TUI asked for.
    ///
    /// Not a promise that every keyboard event is reported: a terminal may
    /// take some enhancements and not others, and the properties below say
    /// which. Nor does it make ⌘ chords reach the app — see
    /// ``EventModifiers/command``.
    package let isEnhanced: Bool

    /// Whether Escape and every Control chord arrive as themselves. Where
    /// `false`, Ctrl-H, Ctrl-I, Ctrl-M and Ctrl-[ arrive as Backspace, Tab,
    /// Return and Escape, because the legacy encodings spend those bytes on
    /// them (see
    /// ``KeyboardShortcut/isDeliverableInTerminal``). Where `true`, a binding
    /// on one of them fires, and one that nothing binds still acts as the key
    /// it used to arrive as.
    package let disambiguatesKeys: Bool

    /// Whether a Control or Option chord with Shift arrives as its shifted
    /// key, so Ctrl-Shift-Z is not Ctrl-Z and Ctrl-Shift-minus (Ctrl-_) is not
    /// Ctrl-minus. Where `false`, Shift on a Control chord is lost, as the
    /// legacy encodings' control byte has no case.
    package let reportsShiftedKeys: Bool

    /// Whether a held key's repeats are told apart from its press: a
    /// ``KeyPress/Phases/repeat`` handler hears only repeats, and a
    /// ``KeyPress/Phases/down`` handler only the press. Where `false`, every
    /// repeat arrives as another press, and a handler for either phase hears
    /// them all.
    package let reportsRepeats: Bool

    /// Whether a key's release is reported, so a ``KeyPress/Phases/up``
    /// handler runs.
    package let reportsReleases: Bool

    /// Whether a modifier key pressed or released on its own is reported, so
    /// `onModifierKeysChanged(mask:initial:_:)` and
    /// `modifierKeyAlternate(_:_:)` see it.
    package let reportsModifierKeys: Bool

    /// Whether the Caps Lock state is reported on every key, so a press's
    /// modifiers include ``EventModifiers/capsLock`` while it is on.
    package let reportsLockStates: Bool

    /// Whether a key on the numeric keypad is told apart from its twin on the
    /// main keyboard, so its modifiers include ``EventModifiers/numericPad``.
    package let reportsNumericPad: Bool

    /// The chords the terminal keeps for its own bindings, which never reach
    /// the app in any encoding: Windows Terminal's ⌃, (its settings) and ⌃-
    /// (its font size) among them, as `TerminalClient.keptChords(_:)` lists
    /// them for each host. Empty where none is known, as for a terminal not
    /// measured.
    ///
    /// Not carried by `\.terminalCapabilities`: a TUI record of the host, as
    /// the quit byte's aliases are, and what TUI names keys by
    /// (``delivers(_:)``).
    package let keptChords: Set<KeyboardShortcut.Trigger>

    /// A terminal speaking only its legacy encodings: none of the above.
    package static let legacy = Self(flags: [])

    /// Whether the terminal sends `shortcut`, as a command key resolved it, as
    /// itself — not as another key that matches some other binding, and not
    /// as nothing: the one rule for whether a key is named anywhere the app
    /// lists its keys (a menu's key column, the status bar, F1's list), which
    /// names one that does arrive in its place where there is one (the owner,
    /// 2026-11-19).
    ///
    /// Never a chord the terminal keeps for itself (``keptChords``). Under the
    /// kitty keyboard protocol's disambiguate mode every chord arrives as
    /// itself, but for one that needs a modifier no key carries
    /// (``EventModifiers/command`` until a command key resolves it,
    /// ``EventModifiers/capsLock``, ``EventModifiers/numericPad``), and a
    /// Control chord on a shifted character (⌃_), which only a terminal that
    /// reports the shifted key (``reportsShiftedKeys``) tells apart from its
    /// unshifted key's — a letter's capital is always known. Otherwise, one
    /// every legacy encoding sends as itself
    /// (``KeyboardShortcut/isDeliverableInTerminal``): Ctrl-Shift-Z arrives as
    /// Ctrl-Z, and Ctrl-/ as Ctrl-minus.
    package func delivers(_ shortcut: KeyboardShortcut) -> Bool {
        guard !keptChords.contains(shortcut.trigger) else { return false }
        guard disambiguatesKeys else { return shortcut.isDeliverableInTerminal }
        guard case .key(let key, let modifiers) = shortcut.trigger else { return true }
        guard modifiers.isDisjoint(with: [.command, .capsLock, .numericPad]) else { return false }
        let character = key.character
        guard modifiers.contains(.control), !character.isLetter else { return true }
        let shifted = modifiers.contains(.shift) || Self.shiftedSymbols.contains(character)
        return !shifted || reportsShiftedKeys
    }

    /// Whether the terminal sends a shortcut that fires on `trigger`
    /// (``delivers(_:)``): for a list of what is bound, which holds triggers.
    package func delivers(_ trigger: KeyboardShortcut.Trigger) -> Bool {
        switch trigger {
        case .defaultAction, .cancelAction: true
        case .key(let key, let modifiers): delivers(KeyboardShortcut(key, modifiers: modifiers))
        }
    }

    /// The characters a US layout types with Shift, which a Control chord can
    /// name only where the terminal reports the shifted key.
    private static let shiftedSymbols = Set("~!@#$%^&*()_+{}|:\"<>?")

    /// What a terminal that took `flags` reports, and that keeps
    /// `keptChords` for itself.
    package init(flags: KittyKeyboardFlags, keptChords: Set<KeyboardShortcut.Trigger> = []) {
        self.keptChords = keptChords
        isEnhanced = !flags.isEmpty
        disambiguatesKeys = flags.contains(.disambiguateEscapeCodes)
        reportsShiftedKeys =
            flags.contains(.reportAlternateKeys)
            && !flags.isDisjoint(with: [.disambiguateEscapeCodes, .reportAllKeysAsEscapeCodes])
        reportsRepeats = flags.contains(.reportEventTypes)
        reportsReleases = flags.contains(.reportEventTypes)
        reportsModifierKeys = flags.contains(.reportAllKeysAsEscapeCodes)
        reportsLockStates = flags.contains(.reportAllKeysAsEscapeCodes)
        reportsNumericPad = flags.contains(.reportAllKeysAsEscapeCodes)
    }
}

// MARK: - Environment key

private struct KeyboardReportingKey: EnvironmentKey {
    /// A view rendered outside a running app (a test, a snapshot) has no
    /// terminal behind it to report anything.
    static let defaultValue = KeyboardReporting.legacy
}

extension EnvironmentValues {
    /// What the terminal reports about the keyboard beyond the keys — see
    /// ``KeyboardReporting``. An app reads `\.terminalCapabilities`.
    ///
    /// Published by the run loop from the startup negotiation.
    package var keyboardReporting: KeyboardReporting {
        get { self[KeyboardReportingKey.self] }
        set { self[KeyboardReportingKey.self] = newValue }
    }
}
