//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyLetterCase.swift
//
//  How a key that is a letter pressed alone is drawn, wherever TUI draws a
//  key — the status bar, the F1 list of shortcuts, a menu's shortcut column:
//  as a capital (`K`), as macOS draws it, or as it is typed (`k`). A key that
//  needs Shift is `⇧K` in either. The owner's APPFB-4, 2026-11-14.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The case

/// How TUI draws a key that is a letter pressed with no modifier: in upper
/// case, as a macOS menu draws a key equivalent, or in lower case, as it is
/// typed.
///
/// TUI-specific. TUI draws keys as macOS does (``KeyboardShortcut/displayString``):
/// the modifiers in the order ⌃ ⌥ ⇧ ⌘, then the key, a letter in upper case —
/// `K` for the bare k key, `⇧K` for Shift-K, `⌃K` for Control-K. That is the
/// default, here as on a Mac. An app whose users read keys as a terminal
/// program writes them (`k kill`, as `htop` and `less` do) asks for
/// ``asTyped``, which draws a bare letter in lower case. Either way a key that
/// needs Shift is drawn with `⇧` (`⇧K`), never as a bare capital, so the case
/// alone never has to say whether Shift is held.
///
/// The status bar, the F1 list of shortcuts and a menu's shortcut column all
/// follow ``EnvironmentValues/keyLetterCase``; text of the app's own that
/// names a key can follow it through ``spelling(_:)``.
///
/// ```swift
/// ContentView()
///     .keyLetterCase(.asTyped)   // k kill, ⇧K kill all, ⌃S save
/// ```
public enum KeyLetterCase: Hashable, Sendable, CaseIterable {
    /// A letter in upper case, as a macOS menu draws it: `K`, `⇧K`, `⌃K`.
    /// The default.
    case capital

    /// A letter pressed alone in lower case, as it is typed: `k`. A letter
    /// with a modifier is drawn as under ``capital`` — `⇧K`, `⌃K` — so Shift
    /// is still always a `⇧`.
    case asTyped

    /// `name`, a key or shortcut as TUI draws it in ``capital``
    /// (``KeyboardShortcut/displayString``), in this case.
    ///
    /// Under ``capital`` it is `name`. Under ``asTyped`` a name that is one
    /// upper-case letter, a letter pressed alone, is that letter in lower
    /// case; anything else — `⇧K`, `⌃K`, `⎋`, `1`, `F5` — is `name`.
    ///
    /// ```swift
    /// @Environment(\.keyLetterCase) private var keyLetterCase
    ///
    /// Text(keyLetterCase.spelling(killShortcut.displayString ?? "") + " kill")
    /// ```
    public func spelling(_ name: String) -> String {
        guard self == .asTyped, name.count == 1, let letter = name.first, letter.isUppercase else { return name }
        // A letter whose lower case is not one character keeps its capital.
        let lower = letter.lowercased()
        return lower.count == 1 ? lower : name
    }

    /// `shortcut`, a ``StatusBarItem``'s key as its string writes it, as it is
    /// drawn in this case.
    ///
    /// An item's string is in the bar's own vocabulary, where the case is the
    /// Shift: `"k"` is k and `"K"` is Shift-K. A string of one letter is drawn
    /// as the key it binds is drawn anywhere else — `K` (`k` ``asTyped``) for
    /// `"k"`, `⇧K` for `"K"` — and anything else as written: a digit, `?`,
    /// `⎋`, `⌃Z`, `1-9`, `c|C`, `↑↓`, and a letter with no one-character
    /// capital (`ß`), which has no key cap of its own.
    package func statusBarItemKey(_ shortcut: String) -> String {
        guard shortcut.count == 1, let letter = shortcut.first, letter.isLetter else { return shortcut }
        if letter.isLowercase { return spelling(KeySymbols.keyCap(letter)) }
        guard letter.isUppercase, letter.lowercased().count == 1 else { return shortcut }
        return "⇧" + shortcut
    }
}

// MARK: - Environment

/// `\.keyLetterCase`'s key.
private struct KeyLetterCaseKey: EnvironmentKey {
    static let defaultValue = KeyLetterCase.capital
}

extension EnvironmentValues {
    /// How a key that is a letter pressed alone is drawn — see
    /// ``KeyLetterCase``. ``KeyLetterCase/capital`` by default.
    public var keyLetterCase: KeyLetterCase {
        get { self[KeyLetterCaseKey.self] }
        set { self[KeyLetterCaseKey.self] = newValue }
    }
}

extension View {
    /// Sets how the keys drawn in this subtree write a letter pressed alone:
    /// as a capital (`K`, the default, as macOS draws it) or as typed (`k`).
    /// A key that needs Shift is `⇧K` either way.
    ///
    /// Reaches the status bar, the F1 list of shortcuts (which writes keys as
    /// the status bar beside it does) and a menu's shortcut column. Set on a
    /// scene with `.environment(\.keyLetterCase, .asTyped)` it reaches
    /// everything the scene draws. TUI-specific; see ``KeyLetterCase``.
    ///
    /// - Parameter letterCase: The case.
    /// - Returns: A view whose keys are drawn in `letterCase`.
    nonisolated public func keyLetterCase(_ letterCase: KeyLetterCase) -> some View {
        environment(\.keyLetterCase, letterCase)
    }
}
