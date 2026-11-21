//  🖥️ TUI — A Terminal UI framework for Swift
//  FindMatchSet.swift
//
//  The find bar's matches in one text, found once for each query, options
//  and text, and carried through the editor's own edits by searching again
//  only the lines an edit touched: so a key with the bar up costs the edit
//  and the screen, not the document (TEXTIN-1).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// The find bar's matches of a query in one text, as UTF-8 offsets into it,
/// in order and never overlapping.
///
/// A match never spans a line break while the query has none, and where in
/// a line the matches fall depends on that line alone: a line's search
/// starts at a break, which no match takes in, and a word's edges are read
/// from the characters beside the match, the break included. So after an
/// edit only the lines it touched are searched again, and the matches either
/// side of them are kept, moved by what the edit put in. A query with a line
/// break in it is searched for whole after every edit.
struct FindMatchSet {
    let query: String
    let options: FindOptions
    /// The text the matches are of.
    let text: String
    /// The matches, as UTF-8 offsets into ``text``.
    let utf8: [Range<Int>]
    /// Made for this set alone: two sets with one identity are the same set,
    /// which is how the editor tells a set it has drawn from a new one
    /// without comparing the matches or the texts.
    let identity = Identity()

    /// What a set is told apart by (``identity``).
    final class Identity: Sendable {}

    /// The matches of `query` in all of `text`.
    init(query: String, options: FindOptions, text: String) {
        self.query = query
        self.options = options
        self.text = text
        utf8 = Self.search(query, options: options, in: text, bytes: 0..<text.utf8.count)
    }

    private init(query: String, options: FindOptions, text: String, utf8: [Range<Int>]) {
        (self.query, self.options, self.text, self.utf8) = (query, options, text, utf8)
    }

    var count: Int { utf8.count }
    var isEmpty: Bool { utf8.isEmpty }

    /// Whether these are the matches of `query` under `options` in `text`.
    func answers(_ query: String, options: FindOptions, in text: String) -> Bool {
        self.query == query && self.options == options && EditorMarkStore.isSameText(self.text, text)
    }

    /// The matches of `query` in the bytes `bytes` of `text`, which start and
    /// end on a character's edge: the search starts there, and a match's
    /// edges as a word are read from `text`'s characters either side.
    static func search(_ query: String, options: FindOptions, in text: String, bytes: Range<Int>) -> [Range<Int>] {
        let utf8 = text.utf8
        let lower = utf8.index(utf8.startIndex, offsetBy: bytes.lowerBound)
        let upper = utf8.index(utf8.startIndex, offsetBy: bytes.upperBound)
        return FindMatches.matches(of: query, in: text, options: options, within: lower..<upper).map {
            utf8.distance(from: utf8.startIndex, to: $0.lowerBound)..<utf8.distance(from: utf8.startIndex, to: $0.upperBound)
        }
    }

    /// These matches carried through `edit`, made to ``text``, which left
    /// `layout`'s text: the lines the edit put in are searched again and the
    /// rest moved by it.
    func carried(through edit: EditorMarkEdit, to layout: EditorLayout) -> Self {
        let after = layout.text
        guard !query.contains(where: \.isNewline) else {
            return Self(query: query, options: options, text: after)
        }
        let starts = layout.lineStarts
        let total = after.utf8.count
        // Every line the edit's new bytes touch, whole, breaks included.
        let first = layout.line(containingUTF8Offset: edit.start)
        let last = layout.line(containingUTF8Offset: max(edit.start, edit.newEnd))
        let region = starts[first]..<(last + 1 < starts.count ? starts[last + 1] : total)
        let shift = edit.newEnd - edit.oldEnd
        // The same lines in the text before: they start where they did, and
        // end where they did, moved by what the edit put in.
        let oldEnd = region.upperBound - shift
        var carried: [Range<Int>] = []
        carried.reserveCapacity(utf8.count + 1)
        let before = Self.firstIndex(in: utf8, endingAfter: region.lowerBound)
        carried += utf8[..<before]
        carried += Self.search(query, options: options, in: after, bytes: region)
        let kept = Self.firstIndex(in: utf8, startingAtOrAfter: oldEnd)
        for match in utf8[kept...] { carried.append((match.lowerBound + shift)..<(match.upperBound + shift)) }
        return Self(query: query, options: options, text: after, utf8: carried)
    }

    /// The matches that reach into `bytes`, as offsets into ``text``.
    func matches(touching bytes: Range<Int>) -> ArraySlice<Range<Int>> {
        let lower = Self.firstIndex(in: utf8, endingAfter: bytes.lowerBound)
        var upper = lower
        while upper < utf8.count, utf8[upper].lowerBound < bytes.upperBound { upper += 1 }
        return utf8[lower..<upper]
    }

    /// The first match in `matches` that ends after `offset`.
    static func firstIndex(in matches: [Range<Int>], endingAfter offset: Int) -> Int {
        var (low, high) = (0, matches.count)
        while low < high {
            let middle = (low + high) / 2
            if matches[middle].upperBound <= offset { low = middle + 1 } else { high = middle }
        }
        return low
    }

    /// The first match in `matches` that starts at or after `offset`.
    static func firstIndex(in matches: [Range<Int>], startingAtOrAfter offset: Int) -> Int {
        var (low, high) = (0, matches.count)
        while low < high {
            let middle = (low + high) / 2
            if matches[middle].lowerBound < offset { low = middle + 1 } else { high = middle }
        }
        return low
    }

    /// Match `index` as character offsets into ``text``: found through
    /// `layout` where it is of the same text, a walk of its line; else by
    /// walking the text.
    func characterOffsets(of index: Int, layout: EditorLayout?) -> Range<Int> {
        let match = utf8[index]
        let view = text.utf8
        let lower = view.index(view.startIndex, offsetBy: match.lowerBound)
        let upper = view.index(view.startIndex, offsetBy: match.upperBound)
        if let layout, EditorMarkStore.isSameText(layout.text, text) {
            return layout.offset(of: lower, in: text)..<layout.offset(of: upper, in: text)
        }
        let start = text.distance(from: text.startIndex, to: lower)
        return start..<(start + text.distance(from: lower, to: upper))
    }
}

/// What an editor's find bar is looking for, while it is up, and where it
/// keeps what it found.
struct FindRequest {
    let query: String
    let options: FindOptions
    let cache: FindMatchCache
}

/// Where an editor's find bar keeps its matches: found once for a query,
/// its options and a text, whoever asks (the bar's count, the editor's
/// tints, Ctrl-G), and carried by the editor through each of its own edits
/// (``carry(_:from:to:)``), so the bar's next question about the edited text
/// is answered without a search.
///
/// A reference, held by the editor's `@State` and lent to its handler while
/// the bar is up: the handler makes the edits, the bar asks the questions.
final class FindMatchCache {
    nonisolated init() {}

    /// The matches last found or carried.
    private(set) var current: FindMatchSet?

    /// How many times the whole of a text has been searched: the test seam
    /// that counts what a key costs with the bar up.
    private(set) var searches = 0

    /// The matches of `query` under `options` in `text`: the ones kept, while
    /// they are of that text and that query, else found afresh.
    func matches(of query: String, options: FindOptions, in text: String) -> FindMatchSet {
        if let current, current.answers(query, options: options, in: text) { return current }
        let found = FindMatchSet(query: query, options: options, text: text)
        searches += 1
        current = found
        return found
    }

    /// Whether the matches kept are of `layout`'s text, so an edit made from
    /// it carries them (``carry(_:to:)``). Asked before the edit is laid out,
    /// while `layout` still has its text.
    func carries(from layout: EditorLayout) -> Bool {
        current.map { EditorMarkStore.isSameText($0.text, layout.text) } ?? false
    }

    /// Carries the matches kept through `edit`, which left `layout`'s text:
    /// the lines it touched searched again, the rest moved.
    func carry(_ edit: EditorMarkEdit, to layout: EditorLayout) {
        current = current?.carried(through: edit, to: layout)
    }
}
