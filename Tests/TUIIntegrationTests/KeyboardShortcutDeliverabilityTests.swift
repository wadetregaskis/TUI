//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyboardShortcutDeliverabilityTests.swift
//
//  `KeyboardShortcut.isDeliverableInTerminal` for the chords a legacy encoding
//  has no byte of its own for: Control with Shift, a digit or punctuation;
//  Return, Tab, Escape, Backspace and space modified; Shift on a non-letter.
//  The C0 collisions (Ctrl-H, Ctrl-4) are `KeyboardShortcutTests`'.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation

@Suite("Which shortcuts every terminal can send")
struct KeyboardShortcutDeliverabilityTests {
    /// A legacy encoding's Control chords are its C0 bytes, which have no case
    /// and exist only for the letters and a few symbols; its Return, Tab,
    /// Escape, Backspace and space are C0 bytes themselves; and Shift on a
    /// character is its case. So ⌘⇧S under `.commandKey(.control)` arrives as
    /// ⌃S, and ⌘1 as a plain 1: the shortcut answered `true` for both.
    @Test("Control with Shift, a digit or punctuation, and the C0 keys modified, are undeliverable")
    func chordsWithNoByteOfTheirOwn() {
        let undeliverable: [KeyboardShortcut?] = [
            KeyboardShortcut("s", modifiers: [.command, .shift]).resolved(commandKey: .control),
            KeyboardShortcut("S", modifiers: .control),
            KeyboardShortcut("1").resolved(commandKey: .control),
            KeyboardShortcut(",", modifiers: .control),
            KeyboardShortcut("/", modifiers: .control),
            KeyboardShortcut("_", modifiers: .control),
            KeyboardShortcut("]", modifiers: .control),
            KeyboardShortcut(.return, modifiers: .control),
            KeyboardShortcut(.return, modifiers: .shift),
            KeyboardShortcut(.tab, modifiers: .control),
            KeyboardShortcut(.space, modifiers: .control),
            KeyboardShortcut(.delete, modifiers: .control),
            KeyboardShortcut("1", modifiers: .shift),
        ]
        for shortcut in undeliverable {
            #expect(shortcut?.isDeliverableInTerminal == false, "\(String(describing: shortcut))")
        }
    }

    @Test("Shift-Tab, Option chords, a letter's capital and the escape-sequence keys stay deliverable")
    func chordsATerminalSends() {
        let deliverable: [KeyboardShortcut] = [
            KeyboardShortcut("s", modifiers: [.option, .shift]),
            KeyboardShortcut("S", modifiers: []),
            KeyboardShortcut(.tab, modifiers: .shift),
            KeyboardShortcut(.return, modifiers: .option),
            KeyboardShortcut(.upArrow, modifiers: [.control, .shift]),
            KeyboardShortcut(KeyEquivalent("\u{F705}"), modifiers: .control),
            KeyboardShortcut("1", modifiers: .option),
            KeyboardShortcut("!", modifiers: []),
            KeyboardShortcut("j", modifiers: [.control, .option]),
            KeyboardShortcut("-", modifiers: .control),
        ]
        for shortcut in deliverable {
            #expect(shortcut.isDeliverableInTerminal == true, "\(shortcut)")
        }
    }
}
