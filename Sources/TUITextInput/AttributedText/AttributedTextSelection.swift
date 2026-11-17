//  🖥️ TUI — A Terminal UI framework for Swift
//  AttributedTextSelection.swift
//
//  SwiftUI's selection in attributed text: an insertion point or ranges of an
//  `AttributedString`, the attributes typing there takes, and the attributes
//  the selection covers.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

/// Represents a selection of attributed text — mirrors SwiftUI's
/// `AttributedTextSelection`.
///
/// A selection is an insertion point (the caret) or one or more ranges of the
/// text. Its indices belong to the text they were made from: keep the two in
/// step by changing the text through `AttributedString`'s
/// ``Foundation/AttributedString/transform(updating:body:)``,
/// ``Foundation/AttributedString/replaceSelection(_:withCharacters:)``,
/// ``Foundation/AttributedString/replaceSelection(_:with:)`` and
/// ``Foundation/AttributedString/transformAttributes(in:body:)``, which move the
/// selection with the characters. After any other change, make a new selection.
///
/// ```swift
/// @State private var text = AttributedString()
/// @State private var selection = AttributedTextSelection()
///
/// Button("Insert Date") {
///     text.replaceSelection(&selection, withCharacters: Date.now.formatted())
/// }
/// ```
///
/// On macOS 26 and later, and on Linux and Windows, an index's validity and
/// the tracking of a selection through an edit are Foundation's own
/// (`isValid(within:)`, `transform(updating:body:)`). macOS 15's Foundation
/// has neither, and there TUI approximates them (see
/// `AttributedTextSelection+MacOS15Fallbacks.swift`): a selection whose indices
/// fall inside a text is taken as valid for it, and a change made through
/// ``Foundation/AttributedString/transform(updating:body:)`` is found by
/// comparing the text before it and after.
///
/// SwiftUI's is macOS 26; TUI's builds on macOS 15 but for
/// `AttributedString`'s `subscript(_:)` with a selection, whose result is
/// Foundation's macOS 26 `DiscontiguousAttributedSubstring`.
public struct AttributedTextSelection: Equatable, Sendable {
    /// The selected indices of a text.
    @frozen public enum Indices: Equatable, Sendable {
        /// An insertion point: nothing selected, the caret at the index.
        case insertionPoint(AttributedString.Index)

        /// One or more selected ranges.
        case ranges(RangeSet<AttributedString.Index>)
    }

    /// The indices the selection was made with or last moved to, or `nil` for
    /// ``init()``'s, which is an insertion point at the end of whichever text
    /// it is read in.
    package var storedIndices: Indices?

    /// The attributes typing at the insertion point takes, where the app or a
    /// formatting change set them (``init(insertionPoint:typingAttributes:)``,
    /// ``Foundation/AttributedString/transformAttributes(in:body:)``), and only
    /// until the caret moves: a selection made anew has none (B-ATTRED-16).
    package var storedTypingAttributes: AttributeContainer?

    /// The side the caret leans to where a row wrapped (B-ATTRED-17).
    ///
    /// Upstream for a selection made outside the editor, as the macOS text
    /// system reports a caret the program set (TextKit 1 and 2, measured on
    /// macOS 15.8); the editor sets the lean its keys leave (`CaretLean`).
    package var lean: TextSelectionAffinity = .upstream

    /// Creates the default selection for a new text editor: an insertion point
    /// at the end of the text.
    public init() {}

    /// Creates a selection that is an insertion point.
    ///
    /// - Parameters:
    ///   - insertionPoint: Where the caret is.
    ///   - typingAttributes: The attributes text typed there takes, until the
    ///     caret moves; `nil` takes them from the text around it (see
    ///     ``typingAttributes(in:)``).
    public init(insertionPoint: AttributedString.Index, typingAttributes: AttributeContainer? = nil) {
        storedIndices = .insertionPoint(insertionPoint)
        storedTypingAttributes = typingAttributes
    }

    /// Creates a selection of several ranges.
    ///
    /// - Parameter ranges: The selected ranges.
    public init(ranges: RangeSet<AttributedString.Index>) {
        storedIndices = .ranges(ranges)
    }

    /// Creates a selection of one range; an empty range is an insertion point
    /// at its start.
    ///
    /// - Parameter range: The selected range.
    public init(range: Range<AttributedString.Index>) {
        storedIndices = range.isEmpty ? .insertionPoint(range.lowerBound) : .ranges(RangeSet(range))
    }

    /// The selection's indices in a text: its own where they are valid for
    /// `text`, and otherwise an insertion point at the text's end.
    ///
    /// Indices are valid for the text they were made from, or moved into by
    /// one of `AttributedString`'s selection-keeping changes. Validity is
    /// Foundation's `isValid(within:)` where Foundation has it; on macOS 15,
    /// indices are valid where they fall inside the text.
    ///
    /// - Parameter text: The text the selection is in.
    /// - Returns: The selected indices.
    public func indices(in text: AttributedString) -> Indices {
        switch storedIndices {
        case .insertionPoint(let index):
            if Self.isValid(index..<index, in: text) { return .insertionPoint(index) }
        case .ranges(let ranges):
            if !ranges.isEmpty, ranges.ranges.allSatisfy({ Self.isValid($0, in: text) }) { return .ranges(ranges) }
        case nil:
            break
        }
        return .insertionPoint(text.endIndex)
    }

    /// The side the caret leans to where its position is both the end of one
    /// row and the start of the next.
    ///
    /// Upstream for a selection made outside the editor, as the macOS text
    /// system reports a caret the program set; an editor reports the lean its
    /// keys leave, as ``TextSelectionAffinity`` describes.
    ///
    /// - Parameter text: The text the selection is in.
    /// - Returns: The selection's affinity.
    public func affinity(in text: AttributedString) -> TextSelectionAffinity {
        lean
    }

    /// The attributes text typed at the selection takes.
    ///
    /// Those given with the insertion point (or by
    /// ``Foundation/AttributedString/transformAttributes(in:body:)`` at it),
    /// until the caret moves. Otherwise the macOS text system's rule, measured
    /// on macOS 15.8 (B-ATTRED-16): the attributes of the character before the
    /// caret; at a paragraph's start, those of the paragraph's first character
    /// (its line break, if the paragraph is empty); at the text's start, those
    /// of its first character; over a selection, those of the selection's
    /// first character. An empty text has none.
    ///
    /// - Parameter text: The text the selection is in.
    /// - Returns: The typing attributes.
    public func typingAttributes(in text: AttributedString) -> AttributeContainer {
        if let storedTypingAttributes { return storedTypingAttributes }
        let characters = text.characters
        guard !characters.isEmpty else { return AttributeContainer() }
        switch indices(in: text) {
        case .ranges(let ranges):
            return Self.attributes(ofCharacterAt: ranges.ranges[0].lowerBound, in: text)
        case .insertionPoint(let caret):
            guard caret > text.startIndex else { return Self.attributes(ofCharacterAt: caret, in: text) }
            let before = characters.index(before: caret)
            if caret < text.endIndex, Self.separatesParagraphs(characters[before]) {
                return Self.attributes(ofCharacterAt: caret, in: text)
            }
            return Self.attributes(ofCharacterAt: before, in: text)
        }
    }

    /// The attributes the selection has in a text: each run's that is wholly
    /// or partly selected, in order, or the typing attributes alone for an
    /// insertion point.
    ///
    /// ```swift
    /// selection.attributes(in: text)[\.foregroundColor].contains(.red)
    /// ```
    ///
    /// - Parameter text: The text the selection is in.
    /// - Returns: A lazy sequence of the attributes.
    public func attributes(in text: AttributedString) -> Attributes<AttributedString> {
        switch indices(in: text) {
        case .insertionPoint:
            Attributes(text: text, ranges: [], typingAttributes: typingAttributes(in: text))
        case .ranges(let ranges):
            Attributes(text: text, ranges: Array(ranges.ranges), typingAttributes: nil)
        }
    }

    /// A sequence of the attribute values a selection has in a text — mirrors
    /// SwiftUI's `AttributedTextSelection.Attributes`.
    ///
    /// The attributes of each run that is wholly or partly selected, or the
    /// typing attributes for an insertion point. Subscript it with an
    /// attribute for that attribute's values alone:
    ///
    /// ```swift
    /// selection.attributes(in: text)[\.foregroundColor].contains(.red)
    /// ```
    public struct Attributes<Text>: Sequence {
        let text: AttributedString
        let ranges: [Range<AttributedString.Index>]
        let typingAttributes: AttributeContainer?

        public func makeIterator() -> some IteratorProtocol<AttributeContainer> {
            AttributedTextSelectionAttributesIterator(
                text: text, ranges: ranges[...], typingAttributes: typingAttributes)
        }

        /// The values of one attribute, by its key path, in the same order.
        public subscript<K>(type: KeyPath<AttributeDynamicLookup, K>) -> some Sequence<K.Value?>
        where K: AttributedStringKey, K.Value: Sendable {
            lazy.map { $0[K.self] }
        }

        /// The values of one attribute, by its key, in the same order.
        public subscript<K>(type: K.Type) -> some Sequence<K.Value?>
        where K: AttributedStringKey, K.Value: Sendable {
            lazy.map { $0[K.self] }
        }
    }
}

@available(*, unavailable)
extension AttributedTextSelection.Attributes: Sendable {}

// MARK: - Reading the text

extension AttributedTextSelection {
    /// The selection's ranges in `text`, and whether it is an insertion point,
    /// whose one range is empty: what the selection-keeping changes work on.
    package func resolvedRanges(in text: AttributedString) -> (ranges: [Range<AttributedString.Index>], isInsertion: Bool) {
        switch indices(in: text) {
        case .insertionPoint(let caret): ([caret..<caret], true)
        case .ranges(let ranges): (Array(ranges.ranges), false)
        }
    }

    /// Moves the selection to `ranges`, its ranges tracked through a change:
    /// an insertion point stays one, and ranges that all closed up become an
    /// insertion point at the first. Typing attributes stay only with an
    /// insertion point.
    package mutating func moveTo(tracked ranges: [Range<AttributedString.Index>], wasInsertion: Bool) {
        let set = wasInsertion ? RangeSet() : RangeSet(ranges)
        if set.isEmpty {
            storedIndices = .insertionPoint(ranges[0].lowerBound)
        } else {
            storedIndices = .ranges(set)
            storedTypingAttributes = nil
        }
    }

    /// Whether `range` is valid for `text`: Foundation's test where it has
    /// one, else whether the range falls inside the text.
    static func isValid(_ range: Range<AttributedString.Index>, in text: AttributedString) -> Bool {
        if #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
            return range.isValid(within: text)
        }
        return AttributedTextSelectionMacOS15Fallbacks.isInside(range, text)
    }

    /// The attributes of the character at `index`, which is before the end.
    static func attributes(ofCharacterAt index: AttributedString.Index, in text: AttributedString) -> AttributeContainer {
        let next = text.characters.index(after: index)
        return text[index..<next].runs.first?.attributes ?? AttributeContainer()
    }

    /// Whether a character ends a paragraph, as the macOS text system's
    /// paragraphs end: a line feed, a carriage return (either alone or the
    /// two together), U+2029 or U+0085.
    static func separatesParagraphs(_ character: Character) -> Bool {
        switch character {
        case "\n", "\r", "\r\n", "\u{2029}", "\u{85}": true
        default: false
        }
    }
}

/// Walks the runs of a selection's ranges, one container a run, or yields the
/// typing attributes once.
private struct AttributedTextSelectionAttributesIterator: IteratorProtocol {
    let text: AttributedString
    var ranges: ArraySlice<Range<AttributedString.Index>>
    var typingAttributes: AttributeContainer?
    var runs: AttributedString.Runs?
    var run: AttributedString.Runs.Index?

    init(text: AttributedString, ranges: ArraySlice<Range<AttributedString.Index>>, typingAttributes: AttributeContainer?) {
        self.text = text
        self.ranges = ranges
        self.typingAttributes = typingAttributes
    }

    mutating func next() -> AttributeContainer? {
        if let typing = typingAttributes {
            typingAttributes = nil
            return typing
        }
        while true {
            if let runs, let run, run < runs.endIndex {
                self.run = runs.index(after: run)
                return runs[run].attributes
            }
            guard let range = ranges.popFirst() else { return nil }
            let next = text[range].runs
            runs = next
            run = next.startIndex
        }
    }
}
