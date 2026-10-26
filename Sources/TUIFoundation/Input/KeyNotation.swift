//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyNotation.swift
//
//  How keys are written on screen: the symbols macOS draws, or their names
//  spelled out for a terminal font that has no glyph for the symbols — the
//  user's `TUIKIT_KEY_SYMBOLS=0`, or the app's own `.keyNotation(_:)`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore

// MARK: - The notation

/// How TUI writes a key or a keyboard shortcut on screen.
///
/// TUI-specific. TUI names keys with the symbols a macOS menu draws —
/// `⌃⇧Z`, `⎋`, `↩`, `⇧⇥` (see ``KeyboardShortcut/displayString``). A
/// terminal draws them in its own font, and a font with no glyph for them
/// draws a box instead; for a user whose font lacks them, the keys can be
/// spelled out: `Ctrl-Shift-Z`, `Esc`, `Return`, `Shift-Tab`.
///
/// The user asks for the names with `TUIKIT_KEY_SYMBOLS=0` in the environment
/// the app runs in, and an app with `Scene.keyNotation(_:)`. The status bar
/// and a menu's shortcut column follow ``EnvironmentValues/keyNotation``; text
/// of the app's own that names a key follows it through ``spelling(_:)``.
public enum KeyNotation: Hashable, Sendable, CaseIterable {
    /// The symbols a macOS menu draws: the modifiers in the order ⌃ ⌥ ⇧ ⌘,
    /// then the key — `⌃⇧Z`, `⌥F`, `⇧⇥`, `⎋`, `↩`, `⌫`. The default.
    case symbols

    /// The keys' names: `Ctrl-Shift-Z`, `Alt-F`, `Shift-Tab`, `Esc`,
    /// `Return`, `Backspace`. The arrows stay arrows, and the function keys
    /// and the space bar are words in both notations.
    case spelledOut

    /// `text`, a key or keys written in ``symbols`` as TUI writes them, in
    /// this notation.
    ///
    /// Under ``symbols`` it is `text`. Under ``spelledOut`` each symbol becomes
    /// its name, and a modifier's name is joined to what follows it by a
    /// hyphen: `⌃⇧Z` is `Ctrl-Shift-Z`, `⎋` is `Esc`, `⌥↑` is `Alt-↑` — unless
    /// the text joins them itself, so `⇧-click` is `Shift-click` and `⌃+C` is
    /// `Ctrl+C`, while `⌃-` and `⌃+/⌃-`, whose keys are the minus and the
    /// plus, are `Ctrl--` and `Ctrl-+/Ctrl--`.
    /// Anything that is not a key symbol stays as it is, so a status bar
    /// item's `1-9` or `c|C` reads the same in both.
    ///
    /// ```swift
    /// @Environment(\.keyNotation) private var keyNotation
    ///
    /// Text("Save: " + keyNotation.spelling(saveShortcut.displayString ?? ""))
    /// ```
    public func spelling(_ text: String) -> String {
        switch self {
        case .symbols: text
        case .spelledOut: Self.spellingOut(text)
        }
    }

    /// `text` with every key symbol replaced by its name.
    private static func spellingOut(_ text: String) -> String {
        // Most of what reaches here names no key at all ("q", "1-9"): left
        // untouched, it is not rebuilt.
        guard text.contains(where: { names[$0] != nil }) else { return text }
        var result = ""
        var rest = text[...]
        while let character = rest.popFirst() {
            guard let name = names[character] else {
                result.append(character)
                continue
            }
            result += name
            // A modifier is joined to what it modifies; one on its own (a
            // status bar's lone ⇧) is just its name.
            if modifierSymbols.contains(character), let next = rest.first, !next.isWhitespace,
                !isJoiner(next, before: rest.dropFirst().first)
            {
                result += "-"
            }
        }
        return result
    }

    /// Whether `character`, just after a modifier symbol, is a joiner the text
    /// already has, rather than the key: a `-` or `+` with a key after it — a
    /// letter, a digit or a key symbol — as in `⇧-click`, `⌃+C` or `⌥-↑`.
    /// Those keep the text's own joiner — `Shift-click`, `Ctrl+C` — where a
    /// hyphen of ours would double it (`Shift--click`). A `-` or `+` followed
    /// by anything else, or by nothing, IS the key, and gets the hyphen any
    /// key does: `⌃-` is `Ctrl--`, Control-minus, and in `⌃+/⌃-` the `/`
    /// separates two chords, `Ctrl-+/Ctrl--`.
    private static func isJoiner(_ character: Character, before following: Character?) -> Bool {
        guard character == "-" || character == "+", let following else { return false }
        return following.isLetter || following.isNumber || names[following] != nil
            || arrows.contains(following)
    }

    /// The arrow keys' symbols, which stay symbols in both notations.
    private static let arrows: Set<Character> = ["←", "↑", "→", "↓"]

    /// Every symbol ``spelledOut`` names, with its name: the modifiers and the
    /// keys `KeySymbols` draws a symbol for. The arrows are not here, being
    /// drawn in every font a terminal uses; nor are the function keys and the
    /// space bar, which are words already.
    ///
    /// English terminal names, as a PC keyboard labels the keys, since a font
    /// without the macOS symbols is most often on a host that is not a Mac:
    /// Option is `Alt`, and the backspace key `Backspace`.
    static let names: [Character: String] = [
        "⌃": "Ctrl", "⌥": "Alt", "⇧": "Shift", "⌘": "Cmd",
        "⎋": "Esc", "↩": "Return", "⇥": "Tab", "⌫": "Backspace", "⌦": "Del",
        "↖": "Home", "↘": "End", "⇞": "PgUp", "⇟": "PgDn",
    ]

    /// The four modifier symbols, whose names a hyphen joins to the key.
    static let modifierSymbols: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
}

// MARK: - The environment value

private struct KeyNotationKey: EnvironmentKey {
    // `.symbols`, and not read from the process environment: a key's default
    // must not depend on where a test runs. The render loop writes the
    // user's answer at the root.
    static let defaultValue = KeyNotation.symbols
}

extension EnvironmentValues {
    /// How the status bar and a menu's shortcut column write keys — see
    /// ``KeyNotation``.
    ///
    /// ``KeyNotation/symbols`` unless the user set `TUIKIT_KEY_SYMBOLS=0` in
    /// the environment the app runs in (``TerminalClient/keyNotationRequested``)
    /// or the app asked for the names with the TUI-specific
    /// `Scene.keyNotation(_:)`. Read-only, so that a view cannot hand symbols
    /// back to a user who asked for names; read it to write a key in text of
    /// the app's own (``KeyNotation/spelling(_:)``).
    public package(set) var keyNotation: KeyNotation {
        get { self[KeyNotationKey.self] }
        set { self[KeyNotationKey.self] = newValue }
    }
}

// MARK: - The user's setting

extension TerminalClient {
    /// How the user asked for keys to be written: ``KeyNotation/spelledOut``
    /// with `TUIKIT_KEY_SYMBOLS=0` in the environment the app was started in,
    /// for a terminal font with no glyph for the symbols, and
    /// ``KeyNotation/symbols`` otherwise. Read once, at first use.
    ///
    /// The app runner hands it to its render loop, which writes it into the
    /// root of every frame's environment, as
    /// ``EnvironmentValues/keyNotation``, before the scene's own
    /// `.keyNotation(_:)`. Only the app runner reads it: a headless app's
    /// loop, and every test's, draws the symbols.
    public static let keyNotationRequested: KeyNotation =
        keyNotationRequested(environment: ProcessInfo.processInfo.environment)

    /// The rule behind ``keyNotationRequested``, posed on its input so it can
    /// be asked without changing what a whole process reads.
    static func keyNotationRequested(environment: [String: String]) -> KeyNotation {
        environment["TUIKIT_KEY_SYMBOLS"] == "0" ? .spelledOut : .symbols
    }
}
