//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ShortcutTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Shortcut Constants Tests

@MainActor
@Suite("Shortcut Constants Tests")
struct ShortcutTests {

    @Test("Combine helper joins shortcuts")
    func combineHelper() {
        let result = Shortcut.combine(Shortcut.control, "C")
        #expect(result == "⌃C")

        let withSeparator = Shortcut.combine("A", "B", "C", separator: "-")
        #expect(withSeparator == "A-B-C")
    }

    @Test("The Control helper names the chord as a shortcut is named: ⌃ and the capital")
    func ctrlHelper() {
        #expect(Shortcut.ctrl("c") == "⌃C")
        #expect(Shortcut.ctrl("x") == "⌃X")
        // An upper-case key is its Shift chord, as in a KeyboardShortcut.
        #expect(Shortcut.ctrl("Q") == "⌃⇧Q")
        #expect(Shortcut.ctrl("q") == KeyboardShortcut("q", modifiers: .control).displayString)
    }

    /// The constants are the formatter's, so a status bar names a key as a
    /// menu does — the symbols macOS draws, which replaced ↵ for Return, ⤒ ⤓
    /// for Home and End, ⇤ for Shift-Tab and ␣ for the space bar.
    @Test("A key's constant is the symbol a macOS menu draws for it")
    func keyConstants() {
        #expect(Shortcut.escape == "⎋")
        #expect(Shortcut.enter == "↩")
        #expect(Shortcut.tab == "⇥")
        #expect(Shortcut.shiftTab == "⇧⇥")
        #expect(Shortcut.backspace == "⌫")
        #expect(Shortcut.delete == "⌦")
        #expect(Shortcut.home == "↖")
        #expect(Shortcut.end == "↘")
        #expect(Shortcut.pageUp == "⇞")
        #expect(Shortcut.pageDown == "⇟")
        #expect(Shortcut.arrowsAll == "↑↓←→")
        #expect(Shortcut.control + Shortcut.option + Shortcut.shift + Shortcut.command == "⌃⌥⇧⌘")
        #expect(Shortcut.f12 == "F12")
        #expect("⌃" + Shortcut.space == KeyboardShortcut(.space, modifiers: .control).displayString)
    }

    @Test("A status bar item on a key's constant is bound to that key")
    func constantsBindTheirKeys() {
        let pairs: [(String, Key)] = [
            (Shortcut.escape, .escape), (Shortcut.enter, .enter), (Shortcut.tab, .tab),
            (Shortcut.backspace, .backspace), (Shortcut.delete, .delete), (Shortcut.space, .space),
            (Shortcut.home, .home), (Shortcut.end, .end), (Shortcut.pageUp, .pageUp),
            (Shortcut.pageDown, .pageDown), (Shortcut.f1, .f1),
        ]
        for (shortcut, key) in pairs {
            #expect(StatusBarItem(shortcut: shortcut, label: "x").triggerKey == key, "\(shortcut)")
        }
    }

    @Test("Range helper creates range string")
    func rangeHelper() {
        let result = Shortcut.range("1", "9")
        #expect(result == "1-9")

        let result2 = Shortcut.range("a", "z")
        #expect(result2 == "a-z")
    }
}
