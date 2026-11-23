//  🖥️ TUI — A Terminal UI framework for Swift
//  ASCIIFastPathTests.swift
//
//  An editor's ASCII line is wrapped and drawn from its bytes (EDMEM-2): each
//  byte's rules — its cells, its glyph, whether it ends a paragraph — must be
//  its character's, and a byte walk must lay a line out as the character walk
//  does.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITextInput

/// Lines of ASCII, the same on every run (`SplitMix`, seeded), heavy in what
/// a wrap decides on: spaces, tabs, long words, the newlines a line may still
/// hold (a lone CR, VT, FF) and controls.
private func asciiLines(count: Int) -> [String] {
    var random = SplitMix(state: 2026_11_22)
    let pieces = ["a", "bc", "defghijk", " ", "  ", "\t", "\r", "\u{0B}", "\u{0C}", "\u{01}", "\u{7F}", "x y", "{}"]
    return (0..<count).map { _ in
        (0..<Int.random(in: 0...14, using: &random)).map { _ in pieces.randomElement(using: &random)! }.joined()
    }
}

@Suite("ASCII fast paths: each byte as its character")
struct ASCIIFastPathTests {
    @Test("A byte advances, draws and ends a paragraph as its character does")
    func byteRulesAreTheCharacters() {
        for byte in UInt8(0)..<0x80 {
            let character = Character(Unicode.Scalar(byte))
            #expect(TextCharacters.character(ascii: byte) == character)
            #expect(TextFieldHandler.displayCharacter(ascii: byte) == TextFieldHandler.displayCharacter(character))
            for tabWidth in [TabWidth.periodic(4), .periodic(8), .fixed(3)] {
                for column in 0..<10 {
                    #expect(
                        TabLayout.advance(from: column, overASCII: byte, tabWidth: tabWidth)
                            == TabLayout.advance(from: column, over: character, tabWidth: tabWidth),
                        "byte \(byte) at column \(column)")
                }
            }
            // The wrap's byte newlines are LF, VT, FF and CR: the ASCII newlines.
            #expect((0x0A...0x0D).contains(byte) == character.isNewline, "byte \(byte)")
        }
    }

    @Test("A character's byte is read where it is one, in an ASCII line and in one that is not")
    func asciiByteAt() {
        let ascii = TextCharacters("a\tb")
        #expect((0..<3).map { ascii.asciiByte(at: $0) } == [0x61, 0x09, 0x62])
        let mixed = TextCharacters("é\tx漢\r\n")
        #expect((0..<mixed.count).map { mixed.asciiByte(at: $0) } == [nil, 0x09, 0x78, nil, nil])
        // `unsafe` outside `#expect`: the closures take an `UnsafeBufferPointer`,
        // which Swift 6.4's strict memory safety flags inside the macro too.
        let asciiBytes = unsafe TextCharacters("ab").withASCIIBytes { unsafe Array($0) }
        let mixedBytes = unsafe mixed.withASCIIBytes { _ in true }
        #expect(asciiBytes == [0x61, 0x62])
        #expect(mixedBytes == nil)
    }

    @Test("An editor's ASCII line wraps through its bytes as it does through its characters")
    func editorWrapMatchesTheCharacterWalk() {
        for line in asciiLines(count: 400) {
            let characters = TextCharacters(line)
            for tabWidth in [TabWidth.periodic(4), .fixed(3), .fixed(300)] {
                for width in [1, 2, 3, 5, 8, 13, 40] {
                    let fast = SoftWrapLayout(characters, width: width, tabWidth: tabWidth)
                    let walked = SoftWrapLayout(walking: Array(line), width: width) { character, column in
                        TabLayout.advance(from: column, over: character, tabWidth: tabWidth)
                    }
                    #expect(fast == walked, "\(line.debugDescription) at \(width), \(tabWidth)")
                    #expect(fast.cellWidths == walked.cellWidths)
                }
            }
        }
    }

    @Test("A field's ASCII text wraps through its bytes as it does through its characters")
    func fieldWrapMatchesTheCharacterWalk() {
        for line in asciiLines(count: 200) {
            for width in [1, 3, 8, 21] {
                let fast = SoftWrapLayout(TextCharacters(line), width: width, cellWidth: TextFieldHandler.verticalCellWidth)
                let walked = SoftWrapLayout(walking: Array(line), width: width) { character, column in
                    column + TextFieldHandler.verticalCellWidth(character)
                }
                #expect(fast == walked, "\(line.debugDescription) at \(width)")
            }
        }
    }
}
