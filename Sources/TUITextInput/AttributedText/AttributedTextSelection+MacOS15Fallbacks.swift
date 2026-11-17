//  🖥️ TUI — A Terminal UI framework for Swift
//  AttributedTextSelection+MacOS15Fallbacks.swift
//
//  EVERY macOS 15 fallback of the attributed text selection, and nothing
//  else: what TUI does where macOS 15's Foundation lacks what macOS 26's,
//  Linux's and Windows' have. Dropping macOS 15 is deleting this file and the
//  `else` arms that call it (owner, 2026-11-17).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// What `AttributedTextSelection` and its `AttributedString` members do on
/// macOS 15, whose Foundation has no index validity (`isValid(within:)`), no
/// index tracking (`transform(updating:body:)`), no `removeSubranges(_:)` and
/// no UTF-8 view: all macOS 26 there, and in swift-foundation from Swift 6.2,
/// so Linux and Windows have them (the G3 design's L0 table).
///
/// Every member is called only from an `if #available(macOS 26, …)`'s `else`,
/// and builds everywhere, so a test runs it on any platform.
///
/// Positions are counted in Unicode scalars, where they must be counted:
/// macOS 15's `AttributedString` finds an index from a scalar or character
/// offset through its rope, in about a microsecond at the end of a 3 MB text
/// (measured on macOS 15.8.3, the G3 design's §9).
enum AttributedTextSelectionMacOS15Fallbacks {
    // MARK: Validity

    /// Approximates `Range.isValid(within:)`: whether the range falls inside
    /// the text.
    ///
    /// Foundation's test also rejects an index made from another text, or from
    /// this one before a change, which an index on macOS 15 does not record.
    /// So an index from elsewhere that happens to fall inside the text is
    /// taken as it is, though it may point anywhere in it, even inside a
    /// character. Cost: two comparisons.
    static func isInside(_ range: Range<AttributedString.Index>, _ text: AttributedString) -> Bool {
        range.lowerBound >= text.startIndex && range.upperBound <= text.endIndex
    }

    // MARK: Tracking a change

    /// Approximates `transform(updating:body:)` with index tracking: runs
    /// `body`, then finds what it changed as the one span between the
    /// longest common start and end of the text before and after, and moves
    /// `ranges` through that span by Foundation's rules (`TrackedSpan`).
    ///
    /// Exact for one contiguous change. Approximate when:
    /// - `body` makes several disjoint changes: they are taken as one span
    ///   from the first to the last, so a bound between them moves as if
    ///   inside a replaced range (it closes up to the span's start or end)
    ///   where Foundation would move it by the changes before it alone;
    /// - a change's text repeats its neighbours' (typing "a" beside an "a"):
    ///   the span is placed as late as the text allows, so a bound inside a
    ///   run of the repeated text may stay where Foundation would move it;
    /// - `body` replaces text with the same text: nothing changed is seen,
    ///   where Foundation would close a bound inside it up to its start.
    /// - `body` assigns a different text whole: Foundation loses track and
    ///   gives `nil`; this still compares the two texts and moves the bounds.
    ///
    /// Cost, beyond `body`: one copy of the text's storage made shared, so
    /// `body`'s first change copies the path it changes; the text before and
    /// after read into two `String`s; and one pass over their UTF-8 to find
    /// the common start and end and count scalars. 2.6 to 2.9 ms in all for
    /// one insert into a 3 MB document shaped as `bigtext`'s (macOS 15.8.3,
    /// -O; the design's §9), where Foundation's work is per change and bound.
    static func transform<E: Error>(
        _ text: inout AttributedString,
        updating ranges: [Range<AttributedString.Index>],
        body: (inout AttributedString) throws(E) -> Void
    ) throws(E) -> [Range<AttributedString.Index>] {
        let before = text
        let scalars = before.unicodeScalars
        let bounds = ranges.map { range in
            (scalars.distance(from: before.startIndex, to: range.lowerBound),
             scalars.distance(from: before.startIndex, to: range.upperBound))
        }
        try body(&text)
        let span = TrackedSpan(from: before, to: text)
        return bounds.map { lower, upper in
            let moved = span.track(lower: lower, upper: upper)
            return index(moved.lower, in: text)..<index(moved.upper, in: text)
        }
    }

    /// The one span a change replaced, in Unicode scalars: `start..<oldEnd` of
    /// the text before became `start..<newEnd` of the text after.
    struct TrackedSpan: Equatable {
        let start: Int
        let oldEnd: Int
        let newEnd: Int

        init(start: Int, oldEnd: Int, newEnd: Int) {
            self.start = start
            self.oldEnd = oldEnd
            self.newEnd = newEnd
        }

        /// The span between the longest common start and end of two texts,
        /// each ending on a character boundary in both.
        init(from before: AttributedString, to after: AttributedString) {
            // Foundation's slice initializer copies the rope's chunks: 0.6 ms
            // for 3 MB, where reading the character view one by one is ~700.
            var old = String(before.characters[before.startIndex..<before.endIndex])
            var new = String(after.characters[after.startIndex..<after.endIndex])
            let (prefix, suffix) = old.withUTF8 { oldBytes in
                new.withUTF8 { newBytes in Self.commonBytes(oldBytes, newBytes) }
            }
            var start = prefix
            while start > 0, !(Self.isBoundary(start, in: old) && Self.isBoundary(start, in: new)) { start -= 1 }
            var end = suffix
            while end > 0,
                !(Self.isBoundary(old.utf8.count - end, in: old) && Self.isBoundary(new.utf8.count - end, in: new))
            {
                end -= 1
            }
            let (startScalars, oldSpan, newSpan) = old.withUTF8 { oldBytes in
                new.withUTF8 { newBytes in
                    (Self.scalars(in: oldBytes[..<start]), Self.scalars(in: oldBytes[start..<(oldBytes.count - end)]),
                     Self.scalars(in: newBytes[start..<(newBytes.count - end)]))
                }
            }
            self.init(start: startScalars, oldEnd: startScalars + oldSpan, newEnd: startScalars + newSpan)
        }

        /// The lengths of the longest common start and the longest common end
        /// that does not overlap it, in bytes.
        private static func commonBytes(_ old: UnsafeBufferPointer<UInt8>, _ new: UnsafeBufferPointer<UInt8>) -> (Int, Int) {
            let shorter = min(old.count, new.count)
            var prefix = 0
            while prefix < shorter, old[prefix] == new[prefix] { prefix += 1 }
            var suffix = 0
            while suffix < shorter - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
            return (prefix, suffix)
        }

        /// Whether a UTF-8 offset is on a character boundary of `text`.
        private static func isBoundary(_ offset: Int, in text: String) -> Bool {
            text.utf8.index(text.utf8.startIndex, offsetBy: offset).samePosition(in: text) != nil
        }

        /// How many Unicode scalars some UTF-8 holds: its bytes that are not
        /// continuation bytes.
        private static func scalars(in bytes: Slice<UnsafeBufferPointer<UInt8>>) -> Int {
            bytes.reduce(0) { $0 + ($1 & 0xC0 == 0x80 ? 0 : 1) }
        }

        /// Where a range's bounds go, as Foundation's tracking moves them
        /// (swift-foundation's `AttributedString+IndexTracking.swift`): a
        /// bound inside the replaced span leaves it (a range wholly inside
        /// closes up at its start; a lower bound inside goes to its end, an
        /// upper bound to its start), then bounds after the span's start shift
        /// by the change in length; at the start, a lower bound shifts only
        /// past an insertion, and an upper bound with it.
        func track(lower: Int, upper: Int) -> (lower: Int, upper: Int) {
            var lower = lower
            var upper = upper
            let lowerInside = lower > start && lower < oldEnd
            let upperInside = upper > start && upper < oldEnd
            switch (lowerInside, upperInside) {
            case (true, true): (lower, upper) = (start, start)
            case (true, false): lower = oldEnd
            case (false, true): upper = start
            case (false, false): break
            }
            let delta = newEnd - oldEnd
            let movedLower = lower > start || (lower == start && start == oldEnd) ? lower + delta : lower
            let movedUpper = upper > start || movedLower != lower ? upper + delta : upper
            return (movedLower, movedUpper)
        }
    }

    // MARK: Changing the text

    /// Approximates `removeSubranges(_:)` then an insertion, with the caret
    /// found by offset: removes `ranges` (ascending, as a `RangeSet` holds
    /// them) from the last, inserts `newContent` where the first began, and
    /// gives the index after it.
    ///
    /// Exact, unlike ``transform(_:updating:body:)``: the change is known, so
    /// nothing is compared. Cost: a scalar offset to an index for each range's
    /// bounds and twice more, each through the rope (about a microsecond at
    /// 3 MB), and a count of `newContent`'s scalars.
    static func replace(
        _ ranges: [Range<AttributedString.Index>], in text: inout AttributedString,
        with newContent: some AttributedStringProtocol
    ) -> AttributedString.Index {
        let scalars = text.unicodeScalars
        let offsets = ranges.map {
            (scalars.distance(from: text.startIndex, to: $0.lowerBound),
             scalars.distance(from: text.startIndex, to: $0.upperBound))
        }
        for (lower, upper) in offsets.reversed() where lower < upper {
            text.removeSubrange(index(lower, in: text)..<index(upper, in: text))
        }
        let start = offsets[0].0
        text.insert(newContent, at: index(start, in: text))
        return index(start + newContent.unicodeScalars.count, in: text)
    }

    /// Sets each run's new attributes, and nothing else: the selection's
    /// indices are kept as they were, which is right on macOS 15, where an
    /// index is its offset and setting attributes moves no character. On
    /// macOS 26 the change is made under `transform(updating:body:)` instead,
    /// to renew the indices' validity. Cost: none beyond setting them.
    static func setAttributes(
        _ changes: [(range: Range<AttributedString.Index>, attributes: AttributeContainer)],
        in text: inout AttributedString
    ) {
        for change in changes { text[change.range].setAttributes(change.attributes) }
    }

    /// The index `offset` Unicode scalars into `text`.
    private static func index(_ offset: Int, in text: AttributedString) -> AttributedString.Index {
        text.unicodeScalars.index(text.startIndex, offsetBy: offset)
    }
}
