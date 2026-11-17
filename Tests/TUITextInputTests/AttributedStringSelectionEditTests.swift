//  🖥️ TUI — A Terminal UI framework for Swift
//  AttributedStringSelectionEditTests.swift
//
//  SwiftUI's `AttributedString` members that change text at a selection and
//  keep the selection in step (G3 L3). Tracking is checked on both paths: the
//  platform's (Foundation's own on macOS 26, Linux and Windows; the fallback
//  on macOS 15) and the macOS 15 fallback called directly, so a macOS 26
//  machine runs both and a macOS 15 one runs the fallback twice. Where both
//  run, a differential test holds the fallback to Foundation's answers.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFoundation
@testable import TUITextInput

/// Which way a selection is tracked through a change.
enum SelectionTrackingPath: String, CaseIterable, CustomTestStringConvertible {
    /// `transform(updating:body:)` as an app calls it.
    case platform
    /// The macOS 15 fallback, called directly on any platform.
    case macOS15Fallback

    var testDescription: String { rawValue }

    /// Changes `text` by `body`, tracking `selection` this way.
    func transform(
        _ text: inout AttributedString, _ selection: inout AttributedTextSelection,
        body: (inout AttributedString) -> Void
    ) {
        switch self {
        case .platform:
            text.transform(updating: &selection, body: body)
        case .macOS15Fallback:
            let resolved = selection.resolvedRanges(in: text)
            let tracked = AttributedTextSelectionMacOS15Fallbacks.transform(&text, updating: resolved.ranges, body: body)
            selection.moveTo(tracked: tracked, wasInsertion: resolved.isInsertion)
        }
    }
}

/// What a selection selects, in character offsets: a caret's, or each range's.
enum SelectedOffsets: Equatable, CustomStringConvertible {
    case caret(Int)
    case ranges([Range<Int>])

    init(_ selection: AttributedTextSelection, in text: AttributedString) {
        func offset(_ index: AttributedString.Index) -> Int {
            text.characters.distance(from: text.startIndex, to: index)
        }
        switch selection.indices(in: text) {
        case .insertionPoint(let caret): self = .caret(offset(caret))
        case .ranges(let ranges): self = .ranges(ranges.ranges.map { offset($0.lowerBound)..<offset($0.upperBound) })
        }
    }

    var description: String {
        switch self {
        case .caret(let offset): "caret \(offset)"
        case .ranges(let ranges): "ranges \(ranges)"
        }
    }
}

@Suite("AttributedString edits at a selection")
struct AttributedStringSelectionEditTests {
    private typealias Sample = SelectionTestText

    /// "0123456789" changed by replacing `edit` with `insert`, with `selected`
    /// selected (a caret when empty), tracked by `path`.
    private static func track(
        _ selected: Range<Int>, through edit: Range<Int>, inserting insert: String, path: SelectionTrackingPath
    ) -> (text: String, selection: SelectedOffsets) {
        var text = AttributedString("0123456789")
        var selection = AttributedTextSelection(range: Sample.range(selected, in: text))
        path.transform(&text, &selection) { text in
            text.characters.replaceSubrange(Sample.range(edit, in: text), with: insert)
        }
        return (String(text.characters), SelectedOffsets(selection, in: text))
    }

    // MARK: transform(updating:body:)

    @Test("A selection moves with its characters through one change", arguments: SelectionTrackingPath.allCases)
    func transformMovesTheSelection(path: SelectionTrackingPath) {
        // Inserted before, after, at the lower bound (the range does not take
        // it) and at the upper bound (nor here).
        #expect(Self.track(3..<6, through: 1..<1, inserting: "ab", path: path).selection == .ranges([5..<8]))
        #expect(Self.track(3..<6, through: 8..<8, inserting: "ab", path: path).selection == .ranges([3..<6]))
        #expect(Self.track(3..<6, through: 3..<3, inserting: "ab", path: path).selection == .ranges([5..<8]))
        #expect(Self.track(3..<6, through: 6..<6, inserting: "ab", path: path).selection == .ranges([3..<6]))
        // Removed around it: it closes up to an insertion point at the start.
        #expect(Self.track(3..<6, through: 2..<8, inserting: "", path: path).selection == .caret(2))
        // Removed across one end: it keeps the rest.
        #expect(Self.track(3..<6, through: 4..<8, inserting: "", path: path).selection == .ranges([3..<4]))
        #expect(Self.track(1..<4, through: 0..<2, inserting: "", path: path).selection == .ranges([0..<2]))
        // Replaced inside it: it takes the new text.
        let replaced = Self.track(3..<6, through: 4..<5, inserting: "XY", path: path)
        #expect(replaced.text == "0123XY56789")
        #expect(replaced.selection == .ranges([3..<7]))
    }

    @Test("A caret moves past text inserted at it, and to the start of text removed around it",
          arguments: SelectionTrackingPath.allCases)
    func transformMovesTheCaret(path: SelectionTrackingPath) {
        #expect(Self.track(4..<4, through: 4..<4, inserting: "ab", path: path).selection == .caret(6))
        #expect(Self.track(4..<4, through: 2..<6, inserting: "", path: path).selection == .caret(2))
        #expect(Self.track(4..<4, through: 6..<9, inserting: "", path: path).selection == .caret(4))
        #expect(Self.track(4..<4, through: 0..<0, inserting: "abc", path: path).selection == .caret(7))
    }

    @Test("The fallback agrees with Foundation's tracking on single changes (macOS 26, Linux, Windows)")
    func fallbackMatchesFoundation() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else {
            // Foundation has no tracking to compare with on macOS 15; CI's
            // macOS 26 and 27 lanes, and Linux's and Windows', run this.
            return
        }
        // Characters that never repeat, and insertions from characters the
        // text lacks: the only texts where a change has exactly one place a
        // comparison can find, which is the fallback's precondition.
        let pool = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var state: UInt64 = 0x5DEECE66D
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        for _ in 0..<400 {
            let length = 5 + next(30)
            let text = String(pool[0..<length])
            let selectionStart = next(length + 1)
            let selected = selectionStart..<(selectionStart + next(length + 1 - selectionStart))
            let editStart = next(length + 1)
            let edit = editStart..<(editStart + next(length + 1 - editStart))
            let insert = String("!#$%&*+?".prefix(next(4)))
            guard !edit.isEmpty || !insert.isEmpty else { continue }
            var results: [SelectedOffsets] = []
            for path in SelectionTrackingPath.allCases {
                var attributed = AttributedString(text)
                var selection = AttributedTextSelection(range: Sample.range(selected, in: attributed))
                path.transform(&attributed, &selection) { $0.characters.replaceSubrange(Sample.range(edit, in: $0), with: insert) }
                results.append(SelectedOffsets(selection, in: attributed))
            }
            #expect(results[0] == results[1], "\(text): \(selected) through \(edit) ← \"\(insert)\"")
        }
    }

    @Test("The fallback takes several changes for one span from the first to the last")
    func fallbackApproximatesDisjointChanges() {
        var text = AttributedString("0123456789")
        var selection = AttributedTextSelection(insertionPoint: Sample.index(5, in: text))
        SelectionTrackingPath.macOS15Fallback.transform(&text, &selection) { text in
            text.characters.remove(at: Sample.index(8, in: text))
            text.characters.remove(at: Sample.index(1, in: text))
        }
        #expect(String(text.characters) == "02345679")
        // Foundation moves the caret by the first removal alone, to 4; the
        // fallback sees one change over 1..<9 and closes the caret up to 1.
        #expect(SelectedOffsets(selection, in: text) == .caret(1))
    }

    @Test("The fallback's span ends on characters, where a change joins a combining mark to one")
    func fallbackSpanEndsOnCharacters() {
        let before = AttributedString("ex")
        let after = AttributedString("e\u{301}x")
        let span = AttributedTextSelectionMacOS15Fallbacks.TrackedSpan(from: before, to: after)
        // "e" became "é" (two scalars): the common start "e" is not a whole
        // character of the text after, so the span starts before it.
        #expect(span == .init(start: 0, oldEnd: 1, newEnd: 2))
        var text = before
        var selection = AttributedTextSelection(insertionPoint: Sample.index(1, in: text))
        SelectionTrackingPath.macOS15Fallback.transform(&text, &selection) { $0 = AttributedString("e\u{301}x") }
        #expect(SelectedOffsets(selection, in: text) == .caret(1))
    }

    // MARK: replaceSelection

    @Test("Characters typed at a caret take its typing attributes, and the caret goes after them")
    func replaceAtACaret() {
        var text = Sample.measured
        var selection = AttributedTextSelection(insertionPoint: Sample.index(3, in: text))
        text.replaceSelection(&selection, withCharacters: "XY")
        #expect(String(text.characters) == "aaaXYbbb\nccc")
        #expect(SelectedOffsets(selection, in: text) == .caret(5))
        #expect(text[Sample.range(3..<5, in: text)].runs.map(\.foregroundColor) == [Sample.red])
        #expect(selection.affinity(in: text) == .upstream)
    }

    @Test("Characters typed over a selection replace it in its first character's attributes")
    func replaceASelection() {
        var text = Sample.measured
        var selection = AttributedTextSelection(range: Sample.range(2..<5, in: text))
        text.replaceSelection(&selection, withCharacters: "Z")
        #expect(String(text.characters) == "aaZb\nccc")
        #expect(SelectedOffsets(selection, in: text) == .caret(3))
        #expect(text[Sample.range(2..<3, in: text)].runs.map(\.foregroundColor) == [Sample.red])
    }

    @Test("Several selected ranges all go, and the new text goes where the first began")
    func replaceSeveralRanges() {
        var text = AttributedString("0123456789")
        var selection = AttributedTextSelection(ranges: RangeSet([Sample.range(1..<3, in: text), Sample.range(6..<8, in: text)]))
        text.replaceSelection(&selection, withCharacters: "ab")
        #expect(String(text.characters) == "0ab34589")
        #expect(SelectedOffsets(selection, in: text) == .caret(3))
    }

    @Test("Attributed text keeps its own attributes; the default selection appends")
    func replaceWithAttributedText() {
        var text = Sample.measured
        var selection = AttributedTextSelection()
        var tail = AttributedString("!!")
        tail.foregroundColor = Sample.yellow
        text.replaceSelection(&selection, with: tail)
        #expect(String(text.characters) == "aaabbb\nccc!!")
        #expect(selection.indices(in: text) == .insertionPoint(text.endIndex))
        #expect(text[Sample.range(10..<12, in: text)].runs.map(\.foregroundColor) == [Sample.yellow])
    }

    @Test("The macOS 15 replacement finds the caret by offset, past what it inserted")
    func fallbackReplace() {
        var text = AttributedString("0123456789")
        let ranges = [Sample.range(1..<3, in: text), Sample.range(6..<8, in: text)]
        let caret = AttributedTextSelectionMacOS15Fallbacks.replace(ranges, in: &text, with: AttributedString("ab"))
        #expect(String(text.characters) == "0ab34589")
        #expect(text.characters.distance(from: text.startIndex, to: caret) == 3)
    }

    // MARK: transformAttributes

    @Test("Over a selection each run's attributes are changed in turn, and the selection keeps its text")
    func transformAttributesOverRuns() {
        var text = Sample.measured
        var selection = AttributedTextSelection(range: Sample.range(2..<5, in: text))
        var seen: [Color?] = []
        text.transformAttributes(in: &selection) { attributes in
            seen.append(attributes.foregroundColor)
            attributes[SelectionTestKey.self] = 1
        }
        #expect(seen == [Sample.red, Sample.blue])
        #expect(SelectedOffsets(selection, in: text) == .ranges([2..<5]))
        #expect(text[Sample.range(2..<5, in: text)].runs.allSatisfy { $0[SelectionTestKey.self] == 1 })
        #expect(text[Sample.range(0..<2, in: text)].runs.allSatisfy { $0[SelectionTestKey.self] == nil })
        #expect(text[Sample.range(2..<5, in: text)].runs.map(\.foregroundColor) == [Sample.red, Sample.blue])
    }

    @Test("At a caret the typing attributes change, and the next characters typed take them")
    func transformAttributesAtACaret() {
        var text = Sample.measured
        var selection = AttributedTextSelection(insertionPoint: Sample.index(3, in: text))
        text.transformAttributes(in: &selection) { $0.foregroundColor = Sample.yellow }
        #expect(String(text.characters) == "aaabbb\nccc")
        #expect(selection.typingAttributes(in: text).foregroundColor == Sample.yellow)
        text.replaceSelection(&selection, withCharacters: "!")
        #expect(text[Sample.range(3..<4, in: text)].runs.map(\.foregroundColor) == [Sample.yellow])
        #expect(selection.typingAttributes(in: text).foregroundColor == Sample.yellow, "the character before's")
    }

    @Test("A change that throws changes nothing")
    func transformAttributesThatThrows() {
        struct Stop: Error {}
        var text = Sample.measured
        let original = text
        var selection = AttributedTextSelection(range: Sample.range(1..<8, in: text))
        var calls = 0
        do {
            try text.transformAttributes(in: &selection) { attributes in
                calls += 1
                attributes.foregroundColor = Sample.yellow
                if calls == 2 { throw Stop() }
            }
            Issue.record("the body threw")
        } catch {
            #expect(error is Stop)
        }
        #expect(text == original)
    }

    // MARK: subscript

    @Test("The text at a selection is its ranges' text, and nothing at a caret (macOS 26, Linux, Windows)")
    func subscriptBySelection() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        let text = Sample.measured
        let selection = AttributedTextSelection(ranges: RangeSet([Sample.range(0..<2, in: text), Sample.range(7..<9, in: text)]))
        #expect(String(text[selection].characters) == "aacc")
        #expect(text[selection].runs.map(\.foregroundColor) == [Sample.red, Sample.green])
        #expect(text[AttributedTextSelection(insertionPoint: Sample.index(3, in: text))].characters.isEmpty)
    }
}
