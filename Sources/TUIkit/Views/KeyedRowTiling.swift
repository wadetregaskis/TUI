//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KeyedRowTiling.swift
//
//  Which of a flattened container's keyed children each of its runs made: the
//  search `FlattenedRowIDs` places one slot's loops with.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Tiling a Slot's Keyed Children With Its Runs

/// The keyed children of one slot of a flattened container, in order, to be
/// tiled by the runs that made them (`KeyedRowRun`): which span of the
/// children each run made.
///
/// Each run can make a span of a kind of its own:
///
/// - **A counted loop** (`Run.counted`) exactly as many rows as its data says,
///   the first carrying the key its first element gives its rows and the last
///   its last element's.
/// - **A loop placed by its keys** (`Run.byKeys`), whose rows are of a number
///   only each row knows, any run of rows carrying its elements' keys in its
///   elements' order: each element a run of its own key, which may be none.
/// - **An outline** any run of outline rows.
/// - **A provider the walk cannot see into** (`Run.opaque`) anything at all.
///   So it bounds what is placed: the runs before the first such provider are
///   placed from the front, those after the last on the rows up to the end,
///   and any between two of them not at all — the providers own those rows.
///
/// A tiling places every run, in order, each on a span it can have made. One
/// is found whenever one exists: each span is chosen with every run after it
/// in view (`Segment.feasible`), so a loop placed by its keys stops where the
/// loops after it can still be placed, however many there are and whatever
/// comes after them. Where more than one tiling exists — a loop placed by its
/// keys beside another such loop or an outline, ending on a key the next one's
/// rows start with — each such run takes as many rows as it can, the earlier
/// first, and the runs after the last provider that cannot be seen into take
/// as many as they can from it. That is the tiling the greedy two-pass
/// placement this replaced found wherever it found one.
///
/// O(runs × children), plus each loop's elements once — but for a loop placed
/// by its keys whose elements' keys repeat (ids whose keys are spelled alike,
/// which no `ForEach` supports), whose extent is read afresh from each child:
/// O(children × (elements + children)) for that loop.
struct KeyedRowTiling {
    /// What one run can make, for the tiling.
    enum Run {
        /// A loop whose data counts its rows: `rows` of them, the first
        /// carrying `firstKey` and the last `lastKey` (`nil` when there are
        /// none).
        case counted(rows: Int, firstKey: String?, lastKey: String?)
        /// A loop whose rows only each row counts, placed by its elements'
        /// keys, in order.
        case byKeys(elementKeys: [String])
        /// An outline's rows.
        case outline
        /// A provider the walk cannot see into.
        case opaque

        var isOpaque: Bool {
            if case .opaque = self { return true }
            return false
        }
    }

    /// Each keyed child's key, in order.
    private let keys: [String]

    /// Whether the child at a position is an outline's row — asked only of a
    /// group with an outline among its runs.
    private let isOutlineRow: (Int) -> Bool

    init(keys: [String], isOutlineRow: @escaping (Int) -> Bool) {
        self.keys = keys
        self.isOutlineRow = isOutlineRow
    }

    /// The span each of `runs` made, in order — `nil` for a provider the walk
    /// cannot see into and for each run between two of them, which are not
    /// placed — or `nil` when no tiling fits: a run's rows are not where the
    /// walk says they are.
    func spans(of runs: [Run]) -> [Range<Int>?]? {
        var spans = [Range<Int>?](repeating: nil, count: runs.count)
        let count = keys.count
        guard let firstOpaque = runs.firstIndex(where: \.isOpaque),
            let lastOpaque = runs.lastIndex(where: \.isOpaque)
        else {
            // Every run, on every child.
            let all = Segment(runs, in: self, endingWhere: (0...count).map { $0 == count })
            guard let placed = all.place(from: 0) else { return nil }
            for (index, span) in placed.spans.enumerated() { spans[index] = span }
            return spans
        }
        // The runs after the last provider, on the rows up to the end: where
        // they can start decides how far the runs before the first can reach.
        let back = Segment(Array(runs[(lastOpaque + 1)...]), in: self, endingWhere: (0...count).map { $0 == count })
        guard let latestBackStart = back.starts.lastIndex(of: true) else { return nil }
        let front = Segment(Array(runs[..<firstOpaque]), in: self, endingWhere: (0...count).map { $0 <= latestBackStart })
        guard let placedFront = front.place(from: 0),
            let backStart = (placedFront.end...latestBackStart).first(where: { back.starts[$0] }),
            let placedBack = back.place(from: backStart)
        else { return nil }
        for (index, span) in placedFront.spans.enumerated() { spans[index] = span }
        for (index, span) in placedBack.spans.enumerated() { spans[lastOpaque + 1 + index] = span }
        return spans
    }

    /// The element of a loop placed by its keys that made each child of
    /// `span` — a span ``spans(of:)`` gave it: its rows read from the span's
    /// start, each element in turn owning the run of its own key.
    func elements(ofLoopKeyed elementKeys: [String], in span: Range<Int>) -> [Int] {
        var elements: [Int] = []
        elements.reserveCapacity(span.count)
        var position = span.lowerBound
        for (element, key) in elementKeys.enumerated() {
            while position < span.upperBound, keys[position] == key {
                elements.append(element)
                position += 1
            }
        }
        return elements
    }

    // MARK: Reach

    /// For each position, where `run` can end at the furthest when it starts
    /// there — every end between the two is one it can have too (a run of a
    /// loop's keys in its elements' order stays one cut short; so does a run
    /// of outline rows) — or `nil` for a counted loop, which has one end.
    private func reach(of run: Run) -> [Int]? {
        let count = keys.count
        var reach = [Int](repeating: count, count: count + 1)
        switch run {
        case .counted, .opaque:
            return nil
        case .outline:
            for position in stride(from: count - 1, through: 0, by: -1) {
                reach[position] = isOutlineRow(position) ? reach[position + 1] : position
            }
        case .byKeys(let elementKeys):
            var elementOf: [String: Int] = [:]
            for (element, key) in elementKeys.enumerated() {
                guard elementOf[key] == nil else { return readGreedily(elementKeys) }
                elementOf[key] = element
            }
            // Each key names one element, so a run from a position goes on
            // as long as the next child's element is the same or a later one.
            for position in stride(from: count - 1, through: 0, by: -1) {
                guard let element = elementOf[keys[position]] else {
                    reach[position] = position
                    continue
                }
                if position + 1 < count, let next = elementOf[keys[position + 1]], next >= element {
                    reach[position] = reach[position + 1]
                } else {
                    reach[position] = position + 1
                }
            }
        }
        return reach
    }

    /// ``reach(of:)`` for a loop placed by its keys whose elements' keys
    /// repeat, read from each position as ``elements(ofLoopKeyed:in:)`` reads
    /// a span.
    private func readGreedily(_ elementKeys: [String]) -> [Int] {
        let count = keys.count
        return (0...count).map { start in
            var position = start
            for key in elementKeys {
                while position < count, keys[position] == key { position += 1 }
            }
            return position
        }
    }

    // MARK: A Run of Runs

    /// Runs with no provider among them that the walk cannot see into, to be
    /// placed one after another on consecutive spans of the children.
    private struct Segment {
        let runs: [Run]

        /// Each flexible run's ``KeyedRowTiling/reach(of:)``, by its index.
        let reaches: [[Int]?]

        /// `feasible[k][p]`: the runs from the `k`-th on can be placed from
        /// position `p` to an end the segment may end at. `feasible[runs.count]`
        /// is those ends.
        let feasible: [[Bool]]

        /// The positions the segment can be placed from.
        var starts: [Bool] { feasible[0] }

        /// The segment of `runs` on `tiling`'s children, ending at a position
        /// `ends` holds.
        init(_ runs: [Run], in tiling: KeyedRowTiling, endingWhere ends: [Bool]) {
            self.runs = runs
            let reaches = runs.map { tiling.reach(of: $0) }
            self.reaches = reaches
            let keys = tiling.keys
            let count = keys.count
            var feasible = [[Bool]](repeating: [], count: runs.count + 1)
            feasible[runs.count] = ends
            for index in runs.indices.reversed() {
                let after = feasible[index + 1]
                var here = [Bool](repeating: false, count: count + 1)
                switch runs[index] {
                case .counted(let rows, let firstKey, let lastKey):
                    for position in 0...count where position + rows <= count && after[position + rows] {
                        here[position] =
                            rows == 0 || (keys[position] == firstKey && keys[position + rows - 1] == lastKey)
                    }
                case .byKeys, .outline:
                    guard let reach = reaches[index] else { break }
                    // The nearest end at or after each position the rest can
                    // be placed from: reachable when the run gets that far.
                    var nearest = count + 1
                    for position in stride(from: count, through: 0, by: -1) {
                        if after[position] { nearest = position }
                        here[position] = nearest <= reach[position]
                    }
                case .opaque:
                    break
                }
                feasible[index] = here
            }
            self.feasible = feasible
        }

        /// Each run's span from `start`, and where the last ends — each run
        /// that could take more or fewer rows taking as many as leaves the
        /// rest placeable — or `nil` when the segment cannot be placed from
        /// there.
        func place(from start: Int) -> (spans: [Range<Int>], end: Int)? {
            guard feasible[0][start] else { return nil }
            var spans: [Range<Int>] = []
            spans.reserveCapacity(runs.count)
            var position = start
            for (index, run) in runs.enumerated() {
                let end: Int
                switch run {
                case .counted(let rows, _, _):
                    end = position + rows
                case .byKeys, .outline:
                    guard let reach = reaches[index] else { return nil }
                    // `feasible[index][position]` holds, so some end between
                    // here and the reach leaves the rest placeable.
                    var furthest = reach[position]
                    while furthest > position, !feasible[index + 1][furthest] { furthest -= 1 }
                    end = furthest
                case .opaque:
                    return nil
                }
                spans.append(position..<end)
                position = end
            }
            return (spans, position)
        }
    }
}
