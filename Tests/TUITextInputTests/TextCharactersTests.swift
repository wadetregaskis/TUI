//  🖥️ TUI — A Terminal UI framework for Swift
//  TextCharactersTests.swift
//
//  `TextCharacters`, a TextEditor's line held as UTF-8 (EDMEM-1): it is the
//  array of `Character`s it replaced, character for character, whatever is
//  done to it, and holds an ASCII line as its bytes alone.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUITextInput

@Suite("TextCharacters: an editor's line as UTF-8, indexed as an array of characters")
struct TextCharactersTests {
    /// Texts of every kind of character: ASCII, a ZWJ family, flags, combining
    /// marks, CJK, right-to-left, a tab, a CRLF and a lone CR.
    static let texts = [
        "", "a", "plain ascii, 31 bytes long ok", "\t\tx",
        "a\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}b", "\u{1F1EF}\u{1F1F5}\u{1F1FA}\u{1F1F8}",
        "e\u{301}e\u{300}\u{323}", "\u{4E2D}\u{6587}\u{65E5}\u{672C}", "\u{05E9}\u{05DC}\u{05D5}\u{05DD} abc",
        "a\r\nb", "a\rb", "mixed \u{4E2D} and \u{1F600} and e\u{301}",
    ]

    @Test("Made from a string, it is the string's characters", arguments: texts)
    func madeFromString(_ text: String) {
        let characters = TextCharacters(text)
        #expect(Array(characters) == Array(text))
        #expect(characters.count == text.count)
        #expect(characters.string == text)
        for index in characters.indices {
            #expect(characters[index] == Array(text)[index])
            #expect(characters.string(in: index..<characters.count) == String(Array(text)[index...]))
            #expect(characters.utf8Offset(of: index) == Array(text)[..<index].reduce(0) { $0 + $1.utf8.count })
        }
    }

    @Test("Characters appended one at a time stay apart, as an array keeps them, until segmented")
    func appendedStayApart() {
        var characters = TextCharacters("e")
        characters.append("\u{301}")
        #expect(characters.count == 2)
        #expect(Array(characters) == ["e", "\u{301}"])
        #expect(characters.string == "e\u{301}")
        #expect(characters.segmented().count == 1)
        #expect(characters.segmented() == TextCharacters("e\u{301}"))
        // Two regional indicators, apart, pair once segmented.
        let flag: TextCharacters = ["\u{1F1EF}", "\u{1F1F5}"]
        #expect(flag.count == 2)
        #expect(flag.segmented().count == 1)
    }

    @Test("Replacing a span leaves what an array would", arguments: texts)
    func replacing(_ text: String) {
        let inserted: [[Character]] = [[], ["x"], ["\u{4E2D}", "\u{301}"], Array("\u{1F1EF}\u{1F1F5}y")]
        let count = text.count
        for lower in 0...count {
            for upper in lower...count {
                for insert in inserted {
                    var array = Array(text)
                    var characters = TextCharacters(text)
                    array.replaceSubrange(lower..<upper, with: insert)
                    characters.replaceSubrange(lower..<upper, with: insert)
                    #expect(Array(characters) == array)
                    #expect(characters.string == String(array))
                    var fromCharacters = TextCharacters(text)
                    fromCharacters.replaceSubrange(lower..<upper, with: TextCharacters(insert))
                    #expect(fromCharacters.hasSameBytes(as: characters))
                }
            }
        }
    }

    @Test("Spans taken out, joined and swapped are an array's", arguments: texts)
    func slicesAndJoins(_ text: String) {
        let characters = TextCharacters(text)
        let array = Array(text)
        for split in 0...array.count {
            let head = characters.characters(in: 0..<split)
            #expect(Array(head) == Array(array[..<split]))
            var joined = head
            joined += characters[split...]
            #expect(joined.hasSameBytes(as: characters))
            #expect(head + TextCharacters("\u{1F600}") == TextCharacters(Array(array[..<split]) + ["\u{1F600}"]))
        }
        guard array.count >= 2 else { return }
        var swapped = characters
        var swappedArray = array
        swapped.swapAt(0, array.count - 1)
        swappedArray.swapAt(0, array.count - 1)
        #expect(Array(swapped) == swappedArray)
    }

    @Test("Equal as arrays are: canonically equivalent characters are equal, the bytes not the same")
    func equality() {
        let composed = TextCharacters("\u{E9}")
        let decomposed = TextCharacters("e\u{301}")
        #expect(composed == decomposed)
        #expect(!composed.hasSameBytes(as: decomposed))
        #expect(TextCharacters("ab") != TextCharacters("abc"))
        let literal: TextCharacters = ["a", "\u{4E2D}"]
        #expect(literal == TextCharacters("a\u{4E2D}"))
    }
}
