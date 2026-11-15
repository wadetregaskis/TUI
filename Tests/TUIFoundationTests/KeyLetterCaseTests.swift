//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyLetterCaseTests.swift
//
//  A letter pressed alone is drawn as a capital by default, as macOS draws it,
//  or as typed; a key that needs Shift is drawn with `⇧` in both (the owner's
//  APPFB-4, 2026-11-14; B-KS-1 before it).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation

@Suite("Key letter case")
struct KeyLetterCaseTests {
    @Test("A key's name keeps its capital by default; as typed, only a letter pressed alone is lower case")
    func names() {
        for name in ["K", "⇧K", "⌃K", "⌃⇧Z", "⎋", "1", "F5", "?", "É"] {
            #expect(KeyLetterCase.capital.spelling(name) == name, "\(name)")
        }
        #expect(KeyLetterCase.asTyped.spelling("K") == "k")
        #expect(KeyLetterCase.asTyped.spelling("É") == "é")
        for name in ["⇧K", "⌃K", "⌃⇧Z", "⎋", "1", "F5", "?", "k"] {
            #expect(KeyLetterCase.asTyped.spelling(name) == name, "\(name)")
        }
    }

    @Test("A status-bar item's letter is drawn as its key: a capital, or as typed, and Shift always ⇧")
    func statusBarItems() {
        #expect(KeyLetterCase.capital.statusBarItemKey("q") == "Q")
        #expect(KeyLetterCase.capital.statusBarItemKey("N") == "⇧N")
        #expect(KeyLetterCase.capital.statusBarItemKey("é") == "É")
        #expect(KeyLetterCase.asTyped.statusBarItemKey("q") == "q")
        #expect(KeyLetterCase.asTyped.statusBarItemKey("N") == "⇧N", "never a bare capital")
        #expect(KeyLetterCase.asTyped.statusBarItemKey("é") == "é")
    }

    @Test("Anything but one letter with a case is drawn as written, in either case")
    func otherStringsUnchanged() {
        for letterCase in KeyLetterCase.allCases {
            for shortcut in ["1", "?", "⎋", "⌃Z", "1-9", "c|C", "↑↓", "ß", "", "日"] {
                #expect(letterCase.statusBarItemKey(shortcut) == shortcut, "\(letterCase) \(shortcut)")
            }
        }
    }

    @Test("Capitals are the default")
    func defaultIsCapital() {
        #expect(EnvironmentValues().keyLetterCase == .capital)
    }
}
