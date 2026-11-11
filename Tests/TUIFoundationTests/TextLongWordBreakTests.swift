//  🖥️ TUI — A Terminal UI framework for Swift
//  TextLongWordBreakTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

/// A word longer than its line breaks across lines at character boundaries,
/// as SwiftUI's `Text` does when it wraps (Core Text's word wrapping falls
/// back to characters for a word no line can hold). Before, the word was put
/// on a line of its own and cut there, so all but its first line's worth was
/// lost even with rows to spare.
@MainActor
@Suite("A word longer than its line breaks across lines")
struct TextLongWordBreakTests {

    private func context(width: Int, height: Int = 24) -> RenderContext {
        makeBareRenderContext(width: width, height: height)
    }

    @Test("An over-long word breaks at character boundaries")
    func breaksAtCharacters() {
        #expect(TextWrapping.wrap("Supercalifragilistic", width: 10) == ["Supercalif", "ragilistic"])
        #expect(TextWrapping.wrap("abcdefg", width: 3) == ["abc", "def", "g"])
    }

    @Test("The word starts its own line first, and what follows shares its last line")
    func startsANewLineAndContinues() {
        #expect(TextWrapping.wrap("Hi Supercalifragilistic", width: 10) == ["Hi", "Supercalif", "ragilistic"])
        #expect(TextWrapping.wrap("Supercalifragilistic ok", width: 12) == ["Supercalifra", "gilistic ok"])
    }

    @Test("Each line's width is the width of what it holds")
    func widthsMatchLines() {
        let wrapped = TextWrapping.wrapMeasured("x Supercalifragilistic y", width: 7)
        #expect(wrapped.widths == wrapped.lines.map(\.strippedLength))
        #expect(wrapped.lines.allSatisfy { $0.strippedLength <= 7 })
    }

    @Test("Combining marks stay with their letter")
    func combiningMarksStayWhole() {
        let accented = String(repeating: "e\u{301}", count: 6)
        let lines = TextWrapping.wrap(accented, width: 3)
        #expect(lines == [String(repeating: "e\u{301}", count: 3), String(repeating: "e\u{301}", count: 3)])
    }

    @Test("A Latin word inside wide text breaks too")
    func breaksInsideWideText() {
        #expect(TextWrapping.wrap("日本 Supercalifragilistic", width: 10) == ["日本", "Supercalif", "ragilistic"])
    }

    @Test("An indented word breaks inside the room the indent leaves")
    func indentedWordBreaks() {
        #expect(TextWrapping.wrap("  abcdefghij", width: 6) == ["  abcd", "efghij"])
    }

    @Test("Text draws every character of an over-long word, and measures the rows")
    func textDrawsTheWholeWord() {
        let text = Text("Supercalifragilistic")
        let drawn = renderToBuffer(text, context: context(width: 10)).lines.map(\.stripped)
        #expect(drawn == ["Supercalif", "ragilistic"])
        let size = text.sizeThatFits(proposal: ProposedViewSize(width: 10, height: nil), context: context(width: 10))
        #expect(size.width == 10)
        #expect(size.height == 2)
    }

    @Test("A line limit still truncates the word with an ellipsis")
    func lineLimitStillTruncates() {
        let one = renderToBuffer(Text("Supercalifragilistic").lineLimit(1), context: context(width: 10))
        #expect(one.lines.map(\.stripped) == ["Supercali…"])
        let two = renderToBuffer(Text("Supercalifragilistic").lineLimit(2), context: context(width: 8))
        #expect(two.lines.map(\.stripped) == ["Supercal", "ifragil…"])
    }

    /// A `.sizeDependent` text takes the widest spelling that shows itself
    /// whole; a word broken across lines is not whole, so a narrower spelling
    /// is still chosen over breaking "Wednesday".
    @Test("A spelling that needs a word broken does not fit whole")
    func brokenWordDoesNotFitWhole() {
        let context = context(width: 5)
        #expect(!Text("Wednesday").fitsWhole(width: 5, height: nil, context: context))
        #expect(Text("Wed").fitsWhole(width: 5, height: nil, context: context))
        #expect(TextWrapping.wrapMeasured("Wednesday", width: 5).brokeAWord)
        #expect(!TextWrapping.wrapMeasured("Wed is", width: 3).brokeAWord)
    }
}
