//  🖥️ TUI — A Terminal UI framework for Swift
//  AttributedTextSelectionTests.swift
//
//  SwiftUI's selection in attributed text (G3 L3): the indices it answers for
//  a text, its fallback for one it no longer fits, the typing attributes the
//  macOS text system's rule gives (B-ATTRED-16) and the attributes it covers.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFoundation
@testable import TUITextInput

/// A key of the tests' own, to read `Attributes` by a key's type: SwiftUI's
/// scope's name is ambiguous in a type position on macOS (see
/// `AttributeScopes.SwiftUIAttributes`).
enum SelectionTestKey: AttributedStringKey {
    typealias Value = Int
    static let name = "SelectionTestKey"
}

/// Texts in coloured runs, and the inks they are drawn in, for the selection
/// suites.
enum SelectionTestText {
    static let red = Color.rgb(200, 20, 20)
    static let blue = Color.rgb(20, 20, 200)
    static let orange = Color.rgb(230, 120, 20)
    static let green = Color.rgb(20, 160, 20)
    static let yellow = Color.rgb(220, 200, 20)

    /// The runs, each in its ink, one after another.
    static func runs(_ parts: [(String, Color)]) -> AttributedString {
        parts.reduce(into: AttributedString()) { text, part in
            var piece = AttributedString(part.0)
            piece.foregroundColor = part.1
            text += piece
        }
    }

    /// The text macOS's typing attributes were measured on (the G3 design's
    /// §8): "aaa" red, "bbb" blue, a line break orange, "ccc" green.
    static let measured = runs([("aaa", red), ("bbb", blue), ("\n", orange), ("ccc", green)])

    /// The index `offset` characters into `text`.
    static func index(_ offset: Int, in text: AttributedString) -> AttributedString.Index {
        text.characters.index(text.startIndex, offsetBy: offset)
    }

    /// The range of characters `range` of `text`.
    static func range(_ range: Range<Int>, in text: AttributedString) -> Range<AttributedString.Index> {
        index(range.lowerBound, in: text)..<index(range.upperBound, in: text)
    }
}

@Suite("AttributedTextSelection")
struct AttributedTextSelectionTests {
    private typealias Sample = SelectionTestText

    // MARK: Indices

    @Test("The default selection is an insertion point at the end of whichever text it is read in")
    func defaultSelection() {
        let selection = AttributedTextSelection()
        #expect(selection.indices(in: Sample.measured) == .insertionPoint(Sample.measured.endIndex))
        let empty = AttributedString()
        #expect(selection.indices(in: empty) == .insertionPoint(empty.endIndex))
    }

    @Test("An empty range is an insertion point; a range and a range set select what they were given")
    func initialisers() {
        let text = Sample.measured
        let caret = Sample.index(2, in: text)
        #expect(AttributedTextSelection(range: caret..<caret) == AttributedTextSelection(insertionPoint: caret))
        #expect(AttributedTextSelection(range: caret..<caret).indices(in: text) == .insertionPoint(caret))
        let range = Sample.range(1..<5, in: text)
        #expect(AttributedTextSelection(range: range).indices(in: text) == .ranges(RangeSet(range)))
        let ranges = RangeSet([Sample.range(0..<1, in: text), Sample.range(4..<6, in: text)])
        #expect(AttributedTextSelection(ranges: ranges).indices(in: text) == .ranges(ranges))
        // A range set with nothing in it has no position: the default's.
        #expect(AttributedTextSelection(ranges: RangeSet()).indices(in: text) == .insertionPoint(text.endIndex))
    }

    @Test("Indices that run past a text fall back to an insertion point at its end")
    func indicesPastTheEnd() {
        let long = AttributedString("a longer text than the other")
        let short = AttributedString("short")
        let selection = AttributedTextSelection(range: Sample.range(2..<20, in: long))
        #expect(selection.indices(in: short) == .insertionPoint(short.endIndex))
        let caret = AttributedTextSelection(insertionPoint: Sample.index(20, in: long))
        #expect(caret.indices(in: short) == .insertionPoint(short.endIndex))
    }

    @Test("Indices from before a change fall back where Foundation can tell (macOS 26, Linux, Windows)")
    func staleIndicesFallBack() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else {
            // macOS 15's indices record no text: its fallback can only see an
            // index past the end, which `macOS15ValidityIsBounds` pins.
            return
        }
        var text = AttributedString("hello world")
        let selection = AttributedTextSelection(range: Sample.range(0..<5, in: text))
        #expect(selection.indices(in: text) == .ranges(RangeSet(Sample.range(0..<5, in: text))))
        text.characters.append("!")
        #expect(selection.indices(in: text) == .insertionPoint(text.endIndex))
    }

    @Test("macOS 15's validity is the text's bounds")
    func macOS15ValidityIsBounds() {
        let text = AttributedString("hello")
        let long = AttributedString("hello, world")
        #expect(AttributedTextSelectionMacOS15Fallbacks.isInside(Sample.range(1..<4, in: text), text))
        #expect(AttributedTextSelectionMacOS15Fallbacks.isInside(text.endIndex..<text.endIndex, text))
        #expect(!AttributedTextSelectionMacOS15Fallbacks.isInside(Sample.range(1..<8, in: long), text))
        // An index from another text, inside this one, is taken as it is.
        #expect(AttributedTextSelectionMacOS15Fallbacks.isInside(Sample.range(1..<4, in: long), text))
    }

    // MARK: Typing attributes (B-ATTRED-16)

    @Test("Typing takes the character before the caret's attributes, as macOS's text system does")
    func typingAttributesFollowTheCharacterBefore() {
        let text = Sample.measured
        func typing(at offset: Int) -> Color? {
            AttributedTextSelection(insertionPoint: Sample.index(offset, in: text)).typingAttributes(in: text).foregroundColor
        }
        #expect(typing(at: 3) == Sample.red, "at the red–blue edge: the red before it")
        #expect(typing(at: 2) == Sample.red)
        #expect(typing(at: 0) == Sample.red, "at the start: the first character's")
        #expect(typing(at: 6) == Sample.blue, "before a line break: the character before")
        #expect(typing(at: 7) == Sample.green, "at a paragraph's start: its first character's")
        #expect(typing(at: 10) == Sample.green, "at the end: the character before")
    }

    @Test("In an empty paragraph typing takes that paragraph's own line break's attributes")
    func typingAttributesInAnEmptyParagraph() {
        let text = Sample.runs([("x", Sample.red), ("\n", Sample.orange), ("\n", Sample.yellow), ("y", Sample.green)])
        let selection = AttributedTextSelection(insertionPoint: Sample.index(2, in: text))
        #expect(selection.typingAttributes(in: text).foregroundColor == Sample.yellow)
        // After a final line break there is no paragraph's own: the break's.
        let trailing = Sample.runs([("x", Sample.red), ("\n", Sample.orange)])
        #expect(AttributedTextSelection().typingAttributes(in: trailing).foregroundColor == Sample.orange)
    }

    @Test("Over a selection typing takes its first character's; given ones win; an empty text has none")
    func typingAttributesOverSelectionsAndGiven() {
        let text = Sample.measured
        #expect(AttributedTextSelection(range: Sample.range(4..<8, in: text)).typingAttributes(in: text).foregroundColor
            == Sample.blue)
        var given = AttributeContainer()
        given.foregroundColor = Sample.yellow
        let caret = AttributedTextSelection(insertionPoint: Sample.index(1, in: text), typingAttributes: given)
        #expect(caret.typingAttributes(in: text) == given)
        #expect(AttributedTextSelection().typingAttributes(in: AttributedString()) == AttributeContainer())
    }

    // MARK: Attributes

    @Test("A selection's attributes are each selected run's, in order; an insertion point's its typing")
    func attributesOfRuns() {
        var text = Sample.measured
        text[Sample.range(4..<5, in: text)][SelectionTestKey.self] = 7
        let selection = AttributedTextSelection(range: Sample.range(1..<8, in: text))
        let inks = Array(selection.attributes(in: text)[\.foregroundColor])
        // The key on the fifth character splits the blue run in three.
        #expect(inks == [Sample.red, Sample.blue, Sample.blue, Sample.blue, Sample.orange, Sample.green])
        #expect(Array(selection.attributes(in: text)[SelectionTestKey.self]) == [nil, nil, 7, nil, nil, nil])
        #expect(selection.attributes(in: text)[\.foregroundColor].contains(Sample.green))

        let ranges = AttributedTextSelection(ranges: RangeSet([Sample.range(0..<1, in: text), Sample.range(8..<9, in: text)]))
        #expect(Array(ranges.attributes(in: text)[\.foregroundColor]) == [Sample.red, Sample.green])

        let caret = AttributedTextSelection(insertionPoint: Sample.index(5, in: text))
        #expect(Array(caret.attributes(in: text)) == [caret.typingAttributes(in: text)])
    }

    // MARK: Affinity and equality

    @Test("A selection made outside an editor leans upstream, as macOS reports one the program set")
    func affinityOfAMadeSelection() {
        let text = Sample.measured
        #expect(AttributedTextSelection().affinity(in: text) == .upstream)
        #expect(AttributedTextSelection(range: Sample.range(0..<2, in: text)).affinity(in: text) == .upstream)
    }

    @Test("Selections are equal by their indices and their typing attributes")
    func equality() {
        let text = Sample.measured
        let caret = Sample.index(3, in: text)
        let made = AttributedTextSelection(insertionPoint: caret)
        #expect(made == AttributedTextSelection(insertionPoint: caret))
        var bold = AttributeContainer()
        bold.foregroundColor = Sample.red
        #expect(AttributedTextSelection(insertionPoint: caret, typingAttributes: bold)
            != AttributedTextSelection(insertionPoint: caret))
        #expect(AttributedTextSelection(insertionPoint: caret) != AttributedTextSelection(insertionPoint: Sample.index(4, in: text)))
    }
}
