//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KeySymbolsTests.swift
//
//  Every key TUIkit names, named as a macOS menu names it: the modifiers in
//  the order ⌃ ⌥ ⇧ ⌘, then the key's symbol.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitStrings
@testable import TUIkitTestSupport

/// The expectations here are AppKit's, not a re-statement of the formatter's
/// tables: `NSKeyboardShortcut`'s `localizedDisplayName`, which draws the
/// shortcuts in macOS's menus and in System Settings, was asked for every key
/// below on macOS 15 (2026-10-05), with each modifier set, and these are its
/// answers. Where TUIkit's own vocabulary differs from AppKit's scalars (its
/// `.delete` is U+007F, which AppKit draws ⌦, where SwiftUI's is U+0008,
/// drawn ⌫), the test follows the NAME: `.delete` is the delete-backwards key.
@Suite("Key symbols")
struct KeySymbolsTests {

    // MARK: - The order and the case

    @Test("The modifiers come first, in macOS's order ⌃ ⌥ ⇧ ⌘, however the set was written")
    func modifierOrder() {
        let all: EventModifiers = [.command, .shift, .option, .control]
        #expect(KeyboardShortcut("s", modifiers: all).displayString == "⌃⌥⇧⌘S")
        #expect(KeyboardShortcut("s", modifiers: [.shift, .command]).displayString == "⇧⌘S")
        #expect(KeyboardShortcut("s", modifiers: [.option, .control]).displayString == "⌃⌥S")
        #expect(all.displayString == "⌃⌥⇧⌘")
        #expect(EventModifiers().displayString.isEmpty)
    }

    @Test("Caps Lock and the numeric pad are not drawn, as macOS draws neither")
    func statesAreNotDrawn() {
        #expect(EventModifiers([.capsLock, .numericPad]).displayString.isEmpty)
        #expect(KeyboardShortcut("s", modifiers: [.control, .capsLock]).displayString == "⌃S")
        #expect(KeyboardShortcut("1", modifiers: .numericPad).displayString == "1")
    }

    @Test("A letter is drawn in upper case, so Shift is a ⇧ of its own")
    func lettersAreCapitals() {
        #expect(KeyboardShortcut("s", modifiers: .command).displayString == "⌘S")
        #expect(KeyboardShortcut("s", modifiers: [.shift, .command]).displayString == "⇧⌘S")
        #expect(KeyboardShortcut("S", modifiers: .command).displayString == "⇧⌘S")
        #expect(KeyboardShortcut("é", modifiers: .control).displayString == "⌃É")
        // A capital that is two letters would not be one key's cap.
        #expect(KeyboardShortcut("ß", modifiers: .control).displayString == "⌃ß")
    }

    @Test("Any other printable key is drawn as typed: ⌘? is the shortcut on \"?\", with no ⇧")
    func punctuationAsTyped() {
        #expect(KeyboardShortcut("?", modifiers: .command).displayString == "⌘?")
        #expect(KeyboardShortcut("/", modifiers: .control).displayString == "⌃/")
        #expect(KeyboardShortcut("_", modifiers: .option).displayString == "⌥_")
        #expect(KeyboardShortcut("1", modifiers: []).displayString == "1")
        // A Shift asked for on one is drawn, as AppKit draws it.
        #expect(KeyboardShortcut("/", modifiers: [.shift, .command]).displayString == "⇧⌘/")
    }

    // MARK: - The keys that type nothing

    @Test(
        "A key that types nothing has macOS's symbol",
        arguments: [
            (KeyEquivalent.escape, "⎋"), (.return, "↩"), (.tab, "⇥"),
            (.delete, "⌫"), (.deleteForward, "⌦"),
            (.upArrow, "↑"), (.downArrow, "↓"), (.leftArrow, "←"), (.rightArrow, "→"),
            (.home, "↖"), (.end, "↘"), (.pageUp, "⇞"), (.pageDown, "⇟"),
        ])
    func namedKeys(key: KeyEquivalent, symbol: String) {
        // Held with a modifier, so the semantic roles (bare Return and Escape)
        // do not take the two of them.
        #expect(KeyboardShortcut(key, modifiers: .option).displayString == "⌥" + symbol)
        #expect(KeySymbols.key(Key(key)) == symbol)
    }

    @Test("Shift-Tab is ⇧⇥, as macOS draws it, not ⇤")
    func backtab() {
        #expect(KeyboardShortcut(.tab, modifiers: .shift).displayString == "⇧⇥")
        #expect(KeyEvent(key: .tab, shift: true).displayString == "⇧⇥")
    }

    @Test("SwiftUI's own Delete scalar, U+0008, is the delete-backwards key too")
    func swiftUIDeleteScalar() {
        #expect(KeyboardShortcut(KeyEquivalent("\u{8}"), modifiers: .option).displayString == "⌥⌫")
    }

    @Test("The space bar is a word, in the app's language, as macOS names it")
    func spaceBar() {
        let space = LocalizationService.shared.string(for: "key.space")
        #expect(KeyboardShortcut(.space, modifiers: .control).displayString == "⌃" + space)
        #expect(KeyEvent(key: .space).displayString == space)
    }

    /// For a caller that keeps a name (the status bar's undo hints): only
    /// the space bar's name changes with the language.
    @Test("Only a name on the space bar is localized")
    func nameIsLocalized() {
        #expect(KeySymbols.nameIsLocalized(KeyboardShortcut(.space, modifiers: .option)))
        #expect(KeySymbols.nameIsLocalized(KeyboardShortcut(" ", modifiers: [])))
        #expect(KeySymbols.nameIsLocalized(KeyboardShortcut(.space, modifiers: [.control, .shift])))
        #expect(!KeySymbols.nameIsLocalized(KeyboardShortcut("z", modifiers: .control)))
        #expect(!KeySymbols.nameIsLocalized(KeyboardShortcut(.home, modifiers: [])))
        #expect(!KeySymbols.nameIsLocalized(KeyboardShortcut(.tab, modifiers: .shift)))
        // The semantic roles have no name.
        #expect(!KeySymbols.nameIsLocalized(.defaultAction))
        #expect(!KeySymbols.nameIsLocalized(.cancelAction))
    }

    @Test("macOS's words for the space bar, in each of TUIkit's languages")
    func spaceBarTranslations() {
        // AppKit's own, read under each language: the Japanese menu keeps the
        // English word.
        let expected: [LocalizationService.Language: String] = [
            .english: "Space", .german: "Leertaste", .french: "Espace", .italian: "Barra spaziatrice",
            .spanish: "Espacio", .simplifiedChinese: "空格键", .japanese: "Space",
        ]
        for language in LocalizationService.Language.allCases {
            #expect(
                LocalizationService.shared.string(for: "key.space", in: language) == expected[language],
                "\(language)")
        }
    }

    @Test("The function keys are words: F1 … F20")
    func functionKeys() {
        #expect(KeySymbols.key(.f1) == "F1")
        #expect(KeySymbols.key(.f12) == "F12")
        #expect(KeySymbols.key(.f20) == "F20")
        #expect(KeyEvent(key: .f5, shift: true).displayString == "⇧F5")
        // The PC keyboard's Menu key, which a Mac's has no symbol for.
        #expect(KeySymbols.key(.menu) == "Menu")
    }

    // MARK: - One table

    @Test("Naming a shortcut's key reads the table an event is matched through, backwards")
    func equivalentsRoundTrip() {
        for (key, equivalent) in KeyboardShortcut.equivalents {
            #expect(Key(equivalent) == key, "\(key)")
        }
        #expect(Key(KeyEquivalent("a")) == .character("a"))
    }

    // MARK: - A key event

    @Test("A key event is drawn as a shortcut on its key would be")
    func keyEvents() {
        #expect(KeyEvent(key: .character("a"), ctrl: true).displayString == "⌃A")
        #expect(KeyEvent(key: .character("a")).displayString == "A")
        // Shift is the character's case, whatever the terminal reported.
        #expect(KeyEvent(character: "A").displayString == "⇧A")
        #expect(KeyEvent(key: .character("A")).displayString == "⇧A")
        #expect(KeyEvent(key: .character("?"), shift: true).displayString == "?")
        #expect(KeyEvent(key: .up, alt: true).displayString == "⌥↑")
        #expect(KeyEvent(key: .left, ctrl: true, alt: true, shift: true).displayString == "⌃⌥⇧←")
        #expect(KeyEvent(key: .escape).displayString == "⎋")
        #expect(KeyEvent(key: .enter).displayString == "↩")
        #expect(KeyEvent(key: .paste("text")).displayString == nil)
    }

    // MARK: - Width

    /// Every symbol is claimed at one cell, the East Asian Ambiguous ones (⇧,
    /// the arrows, ↖ ↘) as the box drawing is: a menu's shortcut column and the
    /// status bar line up by these claims.
    @Test("Every symbol claims one cell")
    func symbolsAreOneCell() {
        let keys: [Key] = [
            .escape, .enter, .tab, .backspace, .delete,
            .up, .down, .left, .right, .home, .end, .pageUp, .pageDown,
        ]
        let symbols = keys.map(KeySymbols.key) + ["⌃", "⌥", "⇧", "⌘"]
        for symbol in symbols {
            #expect(symbol.count == 1, "\(symbol)")
            #expect(symbol.first?.terminalWidth == 1, "\(symbol) claims \(symbol.first?.terminalWidth ?? -1)")
        }
    }
}
