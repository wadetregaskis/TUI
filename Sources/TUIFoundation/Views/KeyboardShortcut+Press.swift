//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyboardShortcut+Press.swift
//
//  A shortcut as the key event pressing it sends: what a menu bar's item
//  presses for a command whose key something else binds.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Pressing a shortcut

extension KeyboardShortcut {
    /// The key event pressing this shortcut sends, its ⌘ resolved through
    /// `commandKey` — what a menu bar's item presses for a command whose key
    /// something else binds (``KeysAfterFrame``) — or `nil` where no key can
    /// press it (⌘ under ``CommandKeyBinding/unavailable``).
    ///
    /// A letter held with Shift is its capital, as a terminal sends it
    /// (``trigger(for:)`` reads Shift from the case).
    package func keyEvent(commandKey: CommandKeyBinding) -> KeyEvent? {
        guard let resolved = resolved(commandKey: commandKey) else { return nil }
        var key = Key(resolved.key)
        let modifiers = resolved.modifiers
        if modifiers.contains(.shift), case .character(let character) = key, character.isLetter {
            key = .character(Character(character.uppercased()))
        }
        return KeyEvent(
            key: key, ctrl: modifiers.contains(.control), alt: modifiers.contains(.option),
            shift: modifiers.contains(.shift))
    }
}

extension QuitShortcut {
    /// The quit key as a keyboard shortcut — the key the menu bar's Quit shows
    /// (TUICommands) — or `nil` for a key no shortcut can name.
    package var keyboardShortcut: KeyboardShortcut? {
        let equivalent: KeyEquivalent? =
            if case .character(let character) = key {
                KeyEquivalent(character)
            } else {
                KeyboardShortcut.equivalents[key]
            }
        return equivalent.map { KeyboardShortcut($0, modifiers: ctrl ? .control : []) }
    }
}
