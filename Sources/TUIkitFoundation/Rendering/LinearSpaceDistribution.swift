//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LinearSpaceDistribution.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Stack Overflow Policy

/// How a linear stack core (``VStack``/``HStack`` and their lazy variants)
/// behaves when its children don't all fit the available extent along the
/// layout axis.
///
/// The eager stacks (`VStack`/`HStack`) and the lazy stacks
/// (`LazyVStack`/`LazyHStack`) share one rendering core; this policy is the
/// *only* thing that distinguishes them.
///
/// - `clip`: the eager behaviour. Every child is laid out via
///   ``distributeLinearSpace(naturalSizes:isFlexible:available:spacing:shares:isSpacer:priorities:minimumSize:statedMinimum:sizeAt:)``,
///   which shares the space as SwiftUI's stacks do and clips, *at the cell*,
///   only what even the children's minimums cannot fit (a child can be cut
///   mid-content). The reported size is the analytic sum-and-clamp.
/// - `window`: the lazy behaviour. Whole children are appended while they fit
///   the available extent and the loop `break`s as soon as the next one would
///   not — so the rendered extent always ends on a child boundary and may fall
///   short of the limit by a truncated child. Because of that child-boundary
///   truncation the reported size MUST be render-derived (an analytic sum would
///   over-report it).
package enum StackOverflow {
    /// Eager: distribute + clip trailing overflow at the cell.
    case clip
    /// Lazy: append whole children while they fit; stop at the first that won't.
    case window
}

// MARK: - Linear Space Distribution

/// Distributes `available` cells across a row or column of children.
///
/// Shared by ``HStack`` (width) and ``VStack`` (height), their `Layout`
/// spellings and the lazy stacks' guide queries. A row shares its space as
/// SwiftUI's stacks do (`shares`, decisions L14); a column, for now, places
/// its children in order (``distributeInOrder(naturalSizes:isFlexible:available:gaps:)``,
/// deviation L14b). Children of a higher
/// ``View/layoutPriority(_:)`` are served first
/// (``distributeLinearSpace(byPriority:naturalSizes:isFlexible:available:gaps:minimum:group:)``);
/// among children of one priority (``distributeOnePriority(naturalSizes:isFlexible:isSpacer:available:gaps:minimumSize:statedMinimum:sizeAt:)``):
///
/// - **Spacers** are set aside at their minimum length and take what the
///   others leave.
/// - **The others** are dealt the space one at a time, the least flexible
///   first, each offered an equal share of what is left. A child's flexibility
///   is how far below its natural size it can shrink; one that fills the axis
///   is the most flexible of all. So a short child keeps its whole length
///   beside a long one, which takes the shortfall, and two children of one
///   length share it.
/// - **When even their minimums do not fit**, the children are placed in
///   order at their natural sizes until the space runs out, filling children
///   at none, so the leading content stays visible and the rest is clipped.
///
/// `spacing` is charged only *between children that are actually placed*. This
/// is the difference between clipping gracefully and going blank: reserving a
/// gap for every child up front means a stack with more gaps than fit (e.g. a
/// `VStack(spacing: 1)` of a dozen rows in a pane only a few rows tall) would
/// have **no** budget left for content and collapse every child to zero —
/// rendering nothing. Charging spacing per placed child instead shows the
/// children that fit and clips the rest, the way SwiftUI does.
///
/// The placed sizes plus the spacing between them always sum to at most
/// `max(0, available)` — which is what makes a stack unable to overflow the
/// space it was given.
///
/// - Parameters:
///   - naturalSizes: Each child's natural size along the layout axis.
///   - isFlexible: Whether each child can flex along the layout axis.
///     Must be the same length as `naturalSizes`.
///   - available: The total space to distribute, *including* the inter-child
///     spacing (which this function accounts for; callers pass the full extent).
///   - spacing: The gap rendered between adjacent non-empty children.
///   - shares: Whether children of one priority share the space as SwiftUI's
///     do — a row's — or are placed in order — a column's, for now.
///   - isSpacer: Whether the child at an index is a `Spacer`, whose natural
///     size is its minimum length.
///   - priorities: Each child's ``View/layoutPriority(_:)``, or `nil` when every
///     one is `0` — the common case.
///   - minimumSize: A child's size when offered nothing on this axis, measured
///     when the distribution needs it — only where a child may be offered less
///     than its natural size — or `nil` for a child that cannot shrink.
///   - statedMinimum: The minimum a filling child states without being
///     measured (a frame's `minWidth`); `0` for none.
///   - sizeAt: The size a child takes along the axis when offered the given
///     length, less than its natural size — measured, as SwiftUI asks each
///     child — or `nil` to take it as all of the offer (a truncating text's
///     answer).
/// - Returns: One allocated size per child; placed sizes + their gaps sum to
///   `<= max(0, available)`.
func distributeLinearSpace(
    naturalSizes: [Int], isFlexible: [Bool], available: Int, spacing: Int = 0, shares: Bool = true,
    isSpacer: (Int) -> Bool = { _ in false }, priorities: [Double]? = nil, minimumSize: (Int) -> Int? = { _ in nil },
    statedMinimum: (Int) -> Int = { _ in 0 }, sizeAt: (Int, Int) -> Int? = { _, _ in nil }
) -> [Int] {
    distributeLinearSpace(
        naturalSizes: naturalSizes, isFlexible: isFlexible, available: available, gaps: StackGaps(uniform: spacing),
        shares: shares, isSpacer: isSpacer, priorities: priorities, minimumSize: minimumSize,
        statedMinimum: statedMinimum, sizeAt: sizeAt)
}

/// ``distributeLinearSpace(naturalSizes:isFlexible:available:spacing:shares:isSpacer:priorities:minimumSize:statedMinimum:sizeAt:)`` with
/// the gaps a ``StackGaps`` gives each pair of neighbours, each clamped at zero
/// as the single `spacing` is.
func distributeLinearSpace(
    naturalSizes: [Int], isFlexible: [Bool], available: Int, gaps: StackGaps, shares: Bool = true,
    isSpacer: (Int) -> Bool = { _ in false }, priorities: [Double]? = nil, minimumSize: (Int) -> Int? = { _ in nil },
    statedMinimum: (Int) -> Int = { _ in 0 }, sizeAt: (Int, Int) -> Int? = { _, _ in nil }
) -> [Int] {
    if let priorities {
        // Each child's minimum, found once whichever group asks: a spacer's is
        // its natural size, its minimum length; a filling child's the one it
        // states; a fixed child's measured.
        var minimums = [Int?](repeating: nil, count: naturalSizes.count)
        func minimum(_ index: Int) -> Int {
            if let known = minimums[index] { return known }
            let natural = max(0, naturalSizes[index])
            let found =
                isSpacer(index)
                ? natural : isFlexible[index] ? statedMinimum(index) : minimumSize(index) ?? natural
            let measured = min(max(0, found), natural)
            minimums[index] = measured
            return measured
        }
        return distributeLinearSpace(
            byPriority: priorities, naturalSizes: naturalSizes, isFlexible: isFlexible, available: available,
            gaps: gaps, minimum: minimum
        ) { members, space in
            let memberNaturals = members.map { naturalSizes[$0] }
            let memberFlexible = members.map { isFlexible[$0] }
            guard shares else {
                return distributeInOrder(
                    naturalSizes: memberNaturals, isFlexible: memberFlexible, available: space, gaps: StackGaps(uniform: 0))
            }
            return distributeOnePriority(
                naturalSizes: memberNaturals, isFlexible: memberFlexible,
                isSpacer: { isSpacer(members[$0]) }, available: space,
                gaps: StackGaps(uniform: 0), minimumSize: { minimum(members[$0]) },
                statedMinimum: { minimum(members[$0]) }, sizeAt: { sizeAt(members[$0], $1) })
        }
    }
    guard shares else {
        return distributeInOrder(naturalSizes: naturalSizes, isFlexible: isFlexible, available: available, gaps: gaps)
    }
    return distributeOnePriority(
        naturalSizes: naturalSizes, isFlexible: isFlexible, isSpacer: isSpacer, available: available, gaps: gaps,
        minimumSize: minimumSize, statedMinimum: statedMinimum, sizeAt: sizeAt)
}

/// The children of one layout priority dealt `available` cells, SwiftUI's way
/// (measured: `Tools/SwiftUIProbes/Layout priority/priority.out`, `share.out`
/// and `spacer.out`).
///
/// SwiftUI sorts a stack's children by flexibility — the range between the
/// sizes they take offered nothing and offered everything — and offers each in
/// turn the space left divided by the children left, a spacer excepted: a
/// spacer keeps its minimum length whatever the others need (`HStack {
/// Text(ten); Spacer(); Text(ten) }` in twenty characters truncates a text
/// rather than the spacer's eight points), and is offered what they leave.
/// Here a share is whole cells, the earlier child of two taking the odd one.
/// A fixed child offered its natural size or more takes its natural size;
/// offered less, it is asked (`sizeAt`) and takes its answer, never less than
/// its minimum. A filling child takes all of its offer and can shrink to
/// nothing, as TUIkit's filling views do, so it is never asked.
///
/// A minimum is measured only when it decides something. Where every fixed
/// child fits beside its siblings — no filling child and the natural sizes
/// sum within the space, or no fixed child longer than an equal share — each
/// fixed child is offered its natural size whatever the order, and nothing is
/// measured. SwiftUI's sort would differ from that shortcut only for a fixed
/// child whose minimum is nearly its natural size beside a sibling that can
/// shrink further, which it could then cut although everything fits.
///
/// When the minimums of the children other than the spacers do not fit at
/// all, there is nothing to share, and SwiftUI's stack would overflow its
/// frame: TUIkit's instead places the children in order at their natural
/// sizes, filling children at none, charging a gap only between the children
/// it places, until the space runs out (``placeInOrder(_:isFlexible:available:gaps:)``).
func distributeOnePriority(
    naturalSizes: [Int], isFlexible: [Bool], isSpacer: (Int) -> Bool, available: Int, gaps: StackGaps,
    minimumSize: (Int) -> Int?, statedMinimum: (Int) -> Int, sizeAt: (Int, Int) -> Int?
) -> [Int] {
    let count = naturalSizes.count
    let total = max(0, available)
    func natural(_ index: Int) -> Int { max(0, naturalSizes[index]) }

    // Each child's minimum, found when first needed. A fixed child's is
    // measured; one that cannot be measured cannot shrink. A filling child
    // takes all it is offered, so it is never measured — asked, a column of
    // rows that fill it measured every row twice on every walk that dealt
    // most of them nothing — and keeps only a minimum it states (a frame's
    // `minWidth`, a `frame(width:)` squeezed below its width, which reports
    // itself flexible there). Allocated on first use: a row that fits needs
    // none.
    var minimums: [Int?] = []
    func minimum(_ index: Int) -> Int {
        if minimums.isEmpty { minimums = [Int?](repeating: nil, count: count) }
        if let known = minimums[index] { return known }
        let found = isFlexible[index] ? statedMinimum(index) : minimumSize(index) ?? natural(index)
        let measured = min(max(0, found), natural(index))
        minimums[index] = measured
        return measured
    }

    /// The deal. With `firstDeal`, the spacers it gave nothing are left out:
    /// no gap is reserved beside them, and they are given nothing again.
    func deal(after firstDeal: [Int]?) -> [Int] {
        func isIdle(_ index: Int) -> Bool { firstDeal.map { $0[index] == 0 && isSpacer(index) } ?? false }
        // How many children will OCCUPY the axis: the gaps are reserved
        // between those, not one per child. A fixed child of no extent is
        // appended through `appendHorizontally` / `appendVertically`'s
        // contributes-nothing branch and earns no gap, so a gap reserved for it
        // was space no flexible sibling was ever handed — `HStack(spacing: 2) {
        // Text("A"); EmptyView(); Spacer(); Text("B") }` in 20 cells gave the
        // spacer 12 rather than 14, and "B" stopped two short of the edge of a
        // row that reports itself as filling the width. A flexible child counts
        // even at a natural size of zero (a default `Spacer`), because its
        // allocation is the very thing being decided.
        let occupies = { (index: Int) in !isIdle(index) && (isFlexible[index] || natural(index) > 0) }
        // A gap by pair is never negative (``StackGaps``), so only the one
        // `spacing` needs the clamp.
        let allSpacing =
            gaps.isUniform
            ? totalLinearSpacing(occupiedChildren: (0..<count).count(where: occupies), spacing: max(0, gaps.uniform))
            : gaps.total(count: count, occupies: occupies)
        let tally = RowTally(
            count: count, natural: natural, isFlexible: isFlexible, isSpacer: isSpacer, isIdle: isIdle)
        let shared = total - allSpacing - tally.reserved

        var result = [Int](repeating: 0, count: count)
        var left = shared
        if tally.fillingCount == 0, tally.fixedNatural <= shared {
            // Every fixed child fits whole, and nothing that fills the axis is
            // offered a share before it: each takes its natural size.
            for index in 0..<count where !isSpacer(index) { result[index] = natural(index) }
            left -= tally.fixedNatural
        } else {
            let order = dealOrder(
                count: count, tally: tally, shared: shared, natural: natural, isFlexible: isFlexible,
                isSpacer: isSpacer, minimum: minimum)
            if case .placeInOrder = order {
                return placeInOrder(naturalSizes, isFlexible: isFlexible, available: total, gaps: gaps)
            }
            var waiting = tally.fixedCount + tally.fillingCount
            func give(_ index: Int) {
                let offer = shareOf(left, among: waiting)
                let taken = share(
                    of: offer, to: index, natural: natural(index), isFlexible: isFlexible[index], minimum: minimum,
                    sizeAt: sizeAt)
                result[index] = taken
                left -= taken
                waiting -= 1
            }
            if case .sorted(let fixed) = order {
                for index in fixed { give(index) }
            } else {
                for index in 0..<count where !isSpacer(index) && !isFlexible[index] { give(index) }
            }
            for index in 0..<count where !isSpacer(index) && isFlexible[index] { give(index) }
        }

        // The spacers: what the others left, each its minimum length at least.
        left += tally.reserved
        var waiting = (0..<count).count { isSpacer($0) && !isIdle($0) }
        for index in 0..<count where isSpacer(index) && !isIdle(index) {
            let taken = max(natural(index), shareOf(left, among: waiting))
            result[index] = taken
            left -= taken
            waiting -= 1
        }

        // A filling child's minimum can still have outrun the share it was
        // offered; the order then decides, as when nothing could be shared.
        let placedSpacing = gaps.total(count: count) { result[$0] > 0 }
        guard result.reduce(0, +) + placedSpacing > total else { return result }
        return placeInOrder(result, isFlexible: nil, available: total, gaps: gaps)
    }

    // A spacer left nothing occupies no part of the axis, so the gap reserved
    // beside it is drawn by nobody: dealt again without it, the space goes to
    // the children it was kept from — a toolbar item exactly as wide as its
    // bar, beside a `Spacer(minLength: 0)`, lost a column to it.
    let first = deal(after: nil)
    let anyIdle = (0..<count).contains { isSpacer($0) && first[$0] == 0 }
    return anyIdle ? deal(after: first) : first
}

/// A COLUMN's children of one priority given `available` cells as TUIkit's
/// stacks gave them before rows followed SwiftUI (decisions L14): fixed
/// children keep their natural size and filling ones absorb the surplus; where
/// space is short the filling ones shrink first, in proportion to their natural
/// sizes; and where even the fixed content overflows, the filling children get
/// nothing and the fixed ones are placed in order until the space runs out
/// (``placeInOrder(_:isFlexible:available:gaps:)``).
///
/// SwiftUI shares a column as it shares a row. Columns keep this rule for now
/// (deviation L14b): shared, a control of several lines is squeezed in the
/// middle of a column, and a squeezed inline menu, which then scrolls inside
/// its border, draws differently served from the cache than drawn afresh.
func distributeInOrder(naturalSizes: [Int], isFlexible: [Bool], available: Int, gaps: StackGaps) -> [Int] {
    let total = max(0, available)
    var result = naturalSizes.map { max(0, $0) }
    let flexIndices = result.indices.filter { isFlexible[$0] }

    var nonFlexTotal = 0
    var flexTotal = 0
    // How many children will OCCUPY the axis, as `distributeOnePriority`
    // counts them: a fixed child of no extent earns no gap, a flexible one
    // does even at a natural size of zero.
    var occupying = 0
    for index in result.indices {
        if isFlexible[index] {
            flexTotal += result[index]
            occupying += 1
        } else {
            nonFlexTotal += result[index]
            if result[index] > 0 { occupying += 1 }
        }
    }
    let allSpacing =
        gaps.isUniform
        ? totalLinearSpacing(occupiedChildren: occupying, spacing: max(0, gaps.uniform))
        : gaps.total(count: result.count) { isFlexible[$0] || result[$0] > 0 }

    if nonFlexTotal + flexTotal + allSpacing <= total {
        // Everything (content + every gap) fits; flexible children absorb the surplus.
        addLinearSpace(
            total - nonFlexTotal - flexTotal - allSpacing, to: flexIndices, of: &result, weights: nil)
        return result
    }
    guard nonFlexTotal + allSpacing <= total else {
        // Even the fixed content + its gaps overflow.
        return placeInOrder(result, isFlexible: isFlexible, available: total, gaps: gaps)
    }
    // Fixed content + gaps fit; flexible children share the remainder.
    let weights = flexTotal > 0 ? flexIndices.map { result[$0] } : nil
    for index in flexIndices { result[index] = 0 }
    addLinearSpace(total - nonFlexTotal - allSpacing, to: flexIndices, of: &result, weights: weights)
    return result
}

/// Adds `amount` cells across `indices`, either evenly or proportionally to
/// `weights`, handing out any rounding remainder one cell at a time.
private func addLinearSpace(_ amount: Int, to indices: [Int], of result: inout [Int], weights: [Int]?) {
    guard !indices.isEmpty, amount > 0 else { return }

    let weightTotal = weights?.reduce(0, +) ?? 0
    if let weights, weightTotal > 0 {
        var distributed = 0
        for (offset, index) in indices.enumerated() {
            let share = amount * weights[offset] / weightTotal
            result[index] += share
            distributed += share
        }
        var remainder = amount - distributed
        var cursor = 0
        while remainder > 0 {
            result[indices[cursor % indices.count]] += 1
            remainder -= 1
            cursor += 1
        }
    } else {
        let per = amount / indices.count
        let remainder = amount % indices.count
        for (offset, index) in indices.enumerated() {
            result[index] += per + (offset < remainder ? 1 : 0)
        }
    }
}

/// What one pass over a row's children finds — all ``distributeOnePriority``'s
/// fast path needs, and nothing allocated.
private struct RowTally {
    /// The spacers' minimum lengths, set aside before the others are dealt.
    var reserved = 0
    /// The fixed children, those of them with content, their natural sizes
    /// summed, and the longest of them.
    var fixedCount = 0
    var fixedWithContent = 0
    var fixedNatural = 0
    var longestFixed = 0
    /// The children that fill the axis.
    var fillingCount = 0

    init(count: Int, natural: (Int) -> Int, isFlexible: [Bool], isSpacer: (Int) -> Bool, isIdle: (Int) -> Bool) {
        for index in 0..<count {
            if isSpacer(index) {
                if !isIdle(index) { reserved += natural(index) }
            } else if isFlexible[index] {
                fillingCount += 1
            } else {
                let length = natural(index)
                fixedCount += 1
                fixedNatural += length
                longestFixed = max(longestFixed, length)
                if length > 0 { fixedWithContent += 1 }
            }
        }
    }
}

/// The order a deal offers the children that are not spacers their shares.
private enum DealOrder {
    /// The fixed children in their order, then the filling ones: none of the
    /// fixed is longer than an equal share, so every one is offered its
    /// natural size whatever the order.
    case byIndex
    /// The fixed children least flexible first, then the filling ones.
    case sorted([Int])
    /// Their minimums do not fit: nothing to share.
    case placeInOrder
}

/// Fixed children first, as the less flexible; sorted among themselves only
/// where one may be offered less than its natural size — which needs their
/// minimums.
///
/// Nothing is shared where the minimums cannot fit. A fixed child with
/// content keeps a cell of it at least (`…`), so more of them than there are
/// cells decides that without measuring one — the tall column that overflows
/// its viewport, asked on every walk; otherwise the minimums are summed until
/// they outrun the space, measuring no further.
private func dealOrder(
    count: Int, tally: RowTally, shared: Int, natural: (Int) -> Int, isFlexible: [Bool], isSpacer: (Int) -> Bool,
    minimum: (Int) -> Int
) -> DealOrder {
    guard tally.longestFixed > max(0, shared) / max(1, tally.fixedCount + tally.fillingCount) else { return .byIndex }
    guard tally.fixedWithContent <= shared else { return .placeInOrder }
    var minimumTotal = 0
    for index in 0..<count where !isSpacer(index) {
        minimumTotal += minimum(index)
        guard minimumTotal <= shared else { return .placeInOrder }
    }
    return .sorted(
        (0..<count).filter { !isSpacer($0) && !isFlexible[$0] }
            .map { (index: $0, flexibility: natural($0) - minimum($0)) }
            .sorted { ($0.flexibility, $0.index) < ($1.flexibility, $1.index) }
            .map(\.index))
}

/// What the child at `index` takes of an `offer`. A filling child takes all of
/// it, its minimum at least; a fixed child offered its natural size or more
/// takes that; offered less, it is asked, as SwiftUI asks: a view that
/// answers with less than it was offered (a `ViewThatFits` falling back)
/// leaves the rest to the children after it. Never below its minimum, which a
/// frame that cannot shrink keeps although the measure, clamped to the offer,
/// does not say so; offered nothing, its minimum is the answer.
private func share(
    of offer: Int, to index: Int, natural: Int, isFlexible: Bool, minimum: (Int) -> Int,
    sizeAt: (Int, Int) -> Int?
) -> Int {
    if isFlexible { return max(minimum(index), offer) }
    if offer >= natural { return natural }
    let answer = offer > 0 ? min(offer, sizeAt(index, offer) ?? offer) : 0
    return max(minimum(index), answer)
}

/// An equal share of `amount` among `count` children, in whole cells: the
/// larger half of an odd one, so the earlier of two children takes it.
private func shareOf(_ amount: Int, among count: Int) -> Int {
    guard count > 0, amount > 0 else { return 0 }
    return (amount + count - 1) / count
}

/// `sizes` placed in order until the space runs out: each child at its size,
/// or what is left of the space, charging a gap only between the children
/// placed — so the leading content stays visible, the rest is clipped, and a
/// stack whose gaps alone exceed the space still shows its first children.
/// Children `isFlexible` marks are given nothing.
private func placeInOrder(_ sizes: [Int], isFlexible: [Bool]?, available total: Int, gaps: StackGaps) -> [Int] {
    var result = sizes
    var used = 0
    var lastPlaced: Int?
    for index in result.indices {
        if isFlexible?[index] ?? false {
            result[index] = 0
            continue
        }
        let leadingGap = lastPlaced.map { max(0, gaps.between($0, index)) } ?? 0
        let room = total - used - leadingGap
        guard room > 0 else {
            result[index] = 0
            continue
        }
        let size = min(max(0, result[index]), room)
        result[index] = size
        if size > 0 {
            used += leadingGap + size
            lastPlaced = index
        }
    }
    return result
}

/// The inter-child gaps a stack actually draws, given how many of its children
/// occupy the layout axis.
///
/// `spacing` belongs BETWEEN two children that occupy the axis. A child that
/// occupies none of it draws nothing, and `FrameBuffer.appendHorizontally` /
/// `appendVertically` hand it no gap slot either — their doc comments state the
/// rule: an `EmptyView`, an `Optional.none` branch, any zero-extent child is
/// treated as though it were not in the children list at all. Charging one gap
/// per CHILD instead is what made the eager stacks report a `spacing` per
/// non-rendering child that the assembled buffer never contains:
/// `HStack(spacing: 2) { Text("A"); EmptyView(); Text("B") }` measured 6 wide
/// and drew `"A  B"` (4), and a `Spacer` beside that row was then sized from the
/// inflated claim, so the trailing column stopped two cells short of flush.
///
/// This is the rule `distributeLinearSpace` above applies as well: its overflow
/// branch charges a gap only per PLACED child, and its fitting branches reserve
/// this very count over the children that will occupy the axis. Stated once
/// here so the extent a stack REPORTS, the extent it DISTRIBUTES and the
/// extent it ASSEMBLES cannot drift.
///
/// `spacing` is deliberately not clamped at zero: a negative spacing legitimately
/// subtracts, which is the case `_VStackCore`'s natural-size test guards.
///
/// - Parameters:
///   - occupiedChildren: How many children occupy the layout axis.
///   - spacing: The stack's inter-child spacing.
/// - Returns: `max(0, occupiedChildren - 1) * spacing`.
func totalLinearSpacing(occupiedChildren: Int, spacing: Int) -> Int {
    max(0, occupiedChildren - 1) * spacing
}

/// The gap a stack walk charges before ONE child, given how far along the
/// layout axis the walk has already placed.
///
/// The per-child spelling of ``totalLinearSpacing(occupiedChildren:spacing:)``,
/// for the walks that accumulate as they go — the lazy stacks' measure and
/// fit-checks, `_VStackCore.naturalRowSlots`, the lazy ramp placement — rather
/// than totalling at the end. It is the assemblers' own predicate:
/// `appendHorizontally`'s `priorWidth > 0 && other.width > 0 ? spacing : 0`,
/// and `appendVertically`'s with lines for columns. So there is no gap before a
/// child of no extent, and none before the first child that has any.
///
/// Not `index > 0 ? spacing : 0`, which every one of those walks used to
/// charge: `LazyHStack { Text("A"); EmptyView(); Text("B") }` measured 4 and
/// drew "A B" (3), and at a width of exactly 3 the render walk spent a phantom
/// gap on the `EmptyView` and stopped before "B", which fitted.
///
/// - Parameters:
///   - extent: The child's extent along the layout axis.
///   - placedExtent: The extent the walk has placed so far, gaps included.
///   - spacing: The stack's inter-child spacing.
/// - Returns: `spacing` when both extents are positive, otherwise `0`.
func linearSpacing(before extent: Int, placedExtent: Int, spacing: Int) -> Int {
    placedExtent > 0 && extent > 0 ? spacing : 0
}

// MARK: - Stack Gaps

/// The gaps a stack draws between the children that occupy its axis: every
/// one its `spacing`, or one per pair of neighbours.
///
/// A gap belongs between two children that OCCUPY the axis, as everywhere in
/// this file (``totalLinearSpacing(occupiedChildren:spacing:)``): a child of
/// no extent between them is not their neighbour and takes no part. So a gap
/// is asked of the two children it separates — ``between(_:_:)`` — rather than
/// of a position, and a walk asks it of the last child it placed that occupies
/// the axis and the one it is about to place (``StackGapWalk``).
///
/// Uniform — every gap ``uniform`` — unless a stack resolves `spacing: nil`
/// per pair and a child states a ``ViewSpacing`` of its own; then a gap one of
/// whose two neighbours states one is the distance the pair's facing edges ask
/// for. A gap by pair is never negative, where a stated `spacing` may be.
struct StackGaps {
    /// Every gap, when ``isUniform``; otherwise the gap between two children
    /// neither of which states a preference.
    let uniform: Int

    /// Per child, the spacing it states, or `nil` for one that states none;
    /// `nil` throughout when every gap is ``uniform``.
    private let preferences: [ViewSpacing?]?

    /// The axis the children follow each other along.
    private let axis: Axis

    /// Gaps of `uniform` between every pair.
    init(uniform: Int) {
        self.uniform = uniform
        self.preferences = nil
        self.axis = .horizontal
    }

    /// Gaps by pair: between two children neither of which states a spacing,
    /// `uniform`; otherwise the distance their ``ViewSpacing``s ask for along
    /// `axis`, a child that states none taking the default.
    ///
    /// - Parameters:
    ///   - uniform: The gap between two children that state nothing — the
    ///     distance two default ``ViewSpacing``s ask for along `axis`.
    ///   - preferences: One per child, `nil` where the child states none.
    ///   - axis: The axis the children follow each other along.
    init(uniform: Int, preferences: [ViewSpacing?], along axis: Axis) {
        self.uniform = uniform
        self.preferences = preferences
        self.axis = axis
    }

    /// Whether every gap is ``uniform``.
    var isUniform: Bool { preferences == nil }

    /// The gap between the children at `previous` and `next`, two that occupy
    /// the axis with none that does between them.
    func between(_ previous: Int, _ next: Int) -> Int {
        guard let preferences, preferences[previous] != nil || preferences[next] != nil else { return uniform }
        return (preferences[previous] ?? ViewSpacing()).distance(to: preferences[next] ?? ViewSpacing(), along: axis)
    }

    /// The gaps between the first `count` children for which `occupies` holds,
    /// in order: ``totalLinearSpacing(occupiedChildren:spacing:)`` by pair.
    func total(count: Int, occupies: (Int) -> Bool) -> Int {
        guard !isUniform else {
            return totalLinearSpacing(occupiedChildren: (0..<count).count(where: occupies), spacing: uniform)
        }
        var total = 0
        var previous: Int?
        for index in 0..<count where occupies(index) {
            if let previous { total += between(previous, index) }
            previous = index
        }
        return total
    }
}

/// A walk that places a stack's children in order, and the gap it charges
/// before each: ``linearSpacing(before:placedExtent:spacing:)``'s rule — none
/// before a child of no extent, none before the first that has any — with
/// each gap ``StackGaps/between(_:_:)`` the last child placed that occupies
/// the axis and the next.
struct StackGapWalk {
    let gaps: StackGaps

    /// The last child placed that occupies the axis.
    private var lastOccupying: Int?

    init(_ gaps: StackGaps) {
        self.gaps = gaps
    }

    /// The gap before child `index`, whose extent along the axis is `extent`.
    func gap(before index: Int, extent: Int) -> Int {
        guard extent > 0, let lastOccupying else { return 0 }
        return gaps.between(lastOccupying, index)
    }

    /// Records child `index` as placed at `extent`.
    mutating func place(_ index: Int, extent: Int) {
        if extent > 0 { lastOccupying = index }
    }
}

/// ``distributeLinearSpace(naturalSizes:isFlexible:available:spacing:shares:isSpacer:priorities:minimumSize:statedMinimum:sizeAt:)``
/// for children of more than one ``View/layoutPriority(_:)``: SwiftUI's stack
/// rule, measured (`Tools/SwiftUIProbes/Layout priority/priority.out`).
///
/// The priorities are taken highest first. Each group is offered the space
/// left once every child of a LOWER priority has its minimum size reserved —
/// its size when offered nothing, `…` for a truncating `Text` — and divides
/// it among its own children as a stack of one priority does (`group`: shared
/// for a row, in order for a column); what it does not take passes down. So `HStack { Text(long);
/// Text(other).layoutPriority(1) }` keeps `other` whole and truncates `long`,
/// and a flexible child given a priority leaves its lower siblings no more
/// than their minimums.
///
/// The gaps between the children that occupy the axis are charged first, as
/// the one-priority path charges them.
private func distributeLinearSpace(
    byPriority priorities: [Double], naturalSizes: [Int], isFlexible: [Bool], available: Int, gaps: StackGaps,
    minimum: (Int) -> Int, group: (_ members: [Int], _ available: Int) -> [Int]
) -> [Int] {
    // Every gap between the children that occupy the axis, as the
    // one-priority path charges them.
    let occupies = { (index: Int) in isFlexible[index] || naturalSizes[index] > 0 }
    let allSpacing =
        gaps.isUniform
        ? totalLinearSpacing(
            occupiedChildren: naturalSizes.indices.count(where: occupies), spacing: max(0, gaps.uniform))
        : gaps.total(count: naturalSizes.count, occupies: occupies)
    var remaining = max(0, max(0, available) - allSpacing)
    var result = [Int](repeating: 0, count: naturalSizes.count)
    for level in Set(priorities).sorted(by: >) {
        let members = naturalSizes.indices.filter { priorities[$0] == level }
        var reserved = 0
        for index in naturalSizes.indices where priorities[index] < level { reserved += minimum(index) }
        let sizes = group(members, max(0, remaining - reserved))
        for (offset, index) in members.enumerated() { result[index] = sizes[offset] }
        remaining = max(0, remaining - sizes.reduce(0, +))
    }
    return result
}
