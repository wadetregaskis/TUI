//  🖥️ TUI — A Terminal UI framework for Swift
//  TextParagraphAlignmentTests.swift
//
//  An attributed string's paragraph `alignment` (G3 L4, the owner's ruling
//  A-ATTRED-3 of 2026-11-17): the attribute under SwiftUI's name, bounded by
//  paragraphs, and a `Text` of the string aligning each paragraph's lines
//  its own way.
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

    /// A paragraph's alignment, named here and not as
    /// `AttributedString.TextAlignment`: on macOS a module that loads Core
    /// Text sees its type of that name too, and without
    /// `MemberImportVisibility` naming it is ambiguous, as an app's would be
    /// (`AttributeScopes.CoreTextAttributes`). Setting it is not.
    enum Side { case left, center, right }

    /// Sets `range`'s paragraph's alignment to `side`'s.
    static func align(_ string: inout AttributedString, _ range: Range<AttributedString.Index>, _ side: Side) {
        switch side {
        case .left: string[range].alignment = .left
        case .center: string[range].alignment = .center
        case .right: string[range].alignment = .right
        }
    }

    /// "alpha" (5) over "hi" (2), the second paragraph aligned `side`.
    private func twoParagraphs(secondAligned side: Side) -> AttributedString {
        var string = AttributedString("alpha\nhi")
        Self.align(&string, string.range(of: "hi")!, side)
        return string
    }

    @Test("The attribute reads back under SwiftUI's name, and covers its whole paragraph")
    func boundedByParagraphs() throws {
        var string = AttributedString("one two\nthree")
        let two = try #require(string.range(of: "two"))
        string[two].alignment = .center
        // Set on one word, it is the paragraph's: every run of it says so, its
        // newline included, and the next paragraph's say nothing.
        let runs = Array(string.runs)
        let first = String(string[runs[0].range].characters)
        #expect(first == "one two\n", "one run for the whole first paragraph: \(runs.map { String(string[$0.range].characters) })")
        #expect(runs[0].alignment == .center)
        #expect(runs.count == 2 && runs[1].alignment == nil)
        let centred = try #require(runs[0].alignment)
        #expect(type(of: centred).allCases == [.left, .center, .right])
    }

    @Test("A centred paragraph centres its lines in the text's width")
    func centred() {
        let rows = render(Text(twoParagraphs(secondAligned: .center)), width: 12)
        #expect(rows[0] == "alpha")
        #expect(rows[1] == " hi  ", "'\(rows[1])'")
    }

    @Test("A right-aligned paragraph puts its lines flush right")
    func right() {
        let rows = render(Text(twoParagraphs(secondAligned: .right)), width: 12)
        #expect(rows[1] == "   hi", "'\(rows[1])'")
    }

    @Test("A paragraph's alignment wins over multilineTextAlignment for its own lines only")
    func winsOverTheModifier() {
        var string = AttributedString("alpha\nhi\nyo")
        string[string.range(of: "hi")!].alignment = .left
        let rows = render(Text(string).multilineTextAlignment(.trailing), width: 12)
        #expect(rows[1] == "hi   ", "the stated paragraph stays left: '\(rows[1])'")
        #expect(rows[2] == "   yo", "the other takes the modifier's: '\(rows[2])'")
    }

    @Test("Every wrapped line of a paragraph takes its alignment")
    func wrappedLines() {
        var string = AttributedString("aaaaaa\nbb cc")
        string[string.range(of: "bb")!].alignment = .right
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
