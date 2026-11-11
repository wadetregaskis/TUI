//  🖥️ TUI — A Terminal UI framework for Swift
//  PlainTerminalTextTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
import TUIFoundation
import TUIView

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
            (["TUI_PLAIN_TEXT": "transliterate", "LANG": "en_US.UTF-8"], true),
        ] as [([String: String], Bool)])
    func isNeeded(environment: [String: String], expected: Bool) {
        #expect(PlainTerminalText.isNeeded(in: environment) == expected)
    }

    @Test(
        "Text is spelled before layout only when asked for by name: an experiment, off by default",
        arguments: [
            (["TUI_PLAIN_TEXT": "transliterate"], true),
            (["TUI_PLAIN_TEXT": "1"], false),
            (["TUI_PLAIN_TEXT": "0"], false),
            (["LANG": "en_US.ISO8859-1"], false),
            ([:], false),
        ] as [([String: String], Bool)])
    func transliterates(environment: [String: String], expected: Bool) {
        #expect(PlainTerminalText.transliterates(in: environment) == expected)
    }

    @Test(
        "A plain terminal spells its key symbols before layout; the transliteration spells all the words",
        arguments: [
            (["TUI_PLAIN_TEXT": "transliterate"], .all),
            (["TUI_PLAIN_TEXT": "1"], .keys),
            (["LANG": "en_US.ISO8859-1"], .keys),
            (["TUI_PLAIN_TEXT": "0", "LANG": "en_US.ISO8859-1"], .none),
            ([:], .none),
        ] as [([String: String], PlainTerminalText.Respelling)])
    func respelling(environment: [String: String], expected: PlainTerminalText.Respelling) {
        #expect(PlainTerminalText.respelling(in: environment) == expected)
        var values = EnvironmentValues()
        values.respell(expected)
        let spelled: [PlainTerminalText.Respelling: TextSpelling] = [
            .none: .asWritten, .keys: .asciiKeys, .all: .ascii(.standard),
        ]
        #expect(values.textSpelling == spelled[expected])
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
        // Control as a caret, as terminals write it, rather than a blank.
        #expect(PlainTerminalText.folding("⌃Q quit") == "^Q quit")
        // A half block as the block it is, a Canvas's or a picture's cell as
        // much as anything: a control whose ends they are draws its own
        // brackets. And the brackets an app draws as theirs, where most were
        // blank.
        #expect(PlainTerminalText.folding("▐▌▀▄█") == "#####")
        #expect(PlainTerminalText.folding("⌜⌟❨❩⟨⟩⟦⟧") == "[]()<>[]")
        // Each radio button's circle, where the empty ones were blank.
        #expect(PlainTerminalText.folding("●◯◌") == "ooo")
    }

    @Test("A toast's and an alert's emoji marks come out as ASCII that says the same, in their two cells")
    func emojiMarks() {
        #expect(PlainTerminalText.folding("\u{26A0}\u{FE0F}") == "! ")
        #expect(PlainTerminalText.folding("\u{2139}\u{FE0F}") == "i ")
        #expect(PlainTerminalText.folding("\u{2705}") == "ok")
        #expect(PlainTerminalText.folding("\u{274C}") == "X ")
        #expect(PlainTerminalText.folding("\u{1F6D1}") == "X ")
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
