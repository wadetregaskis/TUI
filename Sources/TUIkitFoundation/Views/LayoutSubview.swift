//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LayoutSubview.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Placement Sink

/// Where ``LayoutSubview/place(at:anchor:proposal:)`` records its decisions.
///
/// `LayoutSubview` is a value type whose `place` is non-mutating (SwiftUI's
/// shape, and the one that lets a layout write `subviews[i].place(…)` while
/// iterating), so the decisions have to land somewhere shared. This is that
/// somewhere: one instance per render pass, owned by `_LayoutCore`.
@MainActor
final class LayoutPlacements {
    /// The placement recorded for a subview index, in the order placed —
    /// placement order is draw order, so a layout can deliberately overlap.
    private(set) var entries: [(index: Int, x: Int, y: Int, proposal: ProposedSize)] = []

    func record(index: Int, x: Int, y: Int, proposal: ProposedSize) {
        entries.append((index, x, y, proposal))
    }
}

// MARK: - Layout Subview

/// A proxy for one of the views a ``Layout`` arranges.
///
/// A layout measures a subview through ``sizeThatFits(_:)`` or
/// ``dimensions(in:)``, then positions it with one of the `place` methods. A
/// subview that is never placed is not drawn.
@MainActor
public struct LayoutSubview: @MainActor Equatable {
    /// This subview's position in its ``LayoutSubviews`` collection.
    let index: Int

    /// The wrapped child.
    package let child: ChildView

    /// The context children measure and render in.
    let context: RenderContext

    /// Where `place` records its decisions.
    let placements: LayoutPlacements

    /// The element ids the container's `ForEach` rows are implicitly tagged
    /// with, asked only by ``containerValues``.
    let rowIDs: FlattenedRowIDs<AnyHashable>

    /// This subview's index among the children `rowIDs` was built over —
    /// ``index`` itself unless a grid row was taken apart into cells.
    let rowIndex: Int

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.index == rhs.index && lhs.placements === rhs.placements
    }

    // MARK: - Reading a Subview

    /// The value this subview set for `key`, or the key's default.
    public subscript<K: LayoutValueKey>(key: K.Type) -> K.Value {
        guard let provider = child.wrappedView as? LayoutValueProviding,
            let value = provider.layoutValue(for: ObjectIdentifier(K.self)) as? K.Value
        else { return K.defaultValue }
        return value
    }

    /// The size this subview needs for `proposal`.
    ///
    /// Returns TUIkit's ``ViewSize`` rather than a bare size: it carries
    /// `isWidthFlexible` / `isHeightFlexible`, which is what SwiftUI layouts
    /// infer by probing three times with `.zero`, `.unspecified` and
    /// `.infinity`. `.width` and `.height` read the same either way.
    public func sizeThatFits(_ proposal: ProposedSize) -> ViewSize {
        child.measure(proposal: proposal, context: context)
    }

    /// This subview's size and alignment guides for `proposal`.
    ///
    /// Guides a subview set with
    /// ``View/alignmentGuide(_:computeValue:)-(HorizontalAlignment,_)`` are
    /// carried through, so `subview.dimensions(in: p)[.leading]` reports what
    /// the subview asked for rather than the guide's default.
    public func dimensions(in proposal: ProposedSize) -> ViewDimensions {
        let size = child.measure(proposal: proposal, context: context)
        let bare = ViewDimensions(width: size.width, height: size.height)
        guard child.providesAlignmentGuide, let provider = alignmentGuideProvider(of: child.wrappedView)
        else { return bare }
        var explicit: [AlignmentKey: Double] = [:]
        for key in provider.explicitAlignmentGuideKeys {
            explicit[key] = provider.explicitAlignmentGuide(for: key, in: bare)
        }
        return ViewDimensions(width: size.width, height: size.height, explicitGuides: explicit)
    }

    /// The spacing this subview prefers between itself and the next view.
    ///
    /// A ``ViewSpacing``: for every view, one column beside it and no row above
    /// or below, which is what TUIkit's stacks put between views; for a
    /// subview that is itself a ``Layout``, what its
    /// ``Layout/spacing(subviews:cache:)`` says — through the wrappers that
    /// move none of its edges, and through padding on the edges it does not
    /// pad, as SwiftUI's is.
    public var spacing: ViewSpacing {
        statedSpacing(of: child, context: context) ?? ViewSpacing()
    }

    /// The container values associated with this subview.
    ///
    /// What ``View/containerValue(_:_:)`` and ``View/tag(_:includeOptional:)``
    /// wrote on it, read through any modifiers that are not containers; a
    /// `ForEach` row is also tagged with its element's `id`, unless it tags
    /// itself. A value written inside a container this subview holds — a
    /// `VStack`, another layout — is not this subview's: it stops there.
    public var containerValues: ContainerValues {
        ContainerValues(of: child, implicitTag: rowIDs.elementID(ofChildAt: rowIndex))
    }

    // MARK: - Placing a Subview

    /// Places this subview so that `anchor` lands on `position`.
    ///
    /// The SwiftUI-shaped placement. `position` is a whole cell; `anchor` is
    /// fractional, because it is multiplied by the subview's size and then
    /// **floored once** to a cell — the arithmetic ``AlignmentID`` explains at
    /// length. Doing that subtraction yourself against a pre-floored midpoint
    /// floors twice and lands a cell off in a quarter of cases, which is why
    /// ``CellRect`` has no `midX`. When the target is a region rather than a
    /// point, prefer ``place(in:anchor:proposal:)``.
    ///
    /// - Parameters:
    ///   - position: The cell `anchor` should land on, in the bounds passed to
    ///     `placeSubviews`.
    ///   - anchor: The point *within the subview* that meets `position`.
    ///     Defaults to `.topLeading`, which needs no arithmetic at all.
    ///   - proposal: The size to offer the subview.
    public func place(
        at position: (x: Int, y: Int),
        anchor: UnitPoint = .topLeading,
        proposal: ProposedSize
    ) {
        let size = child.measure(proposal: proposal, context: context)
        let x = Int((Double(position.x) - anchor.x * Double(size.width)).rounded(.down))
        let y = Int((Double(position.y) - anchor.y * Double(size.height)).rounded(.down))
        placements.record(index: index, x: x, y: y, proposal: proposal)
    }

    /// Places this subview within `bounds` at `anchor`.
    ///
    /// TUIkit-specific, and the one to reach for when the answer is "centre
    /// this in that" — the overwhelmingly common case, and the one that is easy
    /// to get wrong by hand. The subview's anchor point meets the region's, in
    /// a single flooring step, and the result is clamped inside the region so a
    /// subview larger than its bounds is never pushed off the leading edge.
    ///
    /// - Parameters:
    ///   - bounds: The region to place within.
    ///   - anchor: The point of both the subview and the region that meet.
    ///   - proposal: The size to offer the subview.
    public func place(in bounds: CellRect, anchor: UnitPoint, proposal: ProposedSize) {
        let size = child.measure(proposal: proposal, context: context)
        let x = Int((anchor.x * Double(bounds.width - size.width)).rounded(.down))
        let y = Int((anchor.y * Double(bounds.height - size.height)).rounded(.down))
        placements.record(
            index: index,
            x: bounds.x + min(max(0, x), max(0, bounds.width - size.width)),
            y: bounds.y + min(max(0, y), max(0, bounds.height - size.height)),
            proposal: proposal)
    }
}

// MARK: - Layout Subviews

/// The collection of views a ``Layout`` arranges.
///
/// A `RandomAccessCollection` of ``LayoutSubview``, so the usual `for`, `map`,
/// `enumerated()` and slicing all work.
@MainActor
public struct LayoutSubviews: @MainActor RandomAccessCollection {
    public typealias Element = LayoutSubview
    public typealias Index = Int
    public typealias Indices = Range<Int>

    let children: [ChildView]
    let context: RenderContext
    let placements: LayoutPlacements

    /// The element id of each looped child, resolved only when a subview's
    /// ``LayoutSubview/containerValues`` asks.
    let rowIDs: FlattenedRowIDs<AnyHashable>

    /// For each child, its index among the children `rowIDs` was built over,
    /// when a whole grid row was taken apart into cells; `nil` when the two
    /// lists are one.
    let sourceIndices: [Int]?

    init(
        children: [ChildView], context: RenderContext, placements: LayoutPlacements,
        rowIDs: FlattenedRowIDs<AnyHashable>, sourceIndices: [Int]? = nil
    ) {
        self.children = children
        self.context = context
        self.placements = placements
        self.rowIDs = rowIDs
        self.sourceIndices = sourceIndices
    }

    public var startIndex: Int { children.startIndex }
    public var endIndex: Int { children.endIndex }

    public subscript(index: Int) -> LayoutSubview {
        LayoutSubview(
            index: index, child: children[index], context: context, placements: placements,
            rowIDs: rowIDs, rowIndex: sourceIndices?[index] ?? index)
    }

    /// The explicit values the placed subviews give `query`'s guide, each
    /// moved by where it was placed, merged by the guide's rule — the default
    /// ``Layout/explicitAlignment(of:in:proposal:subviews:cache:)-(HorizontalAlignment,_,_,_,_)``.
    /// A subview placed twice counts twice; one never placed is not drawn and
    /// counts not at all.
    package func mergedExplicitGuide(_ query: AlignmentGuideQuery) -> Double? {
        let entries = placements.entries
        let placedChildren = entries.map { children[$0.index] }
        let frames = entries.map { entry -> (x: Int, y: Int, width: Int, height: Int) in
            let size = children[entry.index].measure(proposal: entry.proposal, context: context)
            return (
                x: entry.x, y: entry.y,
                width: Swift.min(size.width, entry.proposal.width ?? size.width),
                height: Swift.min(size.height, entry.proposal.height ?? size.height)
            )
        }
        return TUIkitFoundation.mergedExplicitGuide(query, of: placedChildren, frames: frames, context: context)
    }

    /// Every subview's spacing preference merged on every edge, or
    /// ``ViewSpacing/zero`` when there are none — the default
    /// ``Layout/spacing(subviews:cache:)``, the grid's included.
    ///
    /// Merged from the default rather than from `.zero`: a stated edge
    /// outweighs a default one (``ViewSpacing``), so starting from `.zero` would
    /// answer `.zero` for every layout.
    package var mergedSpacing: ViewSpacing {
        guard !isEmpty else { return .zero }
        return reduce(into: ViewSpacing()) { $0.formUnion($1.spacing) }
    }

    /// The layout direction inherited by the container view — always
    /// left-to-right, until TUIkit supports right-to-left (see
    /// ``EnvironmentValues/layoutDirection``).
    public var layoutDirection: LayoutDirection {
        context.environment.layoutDirection
    }
}
