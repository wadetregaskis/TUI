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
///   ``distributeLinearSpace(naturalSizes:isFlexible:available:spacing:priorities:minimumSizes:)``,
///   which places leading children at their natural size and clips the trailing
///   overflow *at the cell* (a child can be cut mid-content). The reported size
///   is the analytic sum-and-clamp.
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
/// Shared by ``HStack`` (width) and ``VStack`` (height). The algorithm:
///
/// - **Everything fits** — fixed children keep their natural size and
///   flexible children absorb the surplus.
/// - **Space is short** — flexible children are shrunk first.
/// - **Even the fixed content overflows** — flexible children collapse to
///   zero and fixed children are placed in order (leftmost / topmost first)
///   until the space runs out, so the leading content stays visible and the
///   rest is clipped.
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
///   - priorities: Each child's ``View/layoutPriority(_:)``, or `nil` when every
///     one is `0` — the common case, distributed as above. See
///     ``distributeLinearSpace(byPriority:minimumSizes:naturalSizes:isFlexible:available:gaps:)``.
///   - minimumSizes: Each child's size when offered nothing on this axis;
///     read only with `priorities`.
/// - Returns: One allocated size per child; placed sizes + their gaps sum to
///   `<= max(0, available)`.
func distributeLinearSpace(
    naturalSizes: [Int], isFlexible: [Bool], available: Int, spacing: Int = 0,
    priorities: [Double]? = nil, minimumSizes: [Int]? = nil
) -> [Int] {
    distributeLinearSpace(
        naturalSizes: naturalSizes, isFlexible: isFlexible, available: available, gaps: StackGaps(uniform: spacing),
        priorities: priorities, minimumSizes: minimumSizes)
}

/// ``distributeLinearSpace(naturalSizes:isFlexible:available:spacing:priorities:minimumSizes:)`` with
/// the gaps a ``StackGaps`` gives each pair of neighbours, each clamped at zero
/// as the single `spacing` is.
func distributeLinearSpace(
    naturalSizes: [Int], isFlexible: [Bool], available: Int, gaps: StackGaps,
    priorities: [Double]? = nil, minimumSizes: [Int]? = nil
) -> [Int] {
    if let priorities, let minimumSizes {
        return distributeLinearSpace(
            byPriority: priorities, minimumSizes: minimumSizes, naturalSizes: naturalSizes,
            isFlexible: isFlexible, available: available, gaps: gaps)
    }
    let total = max(0, available)
    var result = naturalSizes.map { max(0, $0) }
    let flexIndices = result.indices.filter { isFlexible[$0] }

    var nonFlexTotal = 0
    var flexTotal = 0
    // How many children will OCCUPY the axis: the fitting branches below reserve
    // gaps between those, not one per child. A fixed child of no extent is
    // appended through `appendHorizontally` / `appendVertically`'s
    // contributes-nothing branch and earns no gap, so a gap reserved for it was
    // space no flexible sibling was ever handed — `HStack(spacing: 2) {
    // Text("A"); EmptyView(); Spacer(); Text("B") }` in 20 cells gave the spacer
    // 12 rather than 14, and "B" stopped two short of the edge of a row that
    // reports itself as filling the width. A flexible child counts even at a
    // natural size of zero (a default `Spacer`), because its allocation is the
    // very thing being decided — the carve-out `_VStackCore`'s size makes for a
    // spacer. One the surplus then leaves at zero gives back a gap nothing
    // reclaims, which is the only over-reservation left.
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
    // A gap by pair is never negative (``StackGaps``), so only the one
    // `spacing` needs the clamp.
    let allSpacing =
        gaps.isUniform
        ? totalLinearSpacing(occupiedChildren: occupying, spacing: max(0, gaps.uniform))
        : gaps.total(count: result.count) { isFlexible[$0] || result[$0] > 0 }

    if nonFlexTotal + flexTotal + allSpacing <= total {
        // Everything (content + every gap) fits; flexible children absorb the surplus.
        addLinearSpace(
            total - nonFlexTotal - flexTotal - allSpacing, to: flexIndices, of: &result, weights: nil)
    } else if nonFlexTotal + allSpacing <= total {
        // Fixed content + gaps fit; flexible children share the remainder.
        let weights = flexTotal > 0 ? flexIndices.map { result[$0] } : nil
        for index in flexIndices { result[index] = 0 }
        addLinearSpace(total - nonFlexTotal - allSpacing, to: flexIndices, of: &result, weights: weights)
    } else {
        // Even the fixed content + its gaps overflow: flexible → 0, then place
        // fixed children top-down at their natural size, charging `spacing` only
        // *between* placed children, until the space runs out. Children that
        // don't fit collapse to zero (clipped). Charging spacing per placed
        // child — rather than reserving every gap up front — is what stops the
        // whole stack going blank when the gaps alone would exceed `available`.
        for index in flexIndices { result[index] = 0 }
        var used = 0
        var lastPlaced: Int?
        for index in result.indices where !isFlexible[index] {
            let leadingGap = lastPlaced.map { max(0, gaps.between($0, index)) } ?? 0
            let room = total - used - leadingGap
            if room <= 0 {
                result[index] = 0
                continue
            }
            let size = min(result[index], room)
            result[index] = size
            if size > 0 {
                used += leadingGap + size
                lastPlaced = index
            }
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

/// ``distributeLinearSpace(naturalSizes:isFlexible:available:spacing:priorities:minimumSizes:)``
/// for children of more than one ``View/layoutPriority(_:)``: SwiftUI's stack
/// rule, measured (`Tools/SwiftUIProbes/Layout priority/priority.out`).
///
/// The priorities are taken highest first. Each group is offered the space
/// left once every child of a LOWER priority has its minimum size reserved —
/// its size when offered nothing, `…` for a truncating `Text` — and divides
/// it among its own children as a stack of one priority does; what it does
/// not take passes down. So `HStack { Text(long); Text(other).layoutPriority(1) }`
/// keeps `other` whole and truncates `long`, and a flexible child given a
/// priority leaves its lower siblings no more than their minimums. Within a
/// group nothing changes.
///
/// The gaps between the children that occupy the axis are charged first, as
/// the fitting branches charge them.
private func distributeLinearSpace(
    byPriority priorities: [Double], minimumSizes: [Int], naturalSizes: [Int], isFlexible: [Bool],
    available: Int, gaps: StackGaps
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
        for index in naturalSizes.indices where priorities[index] < level { reserved += max(0, minimumSizes[index]) }
        let sizes = distributeLinearSpace(
            naturalSizes: members.map { naturalSizes[$0] }, isFlexible: members.map { isFlexible[$0] },
            available: max(0, remaining - reserved))
        for (offset, index) in members.enumerated() { result[index] = sizes[offset] }
        remaining = max(0, remaining - sizes.reduce(0, +))
    }
    return result
}
