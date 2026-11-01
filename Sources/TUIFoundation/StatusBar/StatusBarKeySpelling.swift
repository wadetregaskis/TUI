//  🖥️ TUI — A Terminal UI framework for Swift
//  StatusBarKeySpelling.swift
//
//  How the status bar draws an item's key written as one letter: as a macOS
//  menu draws a key equivalent (`Q`, `⇧N`), or as the item's string is typed
//  (`q`, `N`), where the case is the Shift.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The spelling

/// How the status bar draws an item's key when the item's `shortcut` is one
/// letter.
///
/// TUI-specific. A ``StatusBarItem``'s `shortcut` string is the key it binds,
/// in the bar's own vocabulary, where the case is the Shift: `"q"` is q, and
/// `"N"` is Shift-N. Every other key TUI names is drawn as a macOS menu
/// draws a key equivalent (``KeyboardShortcut/displayString``): a letter in
/// upper case, Shift as `⇧`. By default the bar draws a one-letter key that
/// way too, so `y yes` reads `Y yes` beside `⌃Z undo`, and an app's `"N"`
/// item reads `⇧N` (the owner's ruling B-KS-1, 2026-10-23). The string still
/// binds the key and names the item; only what is drawn changes.
///
/// ```swift
/// StatusBar()
///     .statusBarKeySpelling(.asTyped)   // `y yes`, `N new`
/// ```
public enum StatusBarKeySpelling: Hashable, Sendable, CaseIterable {
    /// As a macOS menu draws a key: a letter in upper case, and a capital as
    /// `⇧` and the letter — `Q`, `⇧N`. The default.
    case menu

    /// As the item's string is typed, the TUI convention in which lower case
    /// means no Shift — `q`, `N`.
    case asTyped

    /// `shortcut`, an item's key as its string writes it, as the bar draws it
    /// in this spelling.
    ///
    /// Only a string of one letter with a case changes; anything else — a
    /// digit, `?`, `⎋`, `⌃Z`, `1-9`, `c|C`, `↑↓` — is drawn as written, in
    /// either spelling. A letter whose capital is not one character (`ß`) has
    /// no key cap of its own, and is drawn as written too.
    public func spelling(_ shortcut: String) -> String {
        guard self == .menu, shortcut.count == 1, let letter = shortcut.first, letter.isLetter else {
            return shortcut
        }
        if letter.isLowercase {
            return KeySymbols.keyCap(letter)
        }
        guard letter.isUppercase, letter.lowercased().count == 1 else { return shortcut }
        return "⇧" + shortcut
    }
}

// MARK: - Environment

/// `\.statusBarKeySpelling`'s key.
private struct StatusBarKeySpellingKey: EnvironmentKey {
    static let defaultValue = StatusBarKeySpelling.menu
}

extension EnvironmentValues {
    /// How the status bar draws an item's one-letter key — see
    /// ``StatusBarKeySpelling``. ``StatusBarKeySpelling/menu`` by default.
    public var statusBarKeySpelling: StatusBarKeySpelling {
        get { self[StatusBarKeySpellingKey.self] }
        set { self[StatusBarKeySpellingKey.self] = newValue }
    }
}

extension View {
    /// Sets how a status bar in this subtree draws an item's one-letter key:
    /// as a macOS menu draws it (`Q`, `⇧N`, the default) or as the item's
    /// string is typed (`q`, `N`).
    ///
    /// TUI-specific; see ``StatusBarKeySpelling``.
    ///
    /// - Parameter spelling: The spelling.
    /// - Returns: A view whose status bar draws its items' keys in `spelling`.
    public func statusBarKeySpelling(_ spelling: StatusBarKeySpelling) -> some View {
        environment(\.statusBarKeySpelling, spelling)
    }
}
