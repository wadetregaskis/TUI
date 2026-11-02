//  🖥️ TUI — A Terminal UI framework for Swift
//  PlainTerminalTextTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore

@Suite("Plain text for a terminal that can show nothing else")
struct PlainTerminalTextTests {
    @Test(
        "The locale says so only by naming another character set",
        arguments: [
            (["LANG": "en_US.ISO8859-1"], true),
            (["LANG": "ru_RU.KOI8-R"], true),
            (["LC_ALL": "de_DE.ISO8859-15@euro"], true),
            (["LANG": "en_US.UTF-8"], false),
            (["LANG": "en_US.utf8"], false),
            (["LANG": "C"], false),
            (["LANG": "POSIX"], false),
            ([:], false),
            (["LC_ALL": "en_US.UTF-8", "LANG": "en_US.ISO8859-1"], false),
            (["LC_ALL": "", "LC_CTYPE": "en_US.ISO8859-1", "LANG": "en_US.UTF-8"], true),
            (["TUI_PLAIN_TEXT": "1", "LANG": "en_US.UTF-8"], true),
            (["TUI_PLAIN_TEXT": "0", "LANG": "en_US.ISO8859-1"], false),
        ] as [([String: String], Bool)])
    func isNeeded(environment: [String: String], expected: Bool) {
        #expect(PlainTerminalText.isNeeded(in: environment) == expected)
    }

    @Test("A row that is ASCII comes back as it was")
    func asciiIsUntouched() {
        let row = "\u{1B}[1mplain\u{1B}[0m"
        #expect(PlainTerminalText.folding(row) == row)
    }

    @Test("Every character keeps its cells, and comes out ASCII", arguments: ["é", "ß", "你", "好", "🙂", "│", "┌", "█", "⠋", "→", "●", "✓", "…"])
    func keepsItsCells(character: String) {
        let folded = PlainTerminalText.folding(character)
        #expect(folded.utf8.allSatisfy { $0 < 0x80 }, "\(folded.debugDescription)")
        #expect(folded.count == character.strippedLength, "\(folded.debugDescription)")
    }

    @Test("Accents and the framework's shapes come out as what they look like")
    func spellings() {
        #expect(PlainTerminalText.folding("Café") == "Cafe")
        #expect(PlainTerminalText.folding("┌─┐│└┘") == "+-+|++")
        #expect(PlainTerminalText.folding("← → ▲ ▼") == "< > ^ v")
    }

    @Test("Escape sequences pass through, an OSC 8 link's address among them")
    func escapesAreKept() {
        let open = "\u{1B}]8;;https://example.com/é\u{1B}\\"
        let close = "\u{1B}]8;;\u{1B}\\"
        #expect(
            PlainTerminalText.folding("\u{1B}[31mé\u{1B}[0m \(open)ü\(close)")
                == "\u{1B}[31me\u{1B}[0m \(open)u\(close)")
    }

    #if canImport(Darwin)
        @Test("Other scripts come out in Latin, cut to their cells, where Foundation can")
        func transliteration() {
            #expect(PlainTerminalText.folding("你好") == "niha")
            #expect(PlainTerminalText.folding("Привет") == "Privet")
        }
    #endif
}
