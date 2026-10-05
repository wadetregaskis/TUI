//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KeySymbols.swift
//
//  The one place a key or a chord becomes text: the symbols a macOS menu
//  draws, in the order it draws them.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Key symbols

/// The one place a key, a set of modifiers or a chord becomes text.
///
/// Everything TUIkit names a key with goes through here — a menu row's
/// shortcut column (``KeyboardShortcut/displayString``), the status bar's
/// ``Shortcut`` constants and its undo and redo hints, ``KeyEvent/displayString``
/// — so a key is spelled one way wherever it appears.
///
/// The spelling is macOS's, as its menus draw a key equivalent. Measured on
/// macOS 15 with AppKit's `NSKeyboardShortcut`, which draws the shortcuts in
/// menus and in System Settings, over every key below:
///
/// - **The modifiers come first, in one order: ⌃ ⌥ ⇧ ⌘** — Control, Option,
///   Shift, Command — however the set was written. Caps Lock and the numeric
///   pad are not drawn: macOS draws neither, and a shortcut ignores both.
/// - **Then the key.** A letter is drawn in upper case, `⌘S` for ⌘s, so
///   Shift has a symbol of its own: `⇧⌘S`. Any other printable key is drawn as
///   it is typed, so `⌘?` is the shortcut on "?", with no ⇧ — the character
///   already says it.
/// - **A key that types nothing has a symbol:** ⎋ Escape, ↩ Return, ⇥ Tab,
///   ⌫ Delete (backspace), ⌦ Forward Delete, ← → ↑ ↓, ↖ Home, ↘ End,
///   ⇞ Page Up and ⇟ Page Down. Shift-Tab is `⇧⇥`, as macOS draws it, not
///   ⇤. The function keys are words, `F1`…`F20`, and so is the space bar,
///   in the app's language: `Space`, `Leertaste`, `Espace`, `Barra
///   spaziatrice`, `Espacio`, `空格键` — and `Space` in Japanese, as macOS
///   has it.
///
/// Every symbol claims one cell by TUIkit's width tables, the East Asian
/// Ambiguous ones (⇧, the arrows, ↖ and ↘) included, as the box drawing does.
/// Which hosts have been measured to agree, and what a host does with "wide"
/// ambiguous characters, is in `Documentation/Terminal-compatibility.md`,
/// "Key symbols".
enum KeySymbols {
    /// The modifiers in `modifiers` that a shortcut is drawn with, in macOS's
    /// order: ⌃ ⌥ ⇧ ⌘.
    static func modifiers(_ modifiers: EventModifiers) -> String {
        // Appended rather than joined from a table: four comparisons and at
        // most twelve bytes, which a small string holds without allocating.
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result
    }

    /// `key` held with `modifiers`: the modifiers, then the key.
    ///
    /// Shift is drawn as `modifiers` says. Fold a printable key's case into it
    /// first (`KeyEquivalent.foldingCase`): an upper-case letter here is drawn
    /// as that letter with no ⇧.
    static func chord(_ key: Key, _ modifiers: EventModifiers) -> String {
        self.modifiers(modifiers) + self.key(key)
    }

    /// The symbol or name for `key` alone.
    static func key(_ key: Key) -> String {
        switch key {
        case .character(let character): keyCap(character)
        case .space: spaceBar
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        case .home: "↖"
        case .end: "↘"
        case .pageUp: "⇞"
        case .pageDown: "⇟"
        default: editingOrFunctionKey(key)
        }
    }

    /// Escape, Return, Tab, the two deletes and the function keys: the rest of
    /// ``key(_:)``, apart so neither switch outgrows the other.
    private static func editingOrFunctionKey(_ key: Key) -> String {
        switch key {
        case .escape: "⎋"
        case .enter: "↩"
        case .tab: "⇥"
        case .backspace: "⌫"
        case .delete: "⌦"
        default:
            // F1…F20 — and pasted text, which is not a key and has no name.
            functionKeys.firstIndex(of: key).map { "F\($0 + 1)" } ?? ""
        }
    }

    /// The function keys in order, F1 first.
    private static let functionKeys: [Key] = [
        .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
        .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20,
    ]

    /// A printable key's cap: a letter in upper case, as macOS draws ⌘S for
    /// ⌘s, and anything else as it is typed — `?`, `/`, `1`, `_`.
    ///
    /// A letter whose capital is two letters (`ß`, `SS`) keeps its own form:
    /// a key is one character.
    static func keyCap(_ character: Character) -> String {
        guard character.isLowercase else { return String(character) }
        let capital = character.uppercased()
        return capital.count == 1 ? capital : String(character)
    }

    /// The space bar's name in the app's language, as macOS names it in a
    /// menu.
    static var spaceBar: String {
        LocalizationService.shared.string(for: LocalizationKey.KeyName.space.rawValue)
    }

    /// `shortcut` as the status bar names a key the framework puts in it (the
    /// undo and redo hints), or `nil` for the semantic roles.
    ///
    /// As a menu draws it (``KeyboardShortcut/displayString``), with one
    /// exception: a letter held with nothing but Shift is written as the bar's
    /// own items are, in the case the key types — `u` for u, `U` for Shift-U.
    /// In the bar an upper-case letter MEANS Shift: an app's `"N"` item is
    /// Shift-N (`StatusBarItem.matches(_:)`), and the bar tells its items
    /// apart by that string. Drawn as a menu draws it, a redo on a bare u read
    /// `U` beside the app's Shift-letter items, and hid behind an app's `"U"`
    /// item (Shift-U, another key) while an app's `"u"` (the same key) left it
    /// showing. A chord with ⌃ ⌥ or ⌘ in it is the menu's (`⌃Z`, `⌃⇧Z`): its
    /// Shift is a ⇧ either way, and no item of the bar's own is spelled so.
    static func statusBarName(of shortcut: KeyboardShortcut) -> String? {
        guard case .key(let equivalent, let modifiers) = shortcut.trigger else { return nil }
        // `trigger` has folded a capital into Shift, so the letter is its
        // lower-case form here and `modifiers` says whether Shift is held.
        let letter = equivalent.character
        if letter.isLowercase, modifiers.subtracting([.capsLock, .numericPad]).isSubset(of: .shift) {
            guard modifiers.contains(.shift) else { return String(letter) }
            // A letter whose capital is not one character (ß) has no case
            // to carry its Shift, and keeps the menu's ⇧.
            let capital = keyCap(letter)
            if capital != String(letter) { return capital }
        }
        return shortcut.displayString
    }
}

// MARK: - A key equivalent's key

extension Key {
    /// The key `equivalent` stands for: the function-key scalars and control
    /// characters SwiftUI names its non-printing keys with as the keys they
    /// name (``KeyEquivalent/upArrow`` is ``up``, ``KeyEquivalent/delete`` is
    /// ``backspace``), and anything else as the character it is.
    ///
    /// The inverse of the table a key event is matched through
    /// (`KeyboardShortcut.equivalents`), read backwards rather than written out
    /// a second time. SwiftUI's own Delete, U+0008, is ``backspace`` too, as
    /// AppKit draws it ⌫.
    init(_ equivalent: KeyEquivalent) {
        let character = equivalent.character
        // A printable ASCII key — almost every shortcut — is itself; only
        // what is left is looked up.
        if let ascii = character.asciiValue, (0x21...0x7E).contains(ascii) {
            self = .character(character)
        } else if character == "\u{8}" {
            self = .backspace
        } else {
            self = Self.equivalentKeys[equivalent] ?? .character(character)
        }
    }

    /// `KeyboardShortcut.equivalents`, read the other way.
    private static let equivalentKeys: [KeyEquivalent: Key] = Dictionary(
        uniqueKeysWithValues: KeyboardShortcut.equivalents.map { ($0.value, $0.key) })
}

// MARK: - What each type shows

extension EventModifiers {
    /// The modifiers a shortcut is drawn with, as macOS menus draw them, in
    /// their order: ⌃ ⌥ ⇧ ⌘ (Control, Option, Shift, Command). Caps Lock and
    /// the numeric pad are not drawn.
    ///
    /// TUI-specific: SwiftUI has no printable form of a modifier set.
    public var displayString: String {
        KeySymbols.modifiers(self)
    }
}

extension KeyEvent {
    /// The key and the modifiers held with it, as ``KeyboardShortcut`` draws a
    /// shortcut: `⌃⇧Z`, `⌥F`, `⇧⇥`, `⎋`, `F5`, and `A` for the key "a" — or
    /// `nil` for pasted text, which is not a key.
    ///
    /// A typed character's Shift is its case, as a shortcut reads it: "A" is
    /// `⇧A` whether or not the terminal reported Shift, and "?" is `?` even
    /// where it did.
    ///
    /// TUI-specific: for a key log or a hint drawn from the key itself.
    public var displayString: String? {
        if case .paste = key { return nil }
        var modifiers = EventModifiers(self).chordModifiers
        guard case .character(let character) = key else {
            return KeySymbols.chord(key, modifiers)
        }
        let (folded, shifted) = KeyEquivalent(character).foldingCase
        modifiers.remove(.shift)
        if shifted { modifiers.insert(.shift) }
        return KeySymbols.chord(.character(folded.character), modifiers)
    }
}
