//  🖥️ TUI — A Terminal UI framework for Swift
//  TextParagraphAlignmentTests.swift
//
//  An attributed string's paragraph `alignment` (G3 L4, the owner's ruling
//  A-ATTRED-3 of 2026-11-17): the attribute under SwiftUI's name, bounded by
//  paragraphs, and a `Text` of the string aligning each paragraph's lines
//  its own way. Each case runs through SwiftUI's `alignment` where it exists
//  (Core Text's on a Mac, so macOS 26) and TUI's `paragraphAlignment`
//  everywhere (the owner's ruling attralign, 2026-11-19).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Paragraph alignment in an AttributedString")
struct TextParagraphAlignmentTests {
    /// The stripped lines of `view` drawn `width` cells wide.
    private func render(_ view: some View, width: Int, height: Int = 8) -> [String] {
        renderToBuffer(AnyView(view), context: makeBareRenderContext(width: width, height: height))
            .lines.map { $0.stripped }
    }

    /// "alpha" (5) over "hi" (2), the second paragraph aligned `side`.
    private func twoParagraphs(
        secondAligned side: TextAlignment, _ spelling: ParagraphAlignmentSpelling
    ) -> AttributedString {
        var string = AttributedString("alpha\nhi")
        spelling.align(&string, string.range(of: "hi")!, side)
        return string
    }

    @Test(
        "The attribute reads back under its name, and covers its whole paragraph",
        arguments: ParagraphAlignmentSpelling.available)
    func boundedByParagraphs(_ spelling: ParagraphAlignmentSpelling) throws {
        var string = AttributedString("one two\nthree")
        let two = try #require(string.range(of: "two"))
        spelling.align(&string, two, .center)
        // Set on one word, it is the paragraph's: every run of it says so, its
        // newline included, and the next paragraph's say nothing.
        let runs = Array(string.runs)
        let first = String(string[runs[0].range].characters)
        #expect(first == "one two\n", "one run for the whole first paragraph: \(runs.map { String(string[$0.range].characters) })")
        #expect(spelling.alignment(of: runs[0]) == .center)
        #expect(string[runs[0].range].drawnParagraphAlignment == .center)
        #expect(runs.count == 2 && spelling.alignment(of: runs[1]) == nil)
    }

    @Test("SwiftUI's alignment runs where Core Text has it, which on a Mac is macOS 26")
    func alignmentRunsWhereCoreTextHasIt() {
        // Held per side (never accepting both): a Mac before macOS 26 has only
        // TUI's spelling; macOS 26, Linux and Windows have both.
        if #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
            #expect(ParagraphAlignmentSpelling.available == [.alignment, .paragraphAlignment])
            #expect(AttributedString.TextAlignment.allCases == [.left, .center, .right])
        } else {
            #expect(ParagraphAlignmentSpelling.available == [.paragraphAlignment])
        }
    }

    @Test("Where a paragraph states both, SwiftUI's alignment wins")
    func alignmentWinsOverParagraphAlignment() throws {
        guard ParagraphAlignmentSpelling.available.contains(.alignment) else { return }
        var string = AttributedString("alpha\nhi")
        let hi = try #require(string.range(of: "hi"))
        ParagraphAlignmentSpelling.paragraphAlignment.align(&string, hi, .trailing)
        ParagraphAlignmentSpelling.alignment.align(&string, hi, .center)
        #expect(string[hi].drawnParagraphAlignment == .center)
        #expect(render(Text(string), width: 12)[1] == " hi  ")
    }

    @Test("A centred paragraph centres its lines in the text's width", arguments: ParagraphAlignmentSpelling.available)
    func centred(_ spelling: ParagraphAlignmentSpelling) {
        let rows = render(Text(twoParagraphs(secondAligned: .center, spelling)), width: 12)
        #expect(rows[0] == "alpha")
        #expect(rows[1] == " hi  ", "'\(rows[1])'")
    }

    @Test("A right-aligned paragraph puts its lines flush right", arguments: ParagraphAlignmentSpelling.available)
    func right(_ spelling: ParagraphAlignmentSpelling) {
        let rows = render(Text(twoParagraphs(secondAligned: .trailing, spelling)), width: 12)
        #expect(rows[1] == "   hi", "'\(rows[1])'")
    }

    @Test(
        "A paragraph's alignment wins over multilineTextAlignment for its own lines only",
        arguments: ParagraphAlignmentSpelling.available)
    func winsOverTheModifier(_ spelling: ParagraphAlignmentSpelling) {
        var string = AttributedString("alpha\nhi\nyo")
        spelling.align(&string, string.range(of: "hi")!, .leading)
        let rows = render(Text(string).multilineTextAlignment(.trailing), width: 12)
        #expect(rows[1] == "hi   ", "the stated paragraph stays left: '\(rows[1])'")
        #expect(rows[2] == "   yo", "the other takes the modifier's: '\(rows[2])'")
    }

    @Test("Every wrapped line of a paragraph takes its alignment", arguments: ParagraphAlignmentSpelling.available)
    func wrappedLines(_ spelling: ParagraphAlignmentSpelling) {
        var string = AttributedString("aaaaaa\nbb cc")
        spelling.align(&string, string.range(of: "bb")!, .trailing)
        // At 6 cells: "aaaaaa", then "bb cc" fits whole (5), right-aligned.
        let rows = render(Text(string), width: 6)
        #expect(rows[0] == "aaaaaa")
        #expect(rows[1] == " bb cc", "'\(rows[1])'")
        // At 4: "bb" and "cc" are both the right-aligned paragraph's.
        let narrow = render(Text(string), width: 4)
        #expect(narrow.count >= 4)
        #expect(narrow[2] == "  bb" && narrow[3] == "  cc", "\(narrow)")
    }
}
