//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListRowEditOwner.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// The `ForEach` that owns a run of a `List`'s rows, and where that run sits
/// in the list's own row numbering.
///
/// A row's `.onDelete` / `.onMove` belong to the `ForEach` that produced the
/// row — SwiftUI's rule, and the only one under which an offset names a real
/// element — and the offsets those actions take are indices into THAT
/// `ForEach`'s data. In a flat `List { ForEach … }` the two numberings are the
/// same number and the distinction never shows. Inside a `Section` they differ
/// by everything drawn before the section's first item: the section's header,
/// and every row of every earlier section. ``rows``'s `lowerBound` IS that
/// difference — the list row at which the collection's element 0 is drawn.
///
/// One owner per editable `ForEach`, and its rows are contiguous by
/// construction (a `ForEach` draws its elements in order), which is what lets
/// a span stand in for the whole mapping — with ``elements`` saying which
/// element each row draws, for a loop whose rows are several views each
/// (decisions B15): a delete on any of an element's rows removes that element,
/// as SwiftUI's does (measured on macOS 15.8, `D1S/probe2/listdel`: the second
/// view of an element selected, `delete:` hands `.onDelete` that element's
/// offset and both of its rows go).
struct ListRowEditOwner {
    /// The actions the owning `ForEach` carries.
    let actions: any DynamicViewContentActions

    /// The list rows its elements occupy — `row - rows.lowerBound` is a row's
    /// place among them, which ``elements`` maps to the element it draws.
    let rows: Range<Int>

    /// Which element each of ``rows`` draws.
    var elements: ListRowElements = .onePerRow

    /// The offset in the loop's collection of the element row `row` draws.
    func elementOffset(ofRow row: Int) -> Int {
        let place = row - rows.lowerBound
        switch elements {
        case .onePerRow: return place
        case .perElement(let count): return place / max(1, count)
        case .listed(let offsets, _): return offsets[place]
        }
    }

    /// The offsets of the elements `rows` draw, each once — the rows outside
    /// this owner's span left out, as an offset into another collection would
    /// be wrong.
    func elementOffsets(ofRows rows: some Sequence<Int>) -> IndexSet {
        IndexSet(rows.filter { self.rows.contains($0) }.map(elementOffset(ofRow:)))
    }

    /// Whether every element draws exactly one row, so a row's place IS its
    /// element's offset, and a row moves alone.
    var isOneRowPerElement: Bool {
        if case .onePerRow = elements { return true }
        return false
    }

    /// The list rows the element drawn at `row` draws — the rows a reorder
    /// moves together.
    func rowsOfElement(drawnAt row: Int) -> Range<Int> {
        let place = row - rows.lowerBound
        switch elements {
        case .onePerRow:
            return row..<(row + 1)
        case .perElement(let count):
            let first = rows.lowerBound + place / max(1, count) * max(1, count)
            return first..<min(rows.upperBound, first + max(1, count))
        case .listed(let offsets, _):
            let element = offsets[place]
            var first = place
            while first > 0, offsets[first - 1] == element { first -= 1 }
            var end = place + 1
            while end < offsets.count, offsets[end] == element { end += 1 }
            return (rows.lowerBound + first)..<(rows.lowerBound + end)
        }
    }

    /// The offset `.onMove` lands its elements at for a reorder slot before
    /// list row `row` — the element drawn there, or one past the last element
    /// for a slot past the owner's last row. Measured, as `.onMove`'s
    /// destination is, against the collection before the move.
    func elementInsertionOffset(beforeRow row: Int) -> Int {
        guard row < rows.upperBound else { return elementCount }
        return elementOffset(ofRow: max(rows.lowerBound, row))
    }

    /// How many elements the owning loop iterates — those that draw no row
    /// too, for a loop whose rows vary.
    var elementCount: Int {
        switch elements {
        case .onePerRow: return rows.count
        case .perElement(let count): return rows.count / max(1, count)
        case .listed(_, let count): return count
        }
    }
}
