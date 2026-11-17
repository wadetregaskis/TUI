//  🖥️ TUI — A Terminal UI framework for Swift
//  AttributedString+AttributedTextSelection.swift
//
//  SwiftUI's five members of `AttributedString` that read or change the text
//  at an `AttributedTextSelection` and keep the selection in step with it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

extension AttributedString {
    /// Changes the text, moving a selection with the characters it selects —
    /// mirrors SwiftUI's `transform(updating:body:)`.
    ///
    /// Make every change through the text `body` is given, not by assigning
    /// `self` from inside it. A selection in text the change removed closes up
    /// at the change's start; one that only reached into it keeps the rest; an
    /// insertion point where text was inserted ends up after it.
    ///
    /// On macOS 26 and later, and on Linux and Windows, Foundation tracks the
    /// selection through each change `body` makes (its own
    /// `transform(updating:body:)`); a body that replaced the text whole, which
    /// it cannot track, leaves the selection as it was, for
    /// ``AttributedTextSelection/indices(in:)`` to answer with its fallback.
    /// macOS 15's Foundation cannot track, and there the change is found by
    /// comparing the text before `body` and after: exact for one contiguous
    /// change, approximate for several (see
    /// `AttributedTextSelection+MacOS15Fallbacks.swift`).
    ///
    /// - Parameters:
    ///   - selection: The selection to keep in step with the text.
    ///   - body: The change, made to the text it is given.
    public mutating func transform<E>(
        updating selection: inout AttributedTextSelection,
        body: (inout AttributedString) throws(E) -> Void
    ) throws(E) where E: Error {
        let resolved = selection.resolvedRanges(in: self)
        let tracked: [Range<Index>]?
        if #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
            tracked = try transform(updating: resolved.ranges, body: body)
        } else {
            tracked = try AttributedTextSelectionMacOS15Fallbacks.transform(
                &self, updating: resolved.ranges, body: body)
        }
        guard let tracked else { return }
        selection.moveTo(tracked: tracked, wasInsertion: resolved.isInsertion)
    }

    /// The selected text — mirrors SwiftUI's `subscript(_:)` with a
    /// selection.
    ///
    /// Empty for an insertion point. Foundation's
    /// `DiscontiguousAttributedSubstring` is macOS 26 on Apple platforms, so this
    /// is too, as SwiftUI's is.
    ///
    /// - Parameter selection: The selection.
    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    public subscript(selection: AttributedTextSelection) -> DiscontiguousAttributedSubstring {
        switch selection.indices(in: self) {
        case .insertionPoint: self[RangeSet<Index>()]
        case .ranges(let ranges): self[ranges]
        }
    }

    /// Changes the attributes at a selection — mirrors SwiftUI's
    /// `transformAttributes(in:body:)`.
    ///
    /// Over selected text, `body` is given each selected run's attributes in
    /// turn, and what it leaves becomes that run's. At an insertion point it is
    /// given the typing attributes, and what it leaves is typed there until the
    /// caret moves. A `body` that throws changes nothing.
    ///
    /// - Parameters:
    ///   - selection: The selection, kept in step with the text.
    ///   - body: The change, made to one run's attributes.
    public mutating func transformAttributes<E>(
        in selection: inout AttributedTextSelection,
        body: (inout AttributeContainer) throws(E) -> Void
    ) throws(E) where E: Error {
        let resolved = selection.resolvedRanges(in: self)
        if resolved.isInsertion {
            var typing = selection.typingAttributes(in: self)
            try body(&typing)
            selection.storedTypingAttributes = typing
            return
        }
        // Every run's new attributes before any is set, so a throw sets none.
        var changes: [(range: Range<Index>, attributes: AttributeContainer)] = []
        for range in resolved.ranges {
            for run in self[range].runs {
                var attributes = run.attributes
                try body(&attributes)
                changes.append((run.range, attributes))
            }
        }
        if #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
            // Setting attributes moves no character, so the ranges read before
            // stay right; tracking renews the selection's indices for the text.
            let tracked = transform(updating: resolved.ranges) { text in
                for change in changes { text[change.range].setAttributes(change.attributes) }
            }
            if let tracked { selection.moveTo(tracked: tracked, wasInsertion: false) }
        } else {
            AttributedTextSelectionMacOS15Fallbacks.setAttributes(changes, in: &self)
        }
    }

    /// Replaces the selected text with characters, which take the selection's
    /// typing attributes — mirrors SwiftUI's
    /// `replaceSelection(_:withCharacters:)`.
    ///
    /// The selection becomes an insertion point after the new characters.
    ///
    /// - Parameters:
    ///   - selection: The selection to replace, and then the caret after it.
    ///   - newContent: The characters.
    public mutating func replaceSelection(
        _ selection: inout AttributedTextSelection, withCharacters newContent: some Collection<Character>
    ) {
        let content = AttributedString(String(newContent), attributes: selection.typingAttributes(in: self))
        replaceSelection(&selection, with: content)
    }

    /// Replaces the selected text with attributed text, which keeps its own
    /// attributes — mirrors SwiftUI's `replaceSelection(_:with:)`.
    ///
    /// Every selected range is removed and the new text put where the first
    /// began; the selection becomes an insertion point after it.
    ///
    /// - Parameters:
    ///   - selection: The selection to replace, and then the caret after it.
    ///   - newContent: The attributed text.
    public mutating func replaceSelection(
        _ selection: inout AttributedTextSelection, with newContent: some AttributedStringProtocol
    ) {
        let resolved = selection.resolvedRanges(in: self)
        let caret: Index
        if #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
            caret = replacing(resolved.ranges, isInsertion: resolved.isInsertion, with: newContent)
        } else {
            caret = AttributedTextSelectionMacOS15Fallbacks.replace(resolved.ranges, in: &self, with: newContent)
        }
        // A new caret, with no typing attributes, leaning upstream as an edit
        // leaves it (`CaretLean`).
        selection = AttributedTextSelection(insertionPoint: caret)
    }

    /// Removes `ranges` and inserts `newContent` where the first began,
    /// Foundation tracking the caret: it stays put while text after it goes,
    /// and then moves past the text inserted at it.
    ///
    /// - Returns: The caret after the inserted text.
    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    private mutating func replacing(
        _ ranges: [Range<Index>], isInsertion: Bool, with newContent: some AttributedStringProtocol
    ) -> Index {
        var caret = ranges[0].lowerBound..<ranges[0].lowerBound
        if !isInsertion {
            let removed = RangeSet(ranges)
            caret = transform(updating: caret) { $0.removeSubranges(removed) } ?? caret
        }
        let position = caret.lowerBound
        caret = transform(updating: caret) { $0.insert(newContent, at: position) } ?? caret
        return caret.lowerBound
    }
}
