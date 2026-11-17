//  🖥️ TUI — A Terminal UI framework for Swift
//  TableOutlineSplice.swift
//
//  A kept outline made again for a change of its open branches by splicing:
//  the rows beneath each branch that opened or closed put in or taken out,
//  and the rest kept, rather than the whole tree flattened again — so opening
//  one branch of a big open tree costs that branch's rows (finding M6-2, from
//  tuitree).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation

// MARK: - The rows by id, across splices

/// One change to an outline's rows: the `removed` rows from `start` taken out
/// and `inserted` rows put in their place, `start` counted in the rows as the
/// splices before it left them.
///
/// Not nested in the generic index, for the reason ``_TableOutlineRow`` is not:
/// a lookup replays these, and replaying them is then integer work.
struct _TableOutlineSplice {
    let start: Int
    let removed: Int
    let inserted: Int

    /// Where the row at `row` is after `splices`, in order: a row before a
    /// splice stays, a row after it moves by what it put in less what it took
    /// out. Never a row it took out, which the index forgets.
    static func replay(_ splices: ArraySlice<Self>, from row: Int) -> Int {
        var row = row
        for splice in splices where row >= splice.start + splice.removed {
            row += splice.inserted - splice.removed
        }
        return row
    }
}

/// A row's index when an outline's index noted it, and how many splices had
/// been noted by then.
struct _TableOutlineIndexEntry {
    let row: Int
    let since: Int
}

/// A kept outline's rows by id: each row's index when it was noted, and the
/// splices made since, which a lookup replays to find where the row is now.
///
/// What lets an outline made by splicing keep its predecessor's index rather
/// than list every row's id again: a splice moves every row after it, and
/// noting them all would cost what flattening the tree again does. A lookup
/// replays the splices made since its row was noted instead, a comparison
/// each, and once lookups have replayed more splices than there are rows the
/// index is made again (``isWorn``), so a lookup costs at most about twice
/// what it would in an index made fresh.
struct _TableOutlineRowIndex<Value: Identifiable> {
    private var entries: [Value.ID: _TableOutlineIndexEntry]
    private var splices: [_TableOutlineSplice] = []

    /// The splices lookups have replayed since the entries were made.
    private var replayed = 0

    /// Whether two rows share an id, which SwiftUI's rows may not. The later
    /// one answers, as it always has, and an outline with such rows is made
    /// again whole on a change: a splice could not tell which of them it moved.
    private(set) var hasSharedIDs = false

    /// The index of `values`, every row noted.
    init(_ values: [Value]) {
        var entries = [Value.ID: _TableOutlineIndexEntry](minimumCapacity: values.count)
        var shared = false
        for index in values.indices {
            let previous = entries.updateValue(_TableOutlineIndexEntry(row: index, since: 0), forKey: values[index].id)
            shared = shared || previous != nil
        }
        self.entries = entries
        hasSharedIDs = shared
    }

    /// Whether lookups have spent more replaying splices than making the
    /// index again would cost, or the splices have piled up: then the outline
    /// makes it again.
    var isWorn: Bool {
        replayed > entries.count + 256 || splices.count > 1024
    }

    /// Where the row `id` names is now, or `nil` for a row not shown.
    mutating func row(of id: Value.ID) -> Int? {
        guard let entry = entries[id] else { return nil }
        guard entry.since < splices.count else { return entry.row }
        replayed += splices.count - entry.since
        return _TableOutlineSplice.replay(splices[entry.since...], from: entry.row)
    }

    /// Forgets the row `id` names: a splice took it out.
    mutating func remove(_ id: Value.ID) {
        entries[id] = nil
    }

    /// Notes a splice, after the one noted before it.
    mutating func note(_ splice: _TableOutlineSplice) {
        splices.append(splice)
    }

    /// Notes a row a change's splices put in, at `row`, where it is once all
    /// of them are noted. `false` where a row shown already has its id.
    mutating func insert(_ id: Value.ID, at row: Int) -> Bool {
        entries.updateValue(_TableOutlineIndexEntry(row: row, since: splices.count), forKey: id) == nil
    }
}

// MARK: - The rows' places, across splices

/// The next outline's rows, made from a kept one's in reading order: runs of
/// rows kept, their parent links moved to where their parents now are, and
/// between them the branches that open or close, with the rows put in beneath
/// them or the rows taken out.
///
/// Not generic, so the work for every kept row — a copy and a parent link
/// moved — is plain integer work, where a merge generic over the rows' values
/// looked up its row type's metadata for each one (two thirds of a toggle's
/// time, measured). The values and branch nodes, which are the app's type, are
/// copied in bulk beside it (``_TableOutline/splicing(_:to:expansion:)``).
struct _TableOutlineRowMerge {
    private(set) var rows: [_TableOutlineRow] = []
    /// The first old row not yet copied or taken out.
    private(set) var copied = 0
    /// The rows put in or taken out.
    private(set) var listed = 0
    /// The branches among the rows taken out.
    private(set) var branchesTakenOut = 0
    /// Where each run of the old rows went: those from `start` on, until the
    /// next run, moved by `delta`.
    private var runs: [(start: Int, delta: Int)] = [(0, 0)]
    private var delta = 0

    init(capacity: Int) {
        rows.reserveCapacity(capacity)
    }

    /// Where the old row `old`, kept, now is. A parent is always before its
    /// rows, and most often in the same run.
    private func moved(_ old: Int) -> Int {
        if old >= runs[runs.count - 1].start { return old + delta }
        var low = 0
        var high = runs.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if runs[middle].start <= old { low = middle } else { high = middle - 1 }
        }
        return old + runs[low].delta
    }

    /// Copies the old rows `range`, unchanged but for where their parents are.
    mutating func keep(_ range: Range<Int>, of old: [_TableOutlineRow]) {
        for index in range {
            let row = old[index]
            rows.append(
                _TableOutlineRow(
                    placement: row.placement, parent: row.parent < 0 ? -1 : moved(row.parent), branch: row.branch))
        }
        copied = max(copied, range.upperBound)
    }

    /// Copies the old rows up to the branch `toggle`, then the branch with
    /// its triangle turned; returns where it now is.
    mutating func turn(_ toggle: Int, of old: [_TableOutlineRow]) -> Int {
        keep(copied..<toggle, of: old)
        let row = old[toggle]
        let disclosure: _TableOutlineDisclosure = row.placement.disclosure == .open ? .closed : .open
        rows.append(
            _TableOutlineRow(
                placement: _TableOutlinePlacement(depth: row.placement.depth, disclosure: disclosure),
                parent: row.parent < 0 ? -1 : moved(row.parent), branch: row.branch))
        copied = toggle + 1
        return rows.count - 1
    }

    /// Puts `beneath` in after the branch just turned open, now at `at`: the
    /// rows a flattening of the branch as a tree of one root listed after it,
    /// their depths and links made the outline's — a local parent 0 is the
    /// branch, and a local branch `b` is `branchBase + b`.
    mutating func put(_ beneath: ArraySlice<_TableOutlineRow>, at: Int, depth: Int, branchBase: Int) {
        for row in beneath {
            rows.append(
                _TableOutlineRow(
                    placement: _TableOutlinePlacement(
                        depth: row.placement.depth + depth, disclosure: row.placement.disclosure),
                    parent: at + row.parent, branch: row.branch < 0 ? -1 : branchBase + row.branch))
        }
        delta += beneath.count
        listed += beneath.count
        runs.append((copied, delta))
    }

    /// Leaves out the old rows beneath the branch just turned closed, the old
    /// row `toggle`; returns them.
    mutating func takeOut(beneath toggle: Int, of old: [_TableOutlineRow]) -> Range<Int> {
        let depth = old[toggle].placement.depth
        var end = toggle + 1
        while end < old.count, old[end].placement.depth > depth {
            if old[end].branch >= 0 { branchesTakenOut += 1 }
            end += 1
        }
        let removed = end - toggle - 1
        delta -= removed
        listed += removed
        copied = end
        runs.append((copied, delta))
        return (toggle + 1)..<end
    }
}

// MARK: - Splicing

extension _TableOutline {
    /// What a change to the open branches makes of a kept outline.
    enum Splicing {
        /// No row shown opens or closes: the outline shows the change as it is.
        case unchanged
        /// The outline with each changed branch's rows spliced in or out, and
        /// how many rows that put in or took out.
        case spliced(_TableOutline, listed: Int)
    }

    /// This outline with the branches `ids` name opened or closed as
    /// `reading` says: the rows beneath each put in, flattened as a full
    /// flattening would, or taken out, and every other row kept, its links
    /// moved to where it now is. `nil` where splicing cannot be trusted to
    /// make what flattening the tree would — rows that share an id, or rows
    /// with traits or loops among them, which a `Table(_:children:)` has
    /// none of — or where the nodes of branches taken out have piled up, and
    /// the outline is made again whole.
    ///
    /// The ids are those whose membership of the open branches changed, in
    /// any order. Only the shown ones whose triangle no longer says what
    /// `reading` does are turned, in reading order, so a branch opened with a
    /// closed one beneath it, or closed with open ones, is spliced once: the
    /// rows put in are flattened with `reading`, and the rows taken out take
    /// the changed ones beneath them with them.
    ///
    /// What it costs: the rows put in or taken out, and a copy of the rows
    /// kept, values and places — a copy, not a flattening: no row is built,
    /// no branch asked whether it is open, and no id listed.
    ///
    /// For a tree whose branches are opened through the table's own
    /// expansion alone: a branch's own binding (`DisclosureTableRow`) is not
    /// in `reading`, and its change would be missed. The kept outline of a
    /// `Table(_:children:)`, the only caller, has none.
    func splicing(
        _ ids: [Value.ID], to reading: _TableOutlineExpansion<Value>.Reading,
        expansion: _TableOutlineExpansion<Value>
    ) -> Splicing? {
        guard traits == nil, insertionAction == nil else { return nil }
        if rowIndices?.isWorn ?? true { rowIndices = _TableOutlineRowIndex(values) }
        guard var index = rowIndices, !index.hasSharedIDs else { return nil }
        var toggles: [Int] = []
        for id in ids {
            guard let row = index.row(of: id), rows[row].branch >= 0 else { continue }
            let isOpen = rows[row].placement.disclosure == .open
            if isOpen != Self.isOpen(branchNodes[rows[row].branch], in: reading) { toggles.append(row) }
        }
        guard !toggles.isEmpty else {
            rowIndices = index
            return .unchanged
        }
        toggles.sort()
        // Taken, not shared: the next outline keeps it, and this one, should
        // anything still ask it, makes its own again.
        rowIndices = nil
        var merge = _TableOutlineRowMerge(capacity: rows.count)
        var newValues: [Value] = []
        newValues.reserveCapacity(values.count)
        // Kept in place, so a kept row's branch is where it was: a branch
        // taken out leaves its node behind (``garbageBranches``).
        var newBranches = branchNodes
        var inserted: [(Value.ID, Int)] = []
        for toggle in toggles where toggle >= merge.copied {
            newValues += values[merge.copied...toggle]
            let at = merge.turn(toggle, of: rows)
            if rows[toggle].placement.disclosure != .open {
                // The branch and its rows, as a tree of one root: what a full
                // flattening lists beneath it.
                let beneath = Self.flattening(
                    _TableRowBranch(nodes: [branchNodes[rows[toggle].branch]]), expansion: reading)
                guard !beneath.anyTraits, beneath.insertionAction == nil else { return nil }
                // Its local branch 0 is the branch itself, listed already.
                merge.put(
                    beneath.rows.dropFirst(), at: at, depth: rows[toggle].placement.depth,
                    branchBase: newBranches.count - 1)
                newBranches += beneath.branchNodes.dropFirst()
                newValues += beneath.values.dropFirst()
                for local in beneath.values.indices.dropFirst() {
                    inserted.append((beneath.values[local].id, at + local))
                }
                index.note(_TableOutlineSplice(start: at + 1, removed: 0, inserted: beneath.values.count - 1))
            } else {
                let gone = merge.takeOut(beneath: toggle, of: rows)
                for old in gone { index.remove(values[old].id) }
                index.note(_TableOutlineSplice(start: at + 1, removed: gone.count, inserted: 0))
            }
        }
        newValues += values[merge.copied...]
        merge.keep(merge.copied..<rows.count, of: rows)
        let garbage = garbageBranches + merge.branchesTakenOut
        guard garbage <= newBranches.count / 2 + 1024 else { return nil }
        var flat = Flattening()
        flat.values = newValues
        flat.rows = merge.rows
        flat.branchNodes = newBranches
        let made = _TableOutline(flat, expansion: expansion)
        made.garbageBranches = garbage
        var intact = true
        for (id, row) in inserted where !index.insert(id, at: row) { intact = false }
        made.rowIndices = intact ? index : nil
        return .spliced(made, listed: merge.listed)
    }
}
