//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StatusBarKeySpellingTests.swift
//
//  The status bar draws an item's one-letter key as a macOS menu draws it, or
//  as typed (the owner's ruling B-KS-1, 2026-10-23).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation

@Suite("Status bar key spelling")
struct StatusBarKeySpellingTests {
    @Test("The menu spelling draws a letter as its key cap, and a capital with ⇧")
    func menuSpelling() {
        #expect(StatusBarKeySpelling.menu.spelling("q") == "Q")
        #expect(StatusBarKeySpelling.menu.spelling("N") == "⇧N")
        #expect(StatusBarKeySpelling.menu.spelling("é") == "É")
    }

    @Test("Anything but one letter with a case is drawn as written")
    func otherStringsUnchanged() {
        for shortcut in ["1", "?", "⎋", "⌃Z", "1-9", "c|C", "↑↓", "ß", "", "日"] {
            #expect(StatusBarKeySpelling.menu.spelling(shortcut) == shortcut, "\(shortcut)")
        }
    }

    @Test("As typed, every string is drawn as written")
    func asTyped() {
        for shortcut in ["q", "N", "1-9", "⌃Z"] {
            #expect(StatusBarKeySpelling.asTyped.spelling(shortcut) == shortcut)
        }
    }

    @Test("The menu spelling is the default")
    func defaultIsMenu() {
        #expect(EnvironmentValues().statusBarKeySpelling == .menu)
    }
}
