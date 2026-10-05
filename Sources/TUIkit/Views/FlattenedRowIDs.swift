//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FlattenedRowIDs.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The rows of a flattened container

/// The selection value of each row of a container whose children arrive
/// FLATTENED — a `Section`'s or a `List`'s content that mixes a `ForEach` with
/// hand-written rows (or with a second `ForEach`, or wraps one in a modifier),
/// walked through `resolveChildViews`.
///
/// A hand-written row answers by the hand-written rule: its own `.tag(_:)`,
/// else its ordinal (see ``staticListRowID(of:ordinal:as:)``). A LOOPED row —
/// one the splice took from a `ForEach` — answers by its loop's rule instead,
/// the one the loop applies when it is the container's whole content: the
/// row's own tag, else its element's id.
///
/// The loop's rule has to be fetched from the loop, because the row cannot
/// carry it. A flattened row is a `ChildView`, which holds its element's id
/// only as the STRING its identity is keyed by — `identityKey(_:)`, a one-way
/// trip — and whose size is load-bearing, so a typed id cannot ride along on it
/// (see `ChildView.providerSlot`). The hand-written rule was applied in its
/// place, and it could not work: a looped row of an `Equatable` element
/// arrives wrapped in `_MemoizedRow`, which is opaque to the tag read, and an
/// ordinal casts into no `String`, `UUID` or `Set` of either. So under any such
/// selection every looped row was unselectable — the cursor stepped over it
/// and a click on it wrote nothing — and under an `Int` selection each was
/// numbered by its position in the container rather than by its element.
///
/// ## Which row is whose: by position
///
/// A flattened row does not say which provider made it, but its PLACE does.
/// `resolveChildViews` emits the children in the order the content declares
/// them — a tuple slot by slot, a `ForEach` element by element — and this walks
/// the content in that same order (``KeyedRowProvider``). Only a loop or an
/// outline makes a KEYED child; every other child is positional. So the keyed
/// children are dealt out to the providers that made them by count: a loop
/// owns exactly as many as it has elements — or as many as its rows' views,
/// for rows of the same number of views each — and an outline owns the run of
/// outline rows in front of it. Each loop's first and last row are checked
/// against the keys the loop gives them, which is what catches a walk that has
/// lost step with the flattening.
///
/// A loop whose rows make a number of views only each row knows — `Text(name);
/// if flagged { Text("!") }`, a loop in a row (decisions B15) — cannot be
/// counted from its data, but every view of such a row carries its element's
/// key (`ChildView.keyedAsMember`). So it is placed by its keys instead: each
/// element in turn owns the run of keyed children carrying its key, which may
/// be none. It is placed after the counted runs on both sides of it, so it
/// claims only the keyed children between them: placed greedily from the
/// front, its last element took the first row of a loop after it whose ids
/// are spelled the same — `ForEach([1, 2, 3])` before `ForEach([3, 4])` — and
/// the placement failed.
///
/// And the keyed children are placed slot by slot: each carries the static
/// slot of the content's outermost tuple it was spliced from
/// (`ChildView.spliceSlot`), and so does each run the walk finds, so the
/// providers in one slot are placed on that slot's children alone. Two loops
/// written side by side never meet, whatever their ids, and a provider this
/// walk cannot see into (below) costs only the loops in its own slot. Where
/// the slots do not tell the runs apart — content with no tuple, a run or a
/// child from no slot — they are placed together, as one.
///
/// Matching by the key alone is what this replaced, and a key names a value
/// only up to its spelling: two loops over overlapping ids — projects 1, 2, 3
/// and people 1, 2 in one sidebar — handed each other's answers, or, where they
/// disagreed, lost both; and an outline node spelled like a loop's element took
/// the loop's tag. By position each row gets its own loop's answer, whatever
/// any other provider's rows are called.
///
/// A provider the walk cannot see into (``KeyedRowRun/opaque``) owns whatever
/// keyed children are left between the loops placed from the front and from
/// the back. Two of them in one slot leave the loops BETWEEN them unplaced,
/// and a failed check unplaces every loop. An unplaced row keeps the hand-written rule —
/// the answer it had before — with its tag read through the value memo, which
/// is at least the tag it wrote.
///
/// The rows themselves are still the flattened ones, rendered at the
/// identities the splice gave them — the `"\(slot)#\(key)"` namespacing and
/// the row memo untouched. Only the id is read from the loop. Asking the
/// content's top-level `ForEach`es for their rows outright
/// (``ListRowExtractor``) would resolve the ids too, and would render the rows
/// at `ForEach.makeListRowContent`'s identity, which has no slot prefix: two
/// loops over the same ids in one container would share `@State` and each
/// other's memoised buffers again.
///
/// ## An ordinal never names a looped row
///
/// An untagged hand-written row falls back to its ordinal, which only an `Int`
/// selection can hold — and an `Int` is exactly what `ForEach(0..<3)` names its
/// rows. Beside such a loop the two collide: "None" at ordinal 0 and the loop's
/// first row both answer 0, so selecting either highlights both, Space on
/// "None" writes the loop's 0, and focus returning to a selection of 0 lands on
/// "None". SwiftUI gives an untagged row no selection value at all, so here an
/// ordinal some looped row in the container already answers to YIELDS: the
/// hand-written row draws, and cannot be selected. An ordinal nothing collides
/// with stays, so a container of hand-written rows keeps the numbers it always
/// had.
///
/// - Note: An id is a SELECTION value and says nothing about which collection a
///   row is in or where — a tag can replace it and a second loop can share it —
///   so recovering it does not make `.onDelete` / `.onMove` attributable in this
///   arrangement, and those still refuse (see
///   ``SectionContentRows/actions``). The placement itself does know
///   each row's loop and offset; it is used for the id and nothing else.
///
/// ## Asked, not computed
///
/// Nothing is walked, placed or resolved until the first answer is asked for,
/// and then only the answer asked for is resolved: a looped row's is its
/// loop's rule, which for a `.tag(_:)`-outermost row means BUILDING the row to
/// read the tag. The one answer that asks others is an untagged hand-written
/// row's ordinal, which has to know whether a looped row answers it (see
/// ``ordinalID(_:)``). The placement is made once, on that first question, and
/// each row's own answer is kept once found, so asking twice costs nothing
/// more. A reference type so that everything holding an answer still to be
/// asked shares the one placement and the one set of answers.
@MainActor
final class FlattenedRowIDs<ID: Hashable> {
    /// The view `children` were flattened from, walked for the placement.
    private let content: any View

    /// The children the answers are for, as `resolveChildViews` returned them —
    /// spacers included, since a position is what matches a row to its loop.
    private let children: [ChildView]

    /// Whether the walk that made ``children`` kept each `Section` whole
    /// (`RenderContext.keepsSectionsWhole`), so that a section is one
    /// positional child rather than its parts' children.
    private let sectionsWhole: Bool

    /// How each child, by its index in ``children``, was placed — `nil` until
    /// the first answer is asked for, then empty when no child was placed as a
    /// looped row, which is every container of hand-written rows.
    private var placements: [Placement]?

    /// The loops ``Placement/looped(loop:offset:)`` points into, in the order
    /// the walk met them.
    private var loops: [any KeyedLoop] = []

    /// Each child's OWN answer — its loop's, or its tag — once asked for,
    /// before any ordinal is considered. Sized to ``children`` on the first
    /// question.
    private var ownAnswers: [OwnAnswer] = []

    /// What the looped rows before ``loopedIDsScanned`` answer to — gathered
    /// by ``ordinalID(_:)``, in order, only as far as its questions have
    /// needed.
    private var loopedIDs: Set<ID> = []

    /// How far into ``children`` ``loopedIDs`` has gathered: the next
    /// ordinal question that needs more resumes here.
    private var loopedIDsScanned = 0

    private enum Placement {
        /// Not a looped row, or a looped row this walk could not place.
        case handWritten
        /// A looped row: one that `loops[loop]`'s `element`-th element made.
        case looped(loop: Int, element: Int)
    }

    /// A child's own answer: not yet asked, or what it names itself — `nil`
    /// when it names nothing this selection can hold.
    private enum OwnAnswer {
        case unasked
        case answered(ID?)
    }

    /// The answers for `children`, which `resolveChildViews` made of `content`
    /// — keeping each `Section` whole when `sectionsWhole`, as a `List`'s walk
    /// does. Nothing is walked here; see the type's note.
    init(content: some View, children: [ChildView], sectionsWhole: Bool = false) {
        self.content = content
        self.children = children
        self.sectionsWhole = sectionsWhole
    }

    /// The selection value of the child at `index`, the `ordinal`-th row of its
    /// container: a placed looped row's own loop's answer, else the
    /// hand-written rule. `nil` means the row draws but cannot be selected —
    /// see `ListRow.id`.
    func id(ofChildAt index: Int, ordinal: Int) -> ID? {
        if let own = ownAnswer(ofChildAt: index) { return own }
        // A looped row its loop named nothing this selection can hold — asked
        // tag first — or a hand-written row with no tag that casts: the ordinal
        // is all that is left, the number it had before.
        return ordinalID(ordinal)
    }

    /// ``id(ofChildAt:ordinal:)``, to be asked later — by whatever holds the
    /// row until something wants its selection value.
    func askedID(ofChildAt index: Int, ordinal: Int) -> AskedRowID<ID> {
        AskedRowID(rowIDs: self, child: index, ordinal: ordinal)
    }

    /// The element id of the child at `index` when it is a looped row this walk
    /// placed, and `nil` for any other child.
    ///
    /// What a `ForEach` row is tagged with by default as a container value —
    /// the element's `id`, never its own `.tag(_:)` (that is read separately,
    /// and outranks this) and never an ordinal: a hand-written row has no
    /// implicit tag at all. Placed the way every other answer here is, so two
    /// loops over overlapping ids each answer with their own elements.
    func elementID(ofChildAt index: Int) -> AnyHashable? {
        let placements = placed()
        guard !placements.isEmpty, case .looped(let loop, let element) = placements[index] else {
            return nil
        }
        return loops[loop].keyedRowElementID(ofElement: element)
    }

    /// What the child at `index` names itself, before any ordinal: a placed
    /// looped row's loop's answer — the row's tag, else its element's id — and
    /// any other row's own tag.
    private func ownAnswer(ofChildAt index: Int) -> ID? {
        let placements = placed()
        if ownAnswers.isEmpty {
            ownAnswers = [OwnAnswer](repeating: .unasked, count: children.count)
        }
        if case .answered(let answer) = ownAnswers[index] { return answer }
        let answer: ID?
        switch placements.isEmpty ? .handWritten : placements[index] {
        case .looped(let loop, let element):
            answer = loops[loop].keyedRowSelectionID(ofElement: element)
        case .handWritten:
            let child = children[index]
            // A keyed child here is a loop's row this walk could not place,
            // and its tag is behind the value memo. A positional child is
            // never memoised, so the plain read is the whole answer for it,
            // and the memo cast is not paid on every hand-written row.
            answer =
                child.identityChildKey == nil
                ? extractTagValue(from: child.wrappedView, as: ID.self)
                : extractRowTagValue(from: child.wrappedView, as: ID.self)
        }
        ownAnswers[index] = .answered(answer)
        return answer
    }

    /// `ordinal` as a selection value, unless a looped row here already
    /// answers to it — see the type's note on why it yields.
    ///
    /// The one question that can ask EVERY looped row. It asks them in order
    /// and stops at the first that answers `ordinal`, keeping what it saw for
    /// the next such question, which checks that first and resumes where this
    /// one stopped. So where a looped row answers — `ForEach(0..<n)`, or tags
    /// numbered from 0, the collision the yield exists for — the question
    /// costs the rows up to that one. Where none does, knowing so takes every
    /// answer, and a tagged row's is any value, read off the built row: no
    /// key, count or range of its loop says it is not `ordinal`. So a list
    /// that draws an untagged hand-written row, under a selection the ordinal
    /// casts into, beside a tagged loop none of whose rows answers it, builds
    /// every one of them on each frame the row is asked about — pinned in
    /// `ListRowSelectionValueCostTests`.
    private func ordinalID(_ ordinal: Int) -> ID? {
        guard let id = ordinal as? ID else { return nil }
        let placements = placed()
        guard !placements.isEmpty else { return id }
        if loopedIDs.contains(id) { return nil }
        while loopedIDsScanned < placements.count {
            let index = loopedIDsScanned
            loopedIDsScanned += 1
            // Only a looped ROW's id: a looped `Section` is spliced as rows
            // keyed by its own items, so the group's id is no row's selection
            // value, and counted here it took a hand-written row's number away
            // for nothing.
            guard case .looped = placements[index], !Self.isSection(children[index]),
                let answer = ownAnswer(ofChildAt: index)
            else { continue }
            loopedIDs.insert(answer)
            if answer == id { return nil }
        }
        return id
    }

    /// The placement, made on the first question.
    private func placed() -> [Placement] {
        if let placements { return placements }
        let placements = place()
        self.placements = placements
        return placements
    }

    /// Walks the content and places its loops on the children.
    ///
    /// The content is walked only when some child IS keyed, so a container of
    /// hand-written rows pays one scan of the children it already has, and
    /// nothing is placed unless the walk found a loop. A failed placement
    /// places nothing at all.
    private func place() -> [Placement] {
        let keyed = children.indices.filter { children[$0].identityChildKey != nil }
        // A loop of sections — `ForEach(groups) { Section … }` — makes no rows
        // of its own: the list splices each section's rows, keyed by the
        // section's own items, and asks nothing here. So nothing is walked.
        guard !keyed.isEmpty, !keyed.allSatisfy({ Self.isSection(children[$0]) }) else { return [] }
        var runs = KeyedRowRuns()
        appendKeyedRowRuns(of: content, to: &runs, sectionsWhole: sectionsWhole)
        let loops = runs.runs.compactMap { run -> (any KeyedLoop)? in
            if case .loop(let loop, _) = run { return loop }
            return nil
        }
        guard !loops.isEmpty,
            let placements = Self.placements(of: runs, onKeyed: keyed, of: children)
        else { return [] }
        self.loops = loops
        return placements
    }

    /// Whether `child` is a `Section`, which the list splices as rows of its
    /// own rather than asking an id of — the question `_ListCore`'s
    /// `sectionRow(of:)` asks, answered without building the section.
    static func isSection(_ child: ChildView) -> Bool {
        if child.wrappedView is SectionRowExtractor { return true }
        guard let memo = child.wrappedView as? any _ValueMemoWrapping else { return false }
        return memo.memoizedContentType is any SectionRowExtractor.Type
    }

    // MARK: Placing the loops

    /// Places each loop in `runs` on the keyed children it made, or answers
    /// `nil` when a loop's rows are not where the walk says they are.
    ///
    /// `keyed` holds the indices into `children` of the keyed ones, in order.
    /// The runs and the keyed children of each slot are placed together
    /// (``slotGroups(of:onKeyed:of:)``), and a slot whose placement fails
    /// unplaces them all.
    private static func placements(
        of runs: KeyedRowRuns, onKeyed keyed: [Int], of children: [ChildView]
    ) -> [Placement]? {
        var placements = [Placement](repeating: .handWritten, count: children.count)
        // Each run with its loop number, in the order `place()` collects the
        // loops.
        var numbered: [NumberedRun] = []
        var loopCount = 0
        for run in runs.runs {
            numbered.append(NumberedRun(run: run, loop: loopCount))
            if run.isLoop { loopCount += 1 }
        }
        for group in slotGroups(of: runs, onKeyed: keyed, of: children) {
            guard
                place(
                    group.runs.map { numbered[$0] }, onKeyed: group.keyed, of: children,
                    into: &placements)
            else { return nil }
        }
        return placements
    }

    /// A run, and the number of its loop among the loops the walk met.
    private struct NumberedRun {
        let run: KeyedRowRun
        let loop: Int
    }

    /// The runs (their indices in `runs`) and the keyed children (their
    /// indices in `children`) that are placed together: those of each slot of
    /// the content's outermost tuple apart, in order — or all of them as one
    /// group, where a run or a keyed child comes from no slot, or a child from
    /// a slot no run came from, so the slots cannot be trusted to tell them
    /// apart.
    private static func slotGroups(
        of runs: KeyedRowRuns, onKeyed keyed: [Int], of children: [ChildView]
    ) -> [(runs: [Int], keyed: [Int])] {
        let whole = [(runs: Array(runs.runs.indices), keyed: keyed)]
        var runsBySlot: [Int: [Int]] = [:]
        var slots: [Int] = []
        for (index, slot) in runs.slots.enumerated() {
            guard let slot else { return whole }
            if runsBySlot[slot] == nil { slots.append(slot) }
            runsBySlot[slot, default: []].append(index)
        }
        guard slots.count > 1 else { return whole }
        var keyedBySlot: [Int: [Int]] = [:]
        for index in keyed {
            guard let slot = children[index].spliceSlot, runsBySlot[slot] != nil else { return whole }
            keyedBySlot[slot, default: []].append(index)
        }
        return slots.map { (runs: runsBySlot[$0, default: []], keyed: keyedBySlot[$0, default: []]) }
    }

    /// Places `runs` on the keyed children at `keyed` (indices into
    /// `children`), answering `false` when a loop's rows are not where the
    /// walk says they are.
    ///
    /// The loops whose rows are counted are placed first, counted off from the
    /// front and then from the back, each side up to the first run that is not
    /// counted: one placed by its keys, or a provider whose rows cannot be
    /// counted. Then the runs between are placed in the keyed children left
    /// between those, a loop by its keys, from the front up to such a
    /// provider and from the back down to it, and that provider owns what is
    /// left. So a loop placed by its keys is bounded by the loops on either
    /// side of it, and claims no row of theirs whose key is spelled like one of
    /// its own.
    private static func place(
        _ runs: [NumberedRun], onKeyed keyed: [Int], of children: [ChildView],
        into placements: inout [Placement]
    ) -> Bool {
        let spans = KeyedSpans(keyed: keyed, children: children)
        var front = 0
        var back = keyed.count
        var first = 0
        var last = runs.count
        /// Places `run` from `front` — `false` when its rows are not there,
        /// `nil` when it is a provider that cannot be counted.
        func placeFromFront(_ run: NumberedRun, onlyCounted: Bool) -> Bool? {
            switch run.run {
            case .loop(let loop, let rowsPerElement):
                if onlyCounted, rowsPerElement == nil { return nil }
                guard
                    let end = spans.place(
                        loop, rowsPerElement: rowsPerElement, number: run.loop, from: front,
                        within: front..<back, into: &placements)
                else { return false }
                front = end
            case .outline:
                while front < back, isOutlineRow(children[keyed[front]]) { front += 1 }
            case .opaque:
                return nil
            }
            return true
        }
        /// Places `run` ending at `back` — the same answers.
        func placeFromBack(_ run: NumberedRun, onlyCounted: Bool) -> Bool? {
            switch run.run {
            case .loop(let loop, let rowsPerElement):
                if onlyCounted, rowsPerElement == nil { return nil }
                guard
                    let start = spans.place(
                        loop, rowsPerElement: rowsPerElement, number: run.loop, endingAt: back,
                        within: front..<back, into: &placements)
                else { return false }
                back = start
            case .outline:
                while back > front, isOutlineRow(children[keyed[back - 1]]) { back -= 1 }
            case .opaque:
                return nil
            }
            return true
        }
        for onlyCounted in [true, false] {
            while first < last, let placed = placeFromFront(runs[first], onlyCounted: onlyCounted) {
                guard placed else { return false }
                first += 1
            }
            while last > first, let placed = placeFromBack(runs[last - 1], onlyCounted: onlyCounted) {
                guard placed else { return false }
                last -= 1
            }
        }
        // Every run was placed, so every keyed child must have been claimed:
        // one left over is one the walk does not know about.
        return first != last || front == back
    }

    /// The keyed children of a container, in order, for its loops to be
    /// placed on — `keyed` indexing into `children`.
    @MainActor
    private struct KeyedSpans {
        let keyed: [Int]
        let children: [ChildView]

        /// The key of the `position`-th keyed child.
        private func key(at position: Int) -> String? {
            children[keyed[position]].identityChildKey
        }

        /// Places `loop` — the `number`-th loop the walk met — on the keyed
        /// children from `start` on, answering where its rows end: `nil` when
        /// they are not there.
        ///
        /// Records WHICH element of which loop made each row, and resolves
        /// nothing: the loop is asked for a row's answer only when that row's
        /// is asked for.
        func place(
            _ loop: any KeyedLoop, rowsPerElement: Int?, number: Int, from start: Int,
            within bounds: Range<Int>, into placements: inout [Placement]
        ) -> Int? {
            guard let perElement = rowsPerElement else {
                // Rows only each element knows the number of: each element's
                // run of its own key, in order, from the front.
                var position = start
                for element in 0..<loop.keyedElementCount {
                    let elementKey = loop.keyedRowKey(ofElement: element)
                    while position < bounds.upperBound, key(at: position) == elementKey {
                        placements[keyed[position]] = .looped(loop: number, element: element)
                        position += 1
                    }
                }
                return position
            }
            let end = start + loop.keyedElementCount * perElement
            return placeCounted(loop, perElement: perElement, number: number, start..<end, bounds, &placements)
                ? end : nil
        }

        /// Places `loop` on the keyed children ending at `end`, answering where
        /// its rows start: `nil` when they are not there.
        func place(
            _ loop: any KeyedLoop, rowsPerElement: Int?, number: Int, endingAt end: Int,
            within bounds: Range<Int>, into placements: inout [Placement]
        ) -> Int? {
            guard let perElement = rowsPerElement else {
                // The same runs as from the front, met last element first.
                var position = end
                for element in (0..<loop.keyedElementCount).reversed() {
                    let elementKey = loop.keyedRowKey(ofElement: element)
                    while position > bounds.lowerBound, key(at: position - 1) == elementKey {
                        position -= 1
                        placements[keyed[position]] = .looped(loop: number, element: element)
                    }
                }
                return position
            }
            let start = end - loop.keyedElementCount * perElement
            return placeCounted(loop, perElement: perElement, number: number, start..<end, bounds, &placements)
                ? start : nil
        }

        /// Places a loop whose every element makes `perElement` rows on the
        /// keyed children at `span`, having checked that the first and the
        /// last of them carry the keys the loop gives them: `false` when they
        /// do not, or when the span falls outside `bounds`.
        private func placeCounted(
            _ loop: any KeyedLoop, perElement: Int, number: Int, _ span: Range<Int>,
            _ bounds: Range<Int>, _ placements: inout [Placement]
        ) -> Bool {
            guard !span.isEmpty else { return true }
            guard span.lowerBound >= bounds.lowerBound, span.upperBound <= bounds.upperBound,
                key(at: span.lowerBound) == loop.keyedRowKey(ofElement: 0),
                key(at: span.upperBound - 1) == loop.keyedRowKey(ofElement: loop.keyedElementCount - 1)
            else { return false }
            for (offset, position) in span.enumerated() {
                placements[keyed[position]] = .looped(loop: number, element: offset / perElement)
            }
            return true
        }
    }

    /// Whether `child` is a row an `OutlineGroup` made, seen through the
    /// wrappers the splice puts round a modified provider's members.
    private static func isOutlineRow(_ child: ChildView) -> Bool {
        throughWrappers(child.wrappedView, as: (any OutlineRowMarking).self) != nil
    }
}

// MARK: - An answer still to be asked

/// A flattened child's selection value, still to be asked of the
/// ``FlattenedRowIDs`` of the container it came from — what a row carries
/// until something wants its id, so a frame that never asks (a hug measure,
/// or the rows no one draws) never builds a tagged row to answer.
@MainActor
struct AskedRowID<ID: Hashable> {
    /// The answers of the container the row came from.
    let rowIDs: FlattenedRowIDs<ID>
    /// The row's index among that container's flattened children.
    let child: Int
    /// The row's ordinal among that container's rows.
    let ordinal: Int

    /// The selection value, asked now — and kept by ``rowIDs``, so a second
    /// ask costs nothing more.
    var id: ID? { rowIDs.id(ofChildAt: child, ordinal: ordinal) }
}

/// What an `OutlineGroup`'s flattened row is, whatever it outlines.
@MainActor
private protocol OutlineRowMarking {}

extension _OutlineRow: OutlineRowMarking {}
