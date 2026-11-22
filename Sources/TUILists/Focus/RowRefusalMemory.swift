//  🖥️ TUI — A Terminal UI framework for Swift
//  RowRefusalMemory.swift
//
//  What a list's rows refused — `.deleteDisabled()`, `.moveDisabled()`,
//  `.selectionDisabled()` — kept from frame to frame by row id.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// What a list keeps a row's refusals under from one frame to the next: its
/// row id where it has one, which follows the row wherever the data moves it,
/// and otherwise its place, which is all a row the selection cannot name has.
enum RowRefusalKey: Hashable {
    /// A row with a row id (its selection value).
    case id(AnyHashable)
    /// A row with none, at this list row.
    case place(Int)
}

/// The refusals a `List`'s rows reported as they drew, kept across frames by
/// row id (owner ruling O-04, 2026-11-21), so that only a row no frame has
/// drawn is unknown.
///
/// A row reports what it refuses only as it renders (``RowEditRestrictions``
/// explains why it cannot be read off the row's structure), and the list
/// draws only its window. Rebuilt from each frame's rows alone, the list
/// forgot a locked row the moment it scrolled away: Delete removed a
/// `.deleteDisabled()` row whose cursor row had been wheeled out of sight, and
/// Select All selected the `.selectionDisabled()` rows off screen (hunt
/// findings LISTS-1 and LISTS-2). Kept here, a refusal stands until its row
/// draws again without reporting it, or leaves the data.
///
/// Only refusing rows are kept, so a list whose rows refuse nothing keeps
/// nothing and pays nothing for it.
struct RowRefusalMemory {
    /// Each refusing row, by key, with the list row it was last found at.
    private var entries: [RowRefusalKey: (row: Int, refusals: RowRefusals)] = [:]

    /// The row count of the frame last settled: a row kept by its place is
    /// another row once the count changes.
    private var rowCount = 0

    /// The list rows refusing deletion.
    private(set) var deleteDisabled: Set<Int> = []
    /// The list rows refusing to be moved.
    private(set) var moveDisabled: Set<Int> = []
    /// The list rows refusing to be selected.
    private(set) var selectionDisabled: Set<Int> = []

    /// Whether a refusal is kept under `key`: what lets a bulk key skip a row
    /// it already knows refuses.
    func keeps(_ key: RowRefusalKey) -> Bool { entries[key] != nil }

    /// Settles what is known after a frame: each kept row is found again among
    /// `count` rows (by its key, where the data moved it) or dropped with the
    /// data that held it; a kept row that `hasRendered` without a report is
    /// forgotten; and every row that reported is kept with what it reported.
    ///
    /// - Parameters:
    ///   - count: The frame's row count.
    ///   - reports: What the rows that drew reported, by list row.
    ///   - keyAt: The key of the row at a list row.
    ///   - hasRendered: Whether the row at a list row drew this frame.
    mutating func settle(
        count: Int, reports: [Int: RowRefusals], keyAt: (Int) -> RowRefusalKey, hasRendered: (Int) -> Bool
    ) {
        defer { rowCount = count }
        // The list that refuses nothing, which is nearly every list: nothing
        // to find, nothing to drop.
        guard !entries.isEmpty || !reports.isEmpty else { return }
        if count != rowCount { entries = entries.filter { if case .place = $0.key { false } else { true } } }
        relocate(count: count, keyAt: keyAt)
        for (key, entry) in entries where reports[entry.row] == nil && hasRendered(entry.row) {
            entries[key] = nil
        }
        for (row, refusals) in reports { entries[keyAt(row)] = (row, refusals) }
        publish()
    }

    /// Keeps what the row at `row`, keyed `key`, was just found to refuse —
    /// by a probe the key that acts on it asked for — or forgets it, where it
    /// refuses nothing. The sets change only at the ``publish()`` that
    /// follows: a key learns thousands of rows at once.
    mutating func learn(_ refusals: RowRefusals, key: RowRefusalKey, row: Int) {
        entries[key] = refusals.isEmpty ? nil : (row, refusals)
    }

    /// Finds each kept row whose key no longer names the row it was at,
    /// in one walk of the rows, and drops the ones the data no longer holds.
    private mutating func relocate(count: Int, keyAt: (Int) -> RowRefusalKey) {
        var lost = Set(entries.compactMap { key, entry in entry.row < count && keyAt(entry.row) == key ? nil : key })
        guard !lost.isEmpty else { return }
        var found: [RowRefusalKey: Int] = [:]
        for row in 0..<count {
            let key = keyAt(row)
            guard lost.remove(key) != nil else { continue }
            found[key] = row
            if lost.isEmpty { break }
        }
        for key in lost { entries[key] = nil }
        for (key, row) in found { entries[key]?.row = row }
    }

    /// The three sets the handler reads, from the kept rows.
    mutating func publish() {
        var delete = Set<Int>()
        var move = Set<Int>()
        var selection = Set<Int>()
        for entry in entries.values {
            if entry.refusals.contains(.delete) { delete.insert(entry.row) }
            if entry.refusals.contains(.move) { move.insert(entry.row) }
            if entry.refusals.contains(.selection) { selection.insert(entry.row) }
        }
        (deleteDisabled, moveDisabled, selectionDisabled) = (delete, move, selection)
    }
}
