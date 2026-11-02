//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollPlanner.swift
//
//  Deciding whether a frame is cheaper as a moved band of rows and a repair than
//  as the rows it changed. A PROTOTYPE, off by default: see
//  `Documentation/Performance/Scroll regions for output.md`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

// MARK: - The switch

/// How far the writer may go in moving rows rather than rewriting them.
/// `TUI_SCROLL_OUTPUT`: `off` (the default), `exact`, `residue` or `margins`.
/// Each level includes the one before it.
enum ScrollOutput: Int, Comparable, Sendable {
    /// Rows are written where they are, as they always have been.
    case off
    /// A whole-width band (`CSI t;b r`, `CSI n S`), found by comparing whole
    /// built rows: the shift most of them agree on. A row that disagrees is
    /// repaired after the move, if the move still pays.
    case exact
    /// As `exact`, and the shift may be found in the part of each row that
    /// moved, so a side pane does not hide it. The fixed columns move with the
    /// band and are repaired, inside the frame's hold.
    case residue
    /// As `residue`, and a band may be narrower than the screen, with DECSLRM
    /// left and right margins, on a host measured to honour them.
    case margins

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// What the environment asks for.
    static let configured = parse(ProcessInfo.processInfo.environment["TUI_SCROLL_OUTPUT"])

    /// A `TUI_SCROLL_OUTPUT` value; anything unknown is `off`.
    static func parse(_ value: String?) -> Self {
        switch value {
        case "exact", "1": .exact
        case "residue": .residue
        case "margins": .margins
        default: .off
        }
    }

    /// What `level` comes to on a host, by what `Tools/TerminalProbes/scroll_region_probe.py`
    /// measured: where a host's display is not held, nothing fixed may be seen
    /// to move and come back, so it stops at `exact`; DECSLRM is only for the
    /// two hosts seen to honour it. Under tmux a held frame repaints the whole
    /// pane at the client whatever it says (`tmux_scroll_probe.py`), so nothing
    /// is to be gained unless holds are off.
    static func level(_ level: Self, on program: TerminalClient.Program, holds: Bool) -> Self {
        switch program {
        case .ghostty, .iTerm2: level
        case .warp: min(level, .residue)
        case .tmux: holds ? .off : min(level, .exact)
        case .appleTerminal, .gnomeTerminal, .xtermJS, .unidentified: min(level, .exact)
        }
    }
}

// MARK: - The plan

/// One move of a band: what to send before the row diff runs.
struct ScrollPlan: Equatable, Sendable {
    /// The region's first and last row, 0-based and inclusive.
    var top: Int
    var bottom: Int
    /// How far the contents move: up when positive (`CSI n S`), down when
    /// negative (`CSI n T`). A new row `i` shows what old row `i + by` showed.
    var by: Int
    /// The columns the band covers, or `nil` for the whole width.
    var columns: Range<Int>?
    /// What the planner thinks this saves, in bytes.
    var saving: Int

    /// The escape sequences that do it, with the frame's first row at `startRow`
    /// (1-based). The region is let go in the same breath, so nothing outlives the
    /// frame but a home cursor, which every write after this moves from anyway:
    /// `CSI r` homes it on all five hosts measured.
    func sequences(startRow: Int) -> String {
        var out = ""
        if let columns {
            out += "\u{1B}[?69h\u{1B}[\(columns.lowerBound + 1);\(columns.upperBound)s"
        }
        out += "\u{1B}[\(startRow + top);\(startRow + bottom)r"
        out += by > 0 ? "\u{1B}[\(by)S" : "\u{1B}[\(-by)T"
        out += "\u{1B}[r"
        if columns != nil { out += "\u{1B}[?69l" }
        return out
    }
}

// MARK: - The planner

/// Finds the shift of a frame and prices it, on the rows the writer already has.
///
/// It runs only where at least ``minimumChangedRows`` rows changed: almost every
/// frame changes fewer, and pays one integer comparison for all of this. Where
/// it does run, it hashes the changed rows, and takes apart nothing the row diff
/// would not take apart anyway: ``newCells`` goes on to that diff.
struct ScrollPlanner {
    /// Fewer changed rows than this cannot pay for the region's bytes, and it is
    /// what keeps a spinner, a breath or a moved selection out of here.
    static let minimumChangedRows = 3
    /// The fewest rows a band may move: fewer is an edit, not a scroll.
    static let minimumMovedRows = 2
    /// `CSI t;b r`, `CSI n S`, `CSI r`, a cursor move and the page's background.
    static let overheadBytes = 40
    /// DECLRMM's two sets and DECSLRM.
    static let marginBytes = 24
    /// The gap ``FrameDiffWriter`` bridges inside a span.
    static let spanGap = 8

    let new: [String]
    let old: [String]
    let changed: [Int]
    let width: Int
    /// Reads a decomposed old row from the writer's cache, or takes it apart.
    let oldRowCells: (Int) -> ANSIRowCells?
    /// Rows that may not ride: carrying compensation a host's store might mind,
    /// or anything but cells. See ``FrameDiffWriter``'s use.
    let rowMayRide: (String) -> Bool

    /// Rows of the new frame taken apart, `nil` until asked for, `.some(nil)`
    /// where a row declines. Handed on to the row diff.
    private(set) var newCells: [ANSIRowCells??]
    private var oldCells: [ANSIRowCells??]

    init(
        new: [String], old: [String], changed: [Int], width: Int,
        oldRowCells: @escaping (Int) -> ANSIRowCells?, rowMayRide: @escaping (String) -> Bool
    ) {
        self.new = new
        self.old = old
        self.changed = changed
        self.width = width
        self.oldRowCells = oldRowCells
        self.rowMayRide = rowMayRide
        newCells = Array(repeating: nil, count: new.count)
        oldCells = Array(repeating: nil, count: new.count)
    }

    private mutating func newRow(_ row: Int) -> ANSIRowCells? {
        if let known = newCells[row] { return known }
        let made = ANSIRowCells(decomposing: new[row], width: width)
        newCells[row] = .some(made)
        return made
    }

    private mutating func oldRow(_ row: Int) -> ANSIRowCells? {
        if let known = oldCells[row] { return known }
        let made = oldRowCells(row)
        oldCells[row] = .some(made)
        return made
    }

    /// What was worked out on the way to a plan: the census prints it.
    struct Findings: Sendable {
        var exactShift = 0
        var exactVotes = 0
        var cellShift = 0
        var cellVotes = 0
        var columns: Range<Int>?
    }

    private(set) var findings = Findings()

    // MARK: Finding the shift

    /// The shift most `signatures` agree on: for each new row whose signature
    /// names at most two old rows, a vote for how far away they are.
    ///
    /// Rows naming more say nothing: blank rows and ruled lines match everywhere.
    private func vote(new: [(row: Int, signature: UInt64)], old: [(row: Int, signature: UInt64)]) -> (by: Int, votes: Int) {
        guard !new.isEmpty, !old.isEmpty else { return (0, 0) }
        let sorted = old.sorted { $0.signature < $1.signature }
        let span = self.new.count
        var votes = [Int32](repeating: 0, count: 2 * span + 1)
        for (row, signature) in new {
            // The first old row with this signature, by bisection.
            var low = 0
            var high = sorted.count
            while low < high {
                let middle = (low + high) / 2
                if sorted[middle].signature < signature { low = middle + 1 } else { high = middle }
            }
            guard low < sorted.count, sorted[low].signature == signature else { continue }
            let tooMany = low + 2 < sorted.count && sorted[low + 2].signature == signature
            if tooMany { continue }
            var index = low
            while index < sorted.count, sorted[index].signature == signature {
                let by = sorted[index].row - row
                if by != 0 { votes[by + span] += 1 }
                index += 1
            }
        }
        var best = (by: 0, votes: 0)
        for (index, count) in votes.enumerated() where Int(count) > best.votes {
            best = (index - span, Int(count))
        }
        return best
    }

    /// Whole rows, hashed: what `exact` looks at.
    private mutating func exactVote() {
        let newRows = changed.map { (row: $0, signature: UInt64(truncatingIfNeeded: new[$0].hashValue)) }
        let oldRows = changed.map { (row: $0, signature: UInt64(truncatingIfNeeded: old[$0].hashValue)) }
        let (by, votes) = vote(new: newRows, old: oldRows)
        findings.exactShift = by
        findings.exactVotes = votes
    }

    /// The columns most changed rows changed in, and the shift of their text
    /// inside those columns: what finds a list beside a side pane.
    private mutating func cellVote() {
        var counts = [Int32](repeating: 0, count: width)
        var seen = 0
        for row in changed {
            guard let new = newRow(row), let old = oldRow(row) else { continue }
            new.addDifferences(from: old, to: &counts)
            seen += 1
        }
        guard seen >= Self.minimumChangedRows else { return }
        let half = Int32(seen / 2)
        guard let left = counts.firstIndex(where: { $0 > half }),
            let right = counts.lastIndex(where: { $0 > half }), right > left
        else { return }
        let columns = left..<(right + 1)
        var newRows: [(row: Int, signature: UInt64)] = []
        var oldRows: [(row: Int, signature: UInt64)] = []
        newRows.reserveCapacity(changed.count)
        oldRows.reserveCapacity(changed.count)
        for row in changed {
            if let cells = newRow(row) { newRows.append((row, cells.textSignature(columns: columns))) }
            if let cells = oldRow(row) { oldRows.append((row, cells.textSignature(columns: columns))) }
        }
        let (by, votes) = vote(new: newRows, old: oldRows)
        findings.columns = columns
        findings.cellShift = by
        findings.cellVotes = votes
    }

    // MARK: Pricing it

    /// What it costs to write `new[row]` over what the terminal would show:
    /// `old[source]` in `band`, and `old[row]` elsewhere.
    private mutating func cost(row: Int, source: Int?, band: Range<Int>?) -> Int? {
        guard let band else {
            guard let source else { return new[row].utf8.count }
            if new[row] == old[source] { return 0 }
            if let cells = newRow(row), let other = oldRow(source) {
                return cells.estimatedWriteBytes(replacing: other, columns: 0..<width, mergingGapsUpTo: Self.spanGap)
            }
            return new[row].utf8.count
        }
        // A narrow band can be repaired only cell by cell: no column of a row
        // that declines can be trusted, and a wide glyph could straddle a margin.
        guard let cells = newRow(row), let fixed = oldRow(row) else { return nil }
        var bytes =
            cells.estimatedWriteBytes(replacing: fixed, columns: 0..<band.lowerBound, mergingGapsUpTo: Self.spanGap)
            + cells.estimatedWriteBytes(replacing: fixed, columns: band.upperBound..<width, mergingGapsUpTo: Self.spanGap)
        if let source {
            guard let other = oldRow(source) else { return nil }
            bytes += cells.estimatedWriteBytes(replacing: other, columns: band, mergingGapsUpTo: Self.spanGap)
        } else {
            bytes += band.count + 16
        }
        return bytes
    }

    /// What `new[row]` costs where it is, today.
    private mutating func costInPlace(_ row: Int) -> Int { cost(row: row, source: row, band: nil) ?? 0 }

    /// The best contiguous band for a shift of `by`, or `nil`: the run of rows
    /// that gains most from the move, less the rows it exposes.
    private mutating func price(by: Int, band: Range<Int>?, inPlace: [Int]) -> ScrollPlan? {
        let rows = new.count
        var best: (sum: Int, first: Int, last: Int)?
        var sum = 0
        var first = 0
        for row in 0..<rows {
            let source = row + by
            guard source >= 0, source < rows,
                let after = cost(row: row, source: source, band: band)
            else {
                sum = 0
                first = row + 1
                continue
            }
            if sum <= 0 {
                sum = 0
                first = row
            }
            sum += inPlace[row] - after
            if sum > (best?.sum ?? 0) { best = (sum, first, row) }
        }
        guard let best, best.last - best.first + 1 >= Self.minimumMovedRows else { return nil }
        let exposed = by > 0 ? (best.last + 1)...(best.last + by) : (best.first + by)...(best.first - 1)
        var saving = best.sum - Self.overheadBytes - (band == nil ? 0 : Self.marginBytes)
        for row in exposed {
            guard let after = cost(row: row, source: nil, band: band) else { return nil }
            saving -= after - inPlace[row]
        }
        let top = by > 0 ? best.first : best.first + by
        let bottom = by > 0 ? best.last + by : best.last
        for row in top...bottom where !rowMayRide(new[row]) || !rowMayRide(old[row]) { return nil }
        return ScrollPlan(top: top, bottom: bottom, by: by, columns: band, saving: saving)
    }

    /// The plan worth taking at `level`, or `nil`.
    mutating func plan(at level: ScrollOutput) -> ScrollPlan? {
        guard level > .off, changed.count >= Self.minimumChangedRows, old.count == new.count else { return nil }
        exactVote()
        let exactIsDecisive = findings.exactVotes * 2 >= changed.count
        if level >= .residue, !exactIsDecisive { cellVote() }

        // Both shifts, when the two looks disagree: a table whose numbers churn
        // gives whole rows few votes and its columns many, and only the price
        // says which of them is the row that moved.
        let shifts = [findings.exactShift, findings.cellShift].filter { $0 != 0 && abs($0) < new.count }
        guard !shifts.isEmpty else { return nil }

        let inPlace = (0..<new.count).map { costInPlace($0) }
        let spent = inPlace.reduce(0, +)
        var chosen: ScrollPlan?
        for by in Array(Set(shifts)).sorted() {
            if let wide = price(by: by, band: nil, inPlace: inPlace), wide.saving > (chosen?.saving ?? 0) {
                chosen = wide
            }
            if level >= .margins, let columns = findings.columns, columns.count < width,
                let narrow = price(by: by, band: columns, inPlace: inPlace), narrow.saving > (chosen?.saving ?? 0)
            {
                chosen = narrow
            }
        }
        guard let chosen, chosen.saving >= max(Self.overheadBytes, spent / 10) else { return nil }
        // Only where the move is not a repair job on the fixed columns does an
        // unheld host get it: `exact` stays with rows that truly moved.
        if level == .exact, findings.exactVotes < Self.minimumMovedRows { return nil }
        return chosen
    }
}

// MARK: - The screen after the move

extension ScrollPlan {
    /// The string a row's previous-frame entry carries when its cells were
    /// spliced by a narrow band: equal to no built row, so the row is diffed,
    /// and to the cell cache's entry, which is what is diffed against.
    static let splicedRow = "\u{FFFF}spliced"

    /// `lines` as the terminal shows them after the move, `""` where a whole
    /// row was exposed, so that row is written whole.
    func movedLines(_ lines: [String]) -> [String] {
        guard columns == nil else {
            var moved = lines
            for row in top...bottom { moved[row] = Self.splicedRow }
            return moved
        }
        var moved = lines
        for row in top...bottom {
            let source = row + by
            moved[row] = (top...bottom).contains(source) ? lines[source] : ""
        }
        return moved
    }
}

extension ScrollPlan {
    /// Moves the cell cache with the band: for a whole-width band each row's
    /// cells go with it, and for a narrow one each band row is spliced from the
    /// two rows it now shows. Rows outside the region keep their entries, which
    /// are checked against their strings as they always are.
    @MainActor
    func move(_ cache: inout FrameDiffWriter.CellCache, lines: [String], old: (Int) -> ANSIRowCells?) {
        for row in top...bottom {
            let source = row + by
            let inside = (top...bottom).contains(source)
            cache.lines[row] = lines[row]
            if let columns {
                cache.cells[row] = old(row)?.splicing(columns: columns, from: inside ? old(source) : nil)
            } else {
                cache.cells[row] = inside ? old(source) : nil
            }
        }
    }
}

// MARK: - The census

/// `TUI_SCROLL_CENSUS`: one tab-separated line per written frame, `-` for
/// standard output or a path: what `Tools/Profiling/scroll_census.py` reads.
/// Costs nothing when unset but one stored optional's check per frame.
@MainActor
final class ScrollCensus {
    /// Where the lines go; `nil` is standard output, through `print`, so that
    /// they keep their place among the lines a harness prints between frames.
    private let handle: FileHandle?
    private var frame = 0

    private init?(destination: String?) {
        guard let destination, !destination.isEmpty else { return nil }
        if destination == "-" {
            handle = nil
        } else {
            _ = FileManager.default.createFile(atPath: destination, contents: nil)
            guard let opened = FileHandle(forWritingAtPath: destination) else { return nil }
            handle = opened
        }
    }

    static func fromEnvironment() -> ScrollCensus? {
        ScrollCensus(destination: ProcessInfo.processInfo.environment["TUI_SCROLL_CENSUS"])
    }

    /// One frame, with what each level would have done with it.
    func record(
        rows: Int, width: Int, changed: [Int], findings: ScrollPlanner.Findings,
        exact: ScrollPlan?, residue: ScrollPlan?, margins: ScrollPlan?
    ) {
        func plan(_ plan: ScrollPlan?) -> String {
            guard let plan else { return "-" }
            let columns = plan.columns.map { "\($0.lowerBound)-\($0.upperBound)" } ?? "full"
            return "\(plan.top)-\(plan.bottom):\(plan.by):\(columns):\(plan.saving)"
        }
        frame += 1
        let columns = findings.columns.map { "\($0.lowerBound)-\($0.upperBound)" } ?? "-"
        let line =
            "#scroll\t\(frame)\t\(rows)\t\(width)\t\(changed.count)"
            + "\t\(findings.exactShift)\t\(findings.exactVotes)\t\(findings.cellShift)\t\(findings.cellVotes)\t\(columns)"
            + "\t\(plan(exact))\t\(plan(residue))\t\(plan(margins))\n"
        if let handle {
            handle.write(Data(line.utf8))
        } else {
            print(line, terminator: "")
        }
    }
}
