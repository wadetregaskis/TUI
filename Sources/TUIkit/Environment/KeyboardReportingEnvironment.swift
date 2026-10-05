//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KeyboardReportingEnvironment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - KeyboardReporting

/// What the terminal reports about the keyboard beyond the keys themselves —
/// which of SwiftUI's keyboard features can work here.
///
/// A terminal's legacy key encodings report a key going down and nothing
/// else: a held key's repeats arrive as more presses, a release sends
/// nothing, a modifier key pressed alone sends nothing, and Caps Lock and the
/// numeric pad leave no mark. Several terminals also speak the **kitty
/// keyboard protocol**, which reports all of those, and TUIkit turns it on at
/// startup wherever the terminal answers its query. Which of its enhancements
/// the terminal took decides which of these is `true`.
///
/// Read it to offer a fallback where a feature cannot work:
///
/// ```swift
/// @Environment(\.keyboardReporting) private var keyboard
///
/// var body: some View {
///     PeekableList()
///         .onKeyPress(.space, phases: .up) { _ in endPeek(); return .handled }
///     if !keyboard.reportsReleases {
///         Text("Press Space again to stop peeking")
///     }
/// }
/// ```
///
/// Everything it describes compiles everywhere. SwiftUI's
/// `KeyPress.Phases.up`, `onModifierKeysChanged(mask:initial:_:)`,
/// `modifierKeyAlternate(_:_:)`, ``EventModifiers/capsLock`` and
/// ``EventModifiers/numericPad`` work where the matching property is `true`,
/// and never fire, or never match, where it is `false`.
///
/// Fixed for the run: the terminal is asked once, before the first frame.
/// See `Documentation/Terminal-compatibility.md`, "The kitty keyboard
/// protocol", for which terminals say they speak it.
public struct KeyboardReporting: Hashable, Sendable {
    /// Whether the terminal speaks the kitty keyboard protocol and took at
    /// least one of the enhancements TUIkit asked for.
    ///
    /// Not a promise that every keyboard event is reported: a terminal may
    /// take some enhancements and not others, and the properties below say
    /// which. Nor does it make ⌘ chords reach the app — see
    /// ``EventModifiers/command``.
    public let isEnhanced: Bool

    /// Whether Escape and every Control chord arrive as themselves. Where
    /// `false`, Ctrl-H, Ctrl-I, Ctrl-J, Ctrl-M and Ctrl-[ arrive as Backspace,
    /// Tab, Return, Return and Escape, because the legacy encodings spend
    /// those bytes on them (see
    /// ``KeyboardShortcut/isDeliverableInTerminal``). Where `true`, a binding
    /// on one of them fires, and one that nothing binds still acts as the key
    /// it used to arrive as.
    public let disambiguatesKeys: Bool

    /// Whether a Control or Option chord with Shift arrives as its shifted
    /// key, so Ctrl-Shift-Z is not Ctrl-Z and Ctrl-Shift-minus (Ctrl-_) is not
    /// Ctrl-minus. Where `false`, Shift on a Control chord is lost, as the
    /// legacy encodings' control byte has no case.
    public let reportsShiftedKeys: Bool

    /// Whether a held key's repeats are told apart from its press: a
    /// ``KeyPress/Phases/repeat`` handler hears only repeats, and a
    /// ``KeyPress/Phases/down`` handler only the press. Where `false`, every
    /// repeat arrives as another press, and a handler for either phase hears
    /// them all.
    public let reportsRepeats: Bool

    /// Whether a key's release is reported, so a `KeyPress.Phases.up`
    /// handler runs.
    public let reportsReleases: Bool

    /// Whether a modifier key pressed or released on its own is reported, so
    /// `onModifierKeysChanged(mask:initial:_:)` and
    /// `modifierKeyAlternate(_:_:)` see it.
    public let reportsModifierKeys: Bool

    /// Whether the Caps Lock state is reported on every key, so a press's
    /// modifiers include ``EventModifiers/capsLock`` while it is on.
    public let reportsLockStates: Bool

    /// Whether a key on the numeric keypad is told apart from its twin on the
    /// main keyboard, so its modifiers include ``EventModifiers/numericPad``.
    public let reportsNumericPad: Bool

    /// A terminal speaking only its legacy encodings: none of the above.
    public static let legacy = Self(flags: [])

    /// What a terminal that took `flags` reports.
    init(flags: KittyKeyboardFlags) {
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
    /// ``KeyboardReporting``.
    ///
    /// Published by the run loop from the startup negotiation; read-only,
    /// because no view can change what the terminal reports.
    public internal(set) var keyboardReporting: KeyboardReporting {
        get { self[KeyboardReportingKey.self] }
        set { self[KeyboardReportingKey.self] = newValue }
    }
}
