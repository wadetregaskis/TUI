//  🖥️ TUI — A Terminal UI framework for Swift
//  UnderlineEffectsTests.swift
//
//  The Text Styles page's two word-by-word underlines: the glide, whose
//  leading end reaches the next word before its tail follows, and the slide,
//  whose two ends move together (the owner's evening feedback, 2026-11-10,
//  item 6).
//
//  Created by Wade Tregaskis
//  License: MIT

// Only where the package can depend on the app (see Package.swift).
#if canImport(Example)

import Testing

@testable import Example
import TUI
import TUITesting

@MainActor
@Suite("The word-by-word underlines")
struct UnderlineEffectsTests {
    /// Three words of different widths, 8, 4 and 5 cells, with gaps between.
    private let words = [0..<8, 9..<13, 15..<20]

    /// The spans drawn through the first leg, from the first word to the
    /// second, a hundredth of it at a time.
    private func firstLeg(_ span: ([Range<Int>], Double) -> Range<Int>) -> [Range<Int>] {
        (0...99).map { span(words, WordGlide.stride * Double($0) / 100) }
    }

    @Test("The slide moves both ends together, from one word to the next")
    func slideMovesBothEnds() {
        let spans = firstLeg(WordSlide.span(of:at:))
        #expect(spans.first == words[0], "it starts under the first word")
        #expect(spans.last == words[1], "and ends under the second: \(spans)")
        // Two thirds through the leg, halfway through the move: both ends are
        // on their way, neither waiting for the other.
        let halfway = spans[67]
        #expect(halfway.lowerBound > words[0].lowerBound && halfway.lowerBound < words[1].lowerBound, "\(halfway)")
        #expect(halfway.upperBound > words[0].upperBound && halfway.upperBound < words[1].upperBound, "\(halfway)")
        // Only ever as long as a word, give or take the cell an end rounds by:
        // it never stretches across both.
        for span in spans {
            #expect(span.count >= words[1].count - 1 && span.count <= words[0].count + 1, "\(span) in \(spans)")
        }
        #expect(Set(spans).count > 4, "it moves in steps, not a jump: \(spans)")
    }

    @Test("The glide keeps its tail still until its head has reached the next word")
    func glideIsACaterpillar() {
        let spans = firstLeg(WordGlide.span(of:at:))
        #expect(spans.contains(words[0].lowerBound..<words[1].upperBound), "it spans both words: \(spans)")
    }

    @Test("The slide is named in every language the glide is")
    func slideIsNamed() {
        let languages = ExampleStrings.g25.filter { $0.value["page.textStyles.effect.sweep"] != nil }.keys
        #expect(languages.count == 7)
        for language in languages {
            #expect(ExampleStrings.g25[language]?["page.textStyles.effect.slide"] != nil, "\(language)")
        }
    }
}

#endif
