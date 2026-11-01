//  🖥️ TUI — A Terminal UI framework for Swift
//  StackLayouts.swift
//
//  The stacks, as `Layout` VALUES rather than views.
//
//  ``AnyLayout`` shipped without them, which made it an eraser with nothing to
//  erase: the one line every adaptive-layout example is built from —
//
//      AnyLayout(isWide ? HStackLayout() : VStackLayout())
//
//  — did not compile, and both this framework's own doc comment and its Example
//  page had to invent private `Row`/`Column` types to have something to pass.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

// MARK: - Cross-Axis Flexibility

/// Whether any subview but a `Spacer` is flexible on the stack's cross axis.
///
/// The one rule both stacks need and neither can read off `sizes` alone:
/// ``Spacer`` reports BOTH axes flexible because it has no axis input, so the
/// stack it is in has to discount the axis that is not its own. Shared rather
/// than written twice — these two values have drifted apart from each other,
/// and from `_VStackCore`/`_HStackCore`, once already.
@MainActor
private func isFlexibleAcross(
    _ subviews: LayoutSubviews, _ sizes: [ViewSize], _ axis: KeyPath<ViewSize, Bool>
) -> Bool {
    zip(subviews, sizes).contains { subview, size in
        !subview.child.isSpacer && size[keyPath: axis]
    }
}

// MARK: - VStackLayout

/// The vertical stack's arrangement, as a value.
///
/// `VStack` and `VStackLayout` place subviews identically; the difference is
/// only that one is a view and the other is a value you can switch between,
/// keeping one identity — and therefore the subviews' `@State` and focus —
/// across the switch.
///
/// ```swift
/// let layout = isWide ? AnyLayout(HStackLayout()) : AnyLayout(VStackLayout())
/// layout {
///     Text("one")
///     Text("two")
/// }
/// ```
///
/// Spacing is in **rows**; `nil`, the default, is what views prefer between
/// them, which is none, matching `VStack` — see ``ViewSpacing``.
///
/// **Deliberate divergence — `alignment` defaults to `.leading`, not
/// `.center`.** SwiftUI's `VStackLayout` defaults to `.center`, the same as
/// `VStack` itself; TUI's `VStack` keeps that `.center` default too (see
/// its own doc comment) — only this `Layout`-value spelling does not. Owner's
/// decision, 2026-09-20: deliberate, to fit more naturally into the terminal
/// environment, the same top-left-reading reasoning
/// `Documentation/SwiftUI parity/SwiftUI compatibility guide.md` §2.7 gives for a fixed `.frame`'s
/// default; §2.10 states it for this type. Pass an explicit
/// `alignment: .center` for the SwiftUI default.
nonisolated public struct VStackLayout: Layout, Sendable, Equatable {
    /// How subviews line up across the stack's width.
    public var alignment: HorizontalAlignment

    /// Blank rows between subviews, or `nil` for what views prefer.
    public var spacing: Int?

    /// Creates a vertical stack layout.
    ///
    /// - Parameters:
    ///   - alignment: The horizontal alignment (default: `.leading` — a
    ///     deliberate divergence from SwiftUI's `.center`; see the type's own
    ///     doc comment).
    ///   - spacing: Blank rows between subviews, or `nil` (the default) for
    ///     what views prefer between them: none.
    public init(alignment: HorizontalAlignment = .leading, spacing: Int? = nil) {
        self.alignment = alignment
        self.spacing = spacing
    }

    /// The spacing in force: the stated one, or the vertical distance views
    /// prefer.
    @MainActor private var resolvedSpacing: Int {
        spacing ?? ViewSpacing().distance(to: ViewSpacing(), along: .vertical)
    }

    @MainActor public func sizeThatFits(
        proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) -> ViewSize {
        // Natural sizes: the cross axis keeps the proposal, the layout axis
        // is UNSPECIFIED. Proposing the whole extent to every subview made
        // the sum meaningless — a Spacer collapsed to zero, a GeometryReader
        // filled all of it and pushed every later sibling past the viewport.
        let natural = ProposedSize(width: proposal.width, height: nil)
        let sizes = subviews.map { $0.sizeThatFits(natural) }
        // The gaps the distribution reserves: between the subviews that occupy
        // the column, a flexible one even at a natural height of zero
        // (`distributeLinearSpace`). One per pair of subviews counted a gap
        // beside an `EmptyView` member, which is drawn with none.
        let occupying = sizes.count(where: { $0.isHeightFlexible || $0.height > 0 })
        let gaps = totalLinearSpacing(occupiedChildren: occupying, spacing: resolvedSpacing)
        let content = sizes.map(\.height).reduce(0, +) + gaps
        let flexible = sizes.contains { $0.isHeightFlexible }
        let height: Int
        if let proposed = proposal.height {
            // A flexible child absorbs any surplus, so the stack fills what
            // it was offered; otherwise it is its content, clamped to it.
            height = flexible ? proposed : min(content, proposed)
        } else {
            height = content
        }
        // A subview's explicit guide lines the subviews up, as a `VStack`'s
        // rows are, and the column is as wide as the lined-up run.
        let run = guideRun(
            subviews, sizes: sizes.map { (width: $0.width, height: $0.height) }, fixedExtent: nil)
        return ViewSize(
            width: run?.extent ?? sizes.map(\.width).max() ?? 0,
            height: height,
            // Spacers excluded from the CROSS axis, not from both: a Spacer
            // "expands along the major axis of its containing stack layout",
            // and it has no axis input, so it reports both flexible and each
            // stack has to drop the one that is not its own. `_VStackCore`
            // does the same at its `!child.isSpacer` guard; the value spelling
            // reported width-flexible instead and took a share of its row's
            // slack away from a sibling that genuinely wanted it.
            isWidthFlexible: isFlexibleAcross(subviews, sizes, \.isWidthFlexible),
            isHeightFlexible: flexible)
    }

    @MainActor public func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) {
        // The same distribution `VStack` itself uses: the least flexible
        // subviews dealt their share first, spacers what is left, and a
        // trailing clip only where even the minimums do not fit.
        let natural = ProposedSize(width: bounds.width, height: nil)
        let sizes = subviews.map { $0.sizeThatFits(natural) }
        let priorities = subviewPriorities(subviews)
        // With room for every subview, none is offered less than its natural
        // height (``fitsAtNaturalHeights(_:isFlexible:spacing:available:)``).
        let fits = fitsAtNaturalHeights(
            sizes.map(\.height), isFlexible: sizes.map(\.isHeightFlexible), spacing: resolvedSpacing,
            available: bounds.height)
        let heights = distributeLinearSpace(
            naturalSizes: sizes.map(\.height),
            isFlexible: sizes.map(\.isHeightFlexible),
            available: bounds.height,
            spacing: resolvedSpacing,
            isSpacer: { subviews[$0].child.isSpacer },
            priorities: priorities,
            minimumSize: {
                fits ? sizes[$0].height : max(
                    subviews[$0].sizeThatFits(ProposedSize(width: bounds.width, height: 0)).height,
                    statedMinimumLength(of: subviews[$0].child, horizontally: false))
            },
            statedMinimum: { statedMinimumLength(of: subviews[$0].child, horizontally: false) },
            sizeAt: { subviews[$0].sizeThatFits(ProposedSize(width: bounds.width, height: $1)).height })
        let run = guideRun(
            subviews, sizes: zip(sizes, heights).map { (width: $0.width, height: $1) }, fixedExtent: bounds.width)
        var y = bounds.y
        for (index, subview) in subviews.enumerated() {
            let height = heights[index]
            subview.place(
                at: (x: bounds.x + (run?.offsets[index] ?? alignedOffset(for: sizes[index].width, in: bounds.width)), y: y),
                proposal: ProposedSize(width: sizes[index].width, height: height))
            // A gap is charged behind a child that was actually placed — the
            // distributor's own rule, which is what keeps a clipped tail from
            // spending the room the visible children needed.
            y += height + (height > 0 ? resolvedSpacing : 0)
        }
    }

    /// Where a subview of this width starts, given the stack's own width.
    ///
    /// ``HorizontalAlignment/childOffset(childWidth:in:)`` rather than a
    /// switch of its own: the switch had a `default` that sent every alignment
    /// it did not name to the centre, which is right for `.center` and silently
    /// wrong for a CUSTOM guide — the one kind of alignment whose whole purpose
    /// is to sit somewhere those three cases cannot express. `childOffset`
    /// resolves through `ViewDimensions`, so it asks the guide where it wants
    /// to be. It clamps at zero too: a subview wider than the stack starts at
    /// the leading edge and overflows, rather than being pushed off the front.
    @MainActor private func alignedOffset(for width: Int, in available: Int) -> Int {
        alignment.childOffset(childWidth: width, in: available)
    }

    /// The subviews' places across the column where any of them states its
    /// own guide for ``alignment`` with `alignmentGuide`: every guide on one
    /// line, as a `VStack`'s rows are (``horizontalGuideRun(_:sizes:alignment:fixedExtent:minimumExtent:holdsChildrenInside:context:)``).
    /// `nil` where none does — almost every column — and the subviews are
    /// placed by the guide's default instead (``alignedOffset(for:in:)``).
    @MainActor private func guideRun(
        _ subviews: Subviews, sizes: [(width: Int, height: Int)], fixedExtent: Int?
    ) -> AlignmentGuideRun? {
        guard subviews.contains(where: { $0.child.providesAlignmentGuide }) else { return nil }
        return horizontalGuideRun(
            subviews.map(\.child), sizes: sizes, alignment: alignment, fixedExtent: fixedExtent,
            context: subviews.context)
    }
}

// MARK: - HStackLayout

/// The horizontal stack's arrangement, as a value. See ``VStackLayout``.
///
/// Spacing is in **columns**; `nil`, the default, is what views prefer between
/// them, which is one column — `HStack`'s, because two words with no cell
/// between them read as one word.
///
/// **Deliberate divergence — `alignment` defaults to `.top`, not `.center`.**
/// See ``VStackLayout``'s doc comment: the same divergence, the same owner
/// decision (2026-09-20), and the same reasoning — `.center` is SwiftUI's
/// default (matching `HStack`, which TUI's own `HStack` keeps), but this
/// `Layout`-value spelling defaults to `.top` instead, to fit more naturally
/// into the terminal environment. See
/// `Documentation/SwiftUI parity/SwiftUI compatibility guide.md` §2.10.
nonisolated public struct HStackLayout: Layout, Sendable, Equatable {
    /// How subviews line up across the stack's height.
    public var alignment: VerticalAlignment

    /// Blank columns between subviews, or `nil` for what views prefer.
    public var spacing: Int?

    /// Creates a horizontal stack layout.
    ///
    /// - Parameters:
    ///   - alignment: The vertical alignment (default: `.top` — a deliberate
    ///     divergence from SwiftUI's `.center`; see the type's own doc
    ///     comment).
    ///   - spacing: Blank columns between subviews, or `nil` (the default)
    ///     for what each pair of neighbours prefers: one column between two
    ///     views, none beside a custom ``Layout`` that asks for none.
    public init(alignment: VerticalAlignment = .top, spacing: Int? = nil) {
        self.alignment = alignment
        self.spacing = spacing
    }

    /// The spacing in force: the stated one, or the horizontal distance views
    /// prefer.
    @MainActor private var resolvedSpacing: Int {
        spacing ?? ViewSpacing().distance(to: ViewSpacing(), along: .horizontal)
    }

    @MainActor public func sizeThatFits(
        proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) -> ViewSize {
        // See `VStackLayout.sizeThatFits` — same reasoning, other axis.
        let natural = ProposedSize(width: nil, height: proposal.height)
        let sizes = subviews.map { $0.sizeThatFits(natural) }
        // See `VStackLayout.sizeThatFits` — the gaps the distribution reserves,
        // each between the two subviews it separates.
        let gaps = gaps(between: subviews).total(count: subviews.count) {
            sizes[$0].isWidthFlexible || sizes[$0].width > 0
        }
        let content = sizes.map(\.width).reduce(0, +) + gaps
        let flexible = sizes.contains { $0.isWidthFlexible }
        let width: Int
        if let proposed = proposal.width {
            width = flexible ? proposed : min(content, proposed)
        } else {
            width = content
        }
        // See `VStackLayout.sizeThatFits` — a subview's explicit guide lines
        // the subviews up, other axis.
        let run = guideRun(
            subviews, sizes: sizes.map { (width: $0.width, height: $0.height) }, fixedExtent: nil)
        return ViewSize(
            width: width,
            height: run?.extent ?? sizes.map(\.height).max() ?? 0,
            isWidthFlexible: flexible,
            // See `VStackLayout.sizeThatFits` — same exclusion, other axis.
            // `_HStackCore` makes it by handling spacers in a branch that
            // never touches its `fillsHeight`.
            isHeightFlexible: isFlexibleAcross(subviews, sizes, \.isHeightFlexible))
    }

    @MainActor public func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) {
        // See `VStackLayout.placeSubviews` — same distribution, other axis.
        let natural = ProposedSize(width: nil, height: bounds.height)
        let sizes = subviews.map { $0.sizeThatFits(natural) }
        let priorities = subviewPriorities(subviews)
        let gaps = gaps(between: subviews)
        let widths = distributeLinearSpace(
            naturalSizes: sizes.map(\.width),
            isFlexible: sizes.map(\.isWidthFlexible),
            available: bounds.width,
            gaps: gaps,
            isSpacer: { subviews[$0].child.isSpacer },
            priorities: priorities,
            minimumSize: {
                max(
                    subviews[$0].sizeThatFits(ProposedSize(width: 0, height: bounds.height)).width,
                    statedMinimumLength(of: subviews[$0].child, horizontally: true))
            },
            statedMinimum: { statedMinimumLength(of: subviews[$0].child, horizontally: true) },
            sizeAt: { subviews[$0].sizeThatFits(ProposedSize(width: $1, height: bounds.height)).width })
        // Each gap is the one between the last subview that took any width and
        // the next that takes some — the distribution's own rule, by pair
        // (`StackGapWalk`), as `_HStackCore` walks it. Charged after every
        // subview that took width, a gap by pair was asked of a subview and its
        // immediate successor, which an `EmptyView` member between two others
        // is: the row reserved one gap and placed another.
        let run = guideRun(
            subviews, sizes: zip(widths, sizes).map { (width: $0, height: $1.height) }, fixedExtent: bounds.height)
        var walk = StackGapWalk(gaps)
        var x = bounds.x
        for (index, subview) in subviews.enumerated() {
            let width = widths[index]
            x += walk.gap(before: index, extent: width)
            walk.place(index, extent: width)
            subview.place(
                at: (x: x, y: bounds.y + (run?.offsets[index] ?? alignedOffset(for: sizes[index].height, in: bounds.height))),
                proposal: ProposedSize(width: width, height: sizes[index].height))
            x += width
        }
    }

    /// The gaps between `subviews`: every one ``spacing``, or — when it is
    /// `nil` — the distance each pair of neighbours' ``LayoutSubview/spacing``
    /// asks for, as ``HStack``'s (decisions B20).
    ///
    /// Asked of no subview where the content's type holds nothing that can
    /// state a preference (``LayoutSubviews/mayStateSpacing``), as an
    /// `HStack`'s row is — which is almost every row.
    @MainActor func gaps(between subviews: Subviews) -> StackGaps {
        guard spacing == nil, subviews.mayStateSpacing else { return StackGaps(uniform: resolvedSpacing) }
        return StackGaps(uniform: resolvedSpacing, stating: subviews.children, along: .horizontal, context: subviews.context)
    }

    /// See ``VStackLayout/alignedOffset(for:in:)`` — same reasoning, other axis.
    @MainActor private func alignedOffset(for height: Int, in available: Int) -> Int {
        alignment.childOffset(childHeight: height, in: available)
    }

    /// See ``VStackLayout/guideRun(_:sizes:fixedExtent:)`` — same rule, other
    /// axis (``verticalGuideRun(_:sizes:alignment:fixedExtent:minimumExtent:holdsChildrenInside:context:)``).
    @MainActor private func guideRun(
        _ subviews: Subviews, sizes: [(width: Int, height: Int)], fixedExtent: Int?
    ) -> AlignmentGuideRun? {
        guard subviews.contains(where: { $0.child.providesAlignmentGuide }) else { return nil }
        return verticalGuideRun(
            subviews.map(\.child), sizes: sizes, alignment: alignment, fixedExtent: fixedExtent,
            context: subviews.context)
    }
}

// MARK: - Published Axis

/// The two stack layouts publish their axis to their subviews, exactly as
/// `_VStackCore` and `_HStackCore` do.
///
/// Placing subviews identically to `VStack`/`HStack` is not the whole contract:
/// a ``Divider`` reads the axis to choose its orientation AND its flex flags, so
/// a row layout that published none handed the rule the width-flexible
/// horizontal spelling, which then absorbed the row's entire slack.
///
/// `ZStackLayout` is absent on purpose: a ZStack has no axis, and a divider in
/// one is the horizontal rule it is outside any stack — which is what a `nil`
/// axis already means.
@MainActor extension VStackLayout {
    /// The stacks keep the default guide merge.
    public static var _definesExplicitAlignment: Bool { false }

    /// A vertical stack orientation.
    public static var layoutProperties: LayoutProperties {
        var properties = LayoutProperties()
        properties.stackOrientation = .vertical
        return properties
    }
}

@MainActor extension HStackLayout {
    /// The stacks keep the default guide merge.
    public static var _definesExplicitAlignment: Bool { false }

    /// A horizontal stack orientation.
    public static var layoutProperties: LayoutProperties {
        var properties = LayoutProperties()
        properties.stackOrientation = .horizontal
        return properties
    }
}

// MARK: - Grid Rows Under a Stack Layout

/// A `ForEach` of grid rows is cells under a stack layout, as it is under
/// `GridLayout`, so switching the two through `AnyLayout` keeps each cell's
/// identity and its `@State`.
@MainActor extension VStackLayout: WholeGridRowExpanding {
    package var expandsWholeGridRows: Bool { true }
}

/// See ``VStackLayout``'s conformance.
@MainActor extension HStackLayout: WholeGridRowExpanding {
    package var expandsWholeGridRows: Bool { true }
}

/// See ``VStackLayout``'s conformance.
@MainActor extension ZStackLayout: WholeGridRowExpanding {
    package var expandsWholeGridRows: Bool { true }
}

// MARK: - The stacks' associated types, spelled out

// SwiftUI's stack layouts name both: a stack's cache is its own business and
// it animates nothing of its own, so `HStackLayout.Cache` and
// `HStackLayout.AnimatableData` are things SwiftUI source can write. Here the
// cache is `Void` — a stack recomputes from its subviews — and the animatable
// data is empty, as SwiftUI's is.

@MainActor extension VStackLayout: Animatable {
    /// A stack layout recomputes from its subviews and caches nothing.
    public typealias Cache = Void
    /// A stack layout animates nothing of its own.
    public typealias AnimatableData = EmptyAnimatableData
}

@MainActor extension HStackLayout: Animatable {
    /// A stack layout recomputes from its subviews and caches nothing.
    public typealias Cache = Void
    /// A stack layout animates nothing of its own.
    public typealias AnimatableData = EmptyAnimatableData
}

@MainActor extension ZStackLayout: Animatable {
    /// A stack layout recomputes from its subviews and caches nothing.
    public typealias Cache = Void
    /// A stack layout animates nothing of its own.
    public typealias AnimatableData = EmptyAnimatableData
}

// MARK: - ZStackLayout

/// The overlay stack's arrangement, as a value. See ``VStackLayout``.
///
/// Every subview is placed at the same origin, in declaration order — which is
/// draw order, so the last one written is on top. ``Layout`` permits that
/// deliberately: a layout may place its subviews overlapping.
///
/// **Deliberate divergence — `alignment` defaults to `.topLeading`, not
/// `.center`.** SwiftUI's `ZStackLayout` defaults to `.center`, matching
/// `ZStack`; TUI's `ZStack` keeps that `.center` default too — only this
/// `Layout`-value spelling does not. Owner's decision, 2026-09-20: deliberate,
/// to fit more naturally into the terminal environment (the same reasoning as
/// ``VStackLayout``'s and ``HStackLayout``'s alignment defaults — see
/// `Documentation/SwiftUI parity/SwiftUI compatibility guide.md` §2.10).
nonisolated public struct ZStackLayout: Layout, Sendable, Equatable {
    /// Where subviews sit within the stack's own frame.
    public var alignment: Alignment

    /// The stacks keep the default guide merge.
    @MainActor public static var _definesExplicitAlignment: Bool { false }

    /// Creates an overlay layout.
    ///
    /// - Parameter alignment: Where subviews sit (default: `.topLeading` — a
    ///   deliberate divergence from SwiftUI's `.center`, which is what
    ///   `ZStack` itself still defaults to; see the type's own doc comment).
    public init(alignment: Alignment = .topLeading) {
        self.alignment = alignment
    }

    @MainActor public func sizeThatFits(
        proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) -> ViewSize {
        let sizes = subviews.map { $0.sizeThatFits(proposal) }
        // A subview's explicit guide lines the layers up on that axis, as a
        // `ZStack`'s are, and the stack is as large as the lined-up run.
        let (across, down) = guideRuns(
            subviews, sizes: sizes.map { (width: $0.width, height: $0.height) }, bounds: nil)
        return ViewSize(
            width: across?.extent ?? sizes.map(\.width).max() ?? 0,
            height: down?.extent ?? sizes.map(\.height).max() ?? 0)
    }

    @MainActor public func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) {
        let sizes = subviews.map { $0.sizeThatFits(proposal) }
        let (across, down) = guideRuns(
            subviews, sizes: sizes.map { (width: $0.width, height: $0.height) }, bounds: bounds)
        for (index, subview) in subviews.enumerated() {
            let size = sizes[index]
            subview.place(
                at: (
                    x: bounds.x
                        + (across?.offsets[index]
                            ?? alignment.horizontal.childOffset(childWidth: size.width, in: bounds.width)),
                    y: bounds.y
                        + (down?.offsets[index]
                            ?? alignment.vertical.childOffset(childHeight: size.height, in: bounds.height))
                ),
                proposal: proposal)
        }
    }

    /// The layers' places across and down where any of them states its own
    /// guide for that half of ``alignment`` — see
    /// ``VStackLayout/guideRun(_:sizes:fixedExtent:)``; each `nil` where none
    /// does, and the layers are placed by the guide's default on that axis.
    @MainActor private func guideRuns(
        _ subviews: Subviews, sizes: [(width: Int, height: Int)], bounds: CellRect?
    ) -> (across: AlignmentGuideRun?, down: AlignmentGuideRun?) {
        guard subviews.contains(where: { $0.child.providesAlignmentGuide }) else { return (nil, nil) }
        let children = subviews.map(\.child)
        return (
            horizontalGuideRun(
                children, sizes: sizes, alignment: alignment.horizontal, fixedExtent: bounds?.width,
                context: subviews.context),
            verticalGuideRun(
                children, sizes: sizes, alignment: alignment.vertical, fixedExtent: bounds?.height,
                context: subviews.context)
        )
    }
}

/// Each subview's ``LayoutSubview/priority``, or `nil` when every one is `0`,
/// for the stack layouts' distribution, as ``layoutPriorities(of:)`` is for the
/// stacks'.
@MainActor
func subviewPriorities(_ subviews: LayoutSubviews) -> [Double]? {
    let priorities = subviews.map(\.priority)
    return priorities.contains { $0 != 0 } ? priorities : nil
}
