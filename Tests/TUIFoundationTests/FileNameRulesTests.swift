//  🖥️ TUI — A Terminal UI framework for Swift
//  FileNameRulesTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation

@Suite("File name rules")
struct FileNameRulesTests {
    @Test("Everywhere: empty, a dot or two, and a slash are no file's name")
    func everywhere() {
        for onWindows in [false, true] {
            for name in ["", ".", "..", "a/b", "/"] {
                #expect(FileNameRules.refuses(name, onWindows: onWindows), "\(name)")
            }
            for name in ["notes", "notes.txt", ".hidden", "a b", "Ünïcödé"] {
                #expect(!FileNameRules.refuses(name, onWindows: onWindows), "\(name)")
            }
        }
    }

    @Test("On Windows: its forbidden characters, a trailing dot or space, and a device's name")
    func windows() {
        for name in [
            "notes:old", #"a\b"#, "a<b", "a>b", #"a"b"#, "a|b", "a?b", "a*b", "tab\there",
            "notes.", "notes ", "CON", "con", "nul.txt", "Com1", "LPT9.log", "CONIN$", "conout$.x",
        ] {
            #expect(FileNameRules.refuses(name, onWindows: true), "\(name)")
            // Each is a file's name everywhere else.
            #expect(!FileNameRules.refuses(name, onWindows: false), "\(name)")
        }
        // Names that only start like a device's are files.
        for name in ["CONSOLE", "nullable.txt", "COM10", "LPT", "AUXILIARY"] {
            #expect(!FileNameRules.refuses(name, onWindows: true), "\(name)")
        }
    }

    @Test("The characters Windows forbids are the ones a settings file's suite loses")
    func forbiddenCharacters() {
        for character in #"<>:"/\|?*"# { #expect(FileNameRules.isForbiddenOnWindows(character)) }
        #expect(FileNameRules.isForbiddenOnWindows("\u{1}"))
        for character in "aZ0 .-_é" { #expect(!FileNameRules.isForbiddenOnWindows(character)) }
    }
}
