//  🖥️ TUI — A Terminal UI framework for Swift
//  Shortcut.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Shortcut Symbols

/// The names of keys, and a few other symbols, for a status bar item's
/// `shortcut`.
///
/// Use these constants instead of typing the symbols. A key's constant is the
/// symbol a macOS menu draws for it, from the same formatter as every other key
/// TUI names (``KeyboardShortcut/displayString``), so a status bar and a
/// menu name a key the same way: ⎋ Escape, ↩ Return, ⇥ Tab, ⌃ Control, and so
/// on.
///
/// # Example
///
/// ```swift
/// StatusBarItem(shortcut: Shortcut.escape, label: "close") { dismiss() }
/// StatusBarItem(shortcut: Shortcut.arrowsUpDown, label: "nav")
/// StatusBarItem(shortcut: Shortcut.enter, label: "select", key: .enter)
/// ```
public enum Shortcut {
    // MARK: - Special Keys

    /// Escape: ⎋
    public static let escape = KeySymbols.key(.escape)

    /// Return: ↩, as macOS draws it.
    public static let enter = KeySymbols.key(.enter)

    /// Tab: ⇥
    public static let tab = KeySymbols.key(.tab)

    /// Shift-Tab: ⇧⇥, as macOS draws it.
    public static let shiftTab = KeySymbols.chord(.tab, .shift)

    /// Delete, the backspace key: ⌫
    public static let backspace = KeySymbols.key(.backspace)

    /// Forward delete: ⌦
    public static let delete = KeySymbols.key(.delete)

    /// The space bar, by name in the app's language, as macOS names it in a
    /// menu: `Space` in English.
    public static var space: String { KeySymbols.key(.space) }

    // MARK: - Arrow Keys (Single)

    /// Up arrow: ↑
    public static let arrowUp = KeySymbols.key(.up)

    /// Down arrow: ↓
    public static let arrowDown = KeySymbols.key(.down)

    /// Left arrow: ←
    public static let arrowLeft = KeySymbols.key(.left)

    /// Right arrow: →
    public static let arrowRight = KeySymbols.key(.right)

    // MARK: - Arrow Key Combinations

    /// Up and down arrows: ↑↓
    public static let arrowsUpDown = arrowUp + arrowDown

    /// Left and right arrows: ←→
    public static let arrowsLeftRight = arrowLeft + arrowRight

    /// All four arrows: ↑↓←→
    public static let arrowsAll = arrowsUpDown + arrowsLeftRight

    /// Vertical arrows (alternative): ⇅
    public static let arrowsVertical = "⇅"

    /// Horizontal arrows (alternative): ⇆
    public static let arrowsHorizontal = "⇆"

    // MARK: - Modifier Keys

    /// Command: ⌘
    public static let command = KeySymbols.modifiers(.command)

    /// Option (Alt): ⌥
    public static let option = KeySymbols.modifiers(.option)

    /// Control: ⌃
    public static let control = KeySymbols.modifiers(.control)

    /// Shift: ⇧
    public static let shift = KeySymbols.modifiers(.shift)

    /// Caps Lock: ⇪
    public static let capsLock = "⇪"

    // MARK: - Function Keys

    /// Function key prefix: Fn
    public static let fn = "Fn"

    /// Function key F1
    public static let f1 = KeySymbols.key(.f1)

    /// Function key F2
    public static let f2 = KeySymbols.key(.f2)

    /// Function key F3
    public static let f3 = KeySymbols.key(.f3)

    /// Function key F4
    public static let f4 = KeySymbols.key(.f4)

    /// Function key F5
    public static let f5 = KeySymbols.key(.f5)

    /// Function key F6
    public static let f6 = KeySymbols.key(.f6)

    /// Function key F7
    public static let f7 = KeySymbols.key(.f7)

    /// Function key F8
    public static let f8 = KeySymbols.key(.f8)

    /// Function key F9
    public static let f9 = KeySymbols.key(.f9)

    /// Function key F10
    public static let f10 = KeySymbols.key(.f10)

    /// Function key F11
    public static let f11 = KeySymbols.key(.f11)

    /// Function key F12
    public static let f12 = KeySymbols.key(.f12)

    // MARK: - Navigation

    /// Home: ↖, as macOS draws it.
    public static let home = KeySymbols.key(.home)

    /// End: ↘, as macOS draws it.
    public static let end = KeySymbols.key(.end)

    /// Page Up: ⇞
    public static let pageUp = KeySymbols.key(.pageUp)

    /// Page Down: ⇟
    public static let pageDown = KeySymbols.key(.pageDown)

    // MARK: - Actions

    /// Plus/Add symbol: +
    public static let plus = "+"

    /// Minus/Remove symbol: −
    public static let minus = "−"

    /// Checkmark/Confirm: ✓
    public static let checkmark = "✓"

    /// Cross/Cancel: ✗
    public static let cross = "✗"

    /// Search/Find: 🔍 (or use "?" for simpler display)
    public static let search = "?"

    /// Help symbol: ?
    public static let help = "?"

    /// Save symbol: 💾 (or use "S" for simpler display)
    public static let save = "S"

    // MARK: - Common Shortcuts

    /// Quit shortcut: q
    public static let quit = "q"

    /// Yes shortcut: y
    public static let yes = "y"

    /// No shortcut: n
    public static let no = "n"

    /// Cancel shortcut: c
    public static let cancel = "c"

    /// OK shortcut: o
    public static let ok = "o"

    // MARK: - Brackets and Selection

    /// Selection indicator: ▸
    public static let selectionRight = "▸"

    /// Selection indicator left: ◂
    public static let selectionLeft = "◂"

    /// Bullet point: •
    public static let bullet = "•"

    /// Square selection: ▪
    public static let squareBullet = "▪"

    // MARK: - Combining Helpers

}

// MARK: - Public API

extension Shortcut {
    /// Combines multiple shortcuts with a separator.
    ///
    /// - Parameters:
    ///   - shortcuts: The shortcuts to combine.
    ///   - separator: The separator (default: empty string).
    /// - Returns: The combined shortcut string.
    ///
    /// # Example
    ///
    /// ```swift
    /// Shortcut.combine(Shortcut.arrowUp, Shortcut.arrowDown)  // "↑↓"
    /// Shortcut.combine("1", "9", separator: "-")               // "1-9"
    /// ```
    public static func combine(_ shortcuts: String..., separator: String = "") -> String {
        shortcuts.joined(separator: separator)
    }

    /// Control held with `key`, named as every other shortcut is: `⌃Q` for
    /// `"q"`. An upper-case `key` is its Shift chord, `⌃⇧Q`, as it is in a
    /// ``KeyboardShortcut``.
    ///
    /// - Parameter key: The key character.
    /// - Returns: The chord's name (e.g., "⌃C").
    public static func ctrl(_ key: Character) -> String {
        let (folded, shifted) = KeyEquivalent(key).foldingCase
        return KeySymbols.chord(.character(folded.character), shifted ? [.control, .shift] : .control)
    }

    /// Creates a range shortcut display (e.g., "1-9").
    ///
    /// - Parameters:
    ///   - start: The start of the range.
    ///   - end: The end of the range.
    /// - Returns: The formatted range (e.g., "1-9").
    public static func range(_ start: String, _ end: String) -> String {
        "\(start)-\(end)"
    }
}
