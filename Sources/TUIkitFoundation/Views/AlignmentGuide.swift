//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AlignmentGuide.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Guide Provider

/// A view carrying explicit alignment guides set with
/// ``View/alignmentGuide(_:computeValue:)-(HorizontalAlignment,_)``.
///
/// Implemented by the wrapper ``View/alignmentGuide(_:computeValue:)-(HorizontalAlignment,_)``
/// produces. Container views that align siblings — the stacks above all — read
/// it to learn where a child wants its guide, instead of assuming the guide's
/// default position.
@MainActor
public protocol AlignmentGuideProviding {
    /// The explicit value this view sets for `key`, evaluated against the size
    /// the view laid out at — or `nil` when it sets no value for that guide.
    func explicitAlignmentGuide(for key: AlignmentKey, in dimensions: ViewDimensions) -> Double?

    /// Every guide this view sets, including any set by wrappers it contains.
    ///
    /// A container that aligns on ONE guide only ever asks about that one, so
    /// it uses ``explicitAlignmentGuide(for:in:)``. A ``Layout`` handed the
    /// subview through ``LayoutSubview/dimensions(in:)`` has to hand back a
    /// whole ``ViewDimensions``, which means knowing what to fill it with —
    /// guides are keyed by arbitrary `AlignmentID` types, so there is nothing
    /// to enumerate unless the view that set them says so.
    var explicitAlignmentGuideKeys: [AlignmentKey] { get }
}

// MARK: - Guide View

/// A view that carries an explicit alignment guide for its container to read.
///
/// `_AlignmentGuideView` is produced by ``View/alignmentGuide(_:computeValue:)-(HorizontalAlignment,_)``.
/// It renders transparently as its wrapped content; the guide is metadata
/// consumed by aligning containers.
///
/// - Important: Framework infrastructure. Created by
///   ``View/alignmentGuide(_:computeValue:)-(HorizontalAlignment,_)``; do not instantiate directly.
public struct _AlignmentGuideView<Content: View>: View {
    /// Which guide this view overrides.
    let key: AlignmentKey

    /// The guide's position, given the view's own dimensions.
    let computeValue: (ViewDimensions) -> Double

    /// The wrapped content view.
    let content: Content

    public var body: some View {
        content
    }

    /// Static witness used by the child-layout path to detect a guide wrapper
    /// without a runtime `as? AlignmentGuideProviding` cast. See
    /// `_providesAlignmentGuide`.
    public static var _providesAlignmentGuide: Bool { true }
}

/// The view that answers for `view`'s explicit guides: `view` itself, or —
/// through a `Subview` placed in a container — the member it stands for
/// (`LayoutTraitsForwarding`).
///
/// Asked by a `Layout`'s ``LayoutSubview/dimensions(in:)`` of the view it
/// places, and by a guide wrapper of the view it wraps — so a guide written
/// on a proxy (`$0.alignmentGuide(.leading) { … }`) adds to the member's own
/// rather than hiding them, as the stacks' path already had it: they reach a
/// member's guides through `AlignmentGuideQuerying`, which `Subview` forwards.
@MainActor
func alignmentGuideProvider(of view: any View) -> AlignmentGuideProviding? {
    if let provider = view as? AlignmentGuideProviding { return provider }
    guard let proxy = view as? LayoutTraitsForwarding else { return nil }
    return alignmentGuideProvider(of: proxy.forwardedChild.wrappedView)
}

extension _AlignmentGuideView: AlignmentGuideProviding {
    public var explicitAlignmentGuideKeys: [AlignmentKey] {
        guard Content._providesAlignmentGuide,
            let inner = alignmentGuideProvider(of: content)?.explicitAlignmentGuideKeys
        else { return [key] }
        // This wrapper's own guide first: a repeated key resolves to the
        // outermost value, and building the dictionary in this order lets the
        // later (inner) write be the one that loses.
        return [key] + inner.filter { $0 != key }
    }

    public func explicitAlignmentGuide(
        for key: AlignmentKey, in dimensions: ViewDimensions
    ) -> Double? {
        if key == self.key { return computeValue(dimensions) }
        // Chained guides (`.alignmentGuide(.leading){…}.alignmentGuide(.top){…}`)
        // nest, so a wrapper that cannot answer asks the one it wraps. The
        // OUTERMOST wrapper wins for a repeated guide, matching the usual
        // modifier rule that the later application is the one in force.
        guard Content._providesAlignmentGuide else { return nil }
        return alignmentGuideProvider(of: content)?.explicitAlignmentGuide(for: key, in: dimensions)
    }
}

// MARK: - Modifier

extension View {
    /// Sets this view's horizontal alignment guide to an explicit position.
    ///
    /// A container aligns its children by lining up one guide per child. Left
    /// alone, that guide sits where its ``AlignmentID`` puts it — `.leading` at
    /// the leading edge, `.center` at the middle. This modifier moves it, so a
    /// view can hang off the alignment line rather than sit on it:
    ///
    /// ```swift
    /// VStack(alignment: .leading) {
    ///     Text("•").alignmentGuide(.leading) { d in d[.trailing] }
    ///     Text("bullet hangs left of this")
    /// }
    /// ```
    ///
    /// Because the bullet's guide is now its *trailing* edge, the stack shifts
    /// everything else right to meet it — and the stack becomes wider than its
    /// widest child, which is the whole point of the mechanism.
    ///
    /// ## How far a guide travels
    ///
    /// As in SwiftUI, a guide travels up through the views that place their
    /// content at a known offset, each moving it by that offset: `VStack`,
    /// `HStack` and `ZStack` report the guides their children set (merged by
    /// the alignment's ``HorizontalAlignment/combineExplicit(_:)`` when several
    /// do), and `.padding` reports its content's moved by the inset. So a
    /// decimal-point guide set on a `Text` inside each row of a column aligns
    /// the rows on the point. A custom ``Layout`` reports the custom guides its
    /// subviews set, or one of its own
    /// (``Layout/explicitAlignment(of:in:proposal:subviews:cache:)-(HorizontalAlignment,_,_,_,_)``).
    ///
    /// - Important: It stops at any other modifier written after it
    ///   (`.border()`, a `.frame`, `.offset`), and at a view type of your own
    ///   whose `body` is one view: a guide inside such a `struct Row: View`'s
    ///   `body` does not travel out of `Row`. Put the guide on the view the
    ///   container places, or on the outside of your view. A guide is a
    ///   closure evaluated against the dimensions the view laid out at, and a
    ///   wrapper that does not translate it would report a position from the
    ///   wrong coordinate space; a view of your own states nothing about what
    ///   its body holds. A body of several views is taken apart, so each of
    ///   its views is the child of the container that takes it apart, and
    ///   that container honours its guide — but goes no further: a stack
    ///   around that container is not told a guide is inside (the view's
    ///   type answers `false` to `View/_providesAlignmentGuide`), where in
    ///   SwiftUI the guide travels on up (decisions D1S, B-D1S-6).
    ///
    /// - Parameters:
    ///   - g: The guide to set.
    ///   - computeValue: The guide's position within this view, given the
    ///     view's dimensions.
    /// - Returns: A view carrying the explicit guide.
    public func alignmentGuide(
        _ g: HorizontalAlignment,
        computeValue: @escaping (ViewDimensions) -> Double
    ) -> some View {
        _AlignmentGuideView(key: g.key, computeValue: computeValue, content: self)
    }

    /// Sets this view's vertical alignment guide to an explicit position.
    ///
    /// The vertical twin of ``View/alignmentGuide(_:computeValue:)-(HorizontalAlignment,_)``: it
    /// moves the guide an `HStack` (or a `ZStack`'s vertical component) lines
    /// its children up on.
    ///
    /// ```swift
    /// HStack(alignment: .top) {
    ///     Text("drops").alignmentGuide(.top) { _ in -1 }
    ///     Text("stays")
    /// }
    /// ```
    ///
    /// - Important: Apply this as the **outermost** modifier on the child —
    ///   see the horizontal overload for why.
    ///
    /// - Parameters:
    ///   - g: The guide to set.
    ///   - computeValue: The guide's position within this view, given the
    ///     view's dimensions.
    /// - Returns: A view carrying the explicit guide.
    public func alignmentGuide(
        _ g: VerticalAlignment,
        computeValue: @escaping (ViewDimensions) -> Double
    ) -> some View {
        _AlignmentGuideView(key: g.key, computeValue: computeValue, content: self)
    }
}

// MARK: - Asking a View for Its Guide

/// One explicit-guide question: which guide, and so along which axis a
/// container translates a child's answer and how it merges several.
enum AlignmentGuideQuery {
    case horizontal(HorizontalAlignment)
    case vertical(VerticalAlignment)

    /// The guide asked about.
    var key: AlignmentKey {
        switch self {
        case .horizontal(let alignment): alignment.key
        case .vertical(let alignment): alignment.key
        }
    }

    /// `value`, a guide position within a child, as a position within the
    /// container that placed the child's origin at `origin`.
    func translated(_ value: Double, by origin: (x: Int, y: Int)) -> Double {
        switch self {
        case .horizontal: value + Double(origin.x)
        case .vertical: value + Double(origin.y)
        }
    }

    /// Several children's explicit values as the container's one:
    /// ``HorizontalAlignment/combineExplicit(_:)`` or
    /// ``VerticalAlignment/combineExplicit(_:)``, SwiftUI's merge.
    func combine(_ values: [Double?]) -> Double? {
        switch self {
        case .horizontal(let alignment): alignment.combineExplicit(values)
        case .vertical(let alignment): alignment.combineExplicit(values)
        }
    }
}

/// A view that answers the explicit-guide question itself, given where it is
/// laid out: a guide wrapper, a container that works its children's guides out
/// through their placements, a padded view.
///
/// The context is what the context-free ``AlignmentGuideProviding`` lacks. A
/// container cannot find its children's guides without resolving and measuring
/// them, and that needs the context it is laid out in.
@MainActor
protocol AlignmentGuideQuerying {
    /// The explicit value this view has for `query`'s guide when laid out at
    /// `dimensions` in `context` — its own context, identity included — or
    /// `nil` when it has none.
    func explicitGuide(
        _ query: AlignmentGuideQuery, in dimensions: ViewDimensions, context: RenderContext
    ) -> Double?
}

/// The explicit value `view` has for `query`'s guide, laid out at `dimensions`
/// in `context` (its own), or `nil` when it has none.
///
/// The static witness (``View/_providesAlignmentGuide``) gates everything: a
/// view whose type cannot hold a guide is answered without a cast. Past it, a
/// view answers itself (``AlignmentGuideQuerying``, or the public
/// ``AlignmentGuideProviding``), or — a framework composite such as `VStack`,
/// whose witness forwards its content's — its `body` is asked, at the identity
/// its body renders at. An app's own views state no witness, so a guide inside
/// one does not travel out of it.
@MainActor
func explicitGuide<V: View>(
    of view: V, _ query: AlignmentGuideQuery, in dimensions: ViewDimensions,
    context: RenderContext
) -> Double? {
    guard V._providesAlignmentGuide else { return nil }
    if let querying = view as? AlignmentGuideQuerying {
        return querying.explicitGuide(query, in: dimensions, context: context)
    }
    if let provider = view as? AlignmentGuideProviding {
        return provider.explicitAlignmentGuide(for: query.key, in: dimensions)
    }
    guard V.Body.self != Never.self, !(view is Renderable) else { return nil }
    // The body as the measure walk evaluates it: `@Environment` resolved and
    // `@State` bound at this view's identity, so it is the body that is drawn.
    resolveEnvironmentProperties(of: view, in: context.environment)
    if let storage = context.stateStorage {
        bindStateProperties(of: view, identity: context.identity, storage: storage)
    }
    return explicitGuide(
        of: view.body, query, in: dimensions, context: context.withChildIdentity(type: V.Body.self))
}

// MARK: - Reading a Child's Guide

extension ChildView {
    /// The explicit value this child has for `query`'s guide when laid out at
    /// `dimensions` in its container's `context`, or `nil` when it has none.
    ///
    /// The stored witness gates the query, so a child with no guide — every
    /// child in almost every tree — costs one `Bool` read. Asked in a measuring
    /// context of the child's own: a query lays out what it asks about, and
    /// must leave nothing behind.
    func explicitGuide(
        _ query: AlignmentGuideQuery, at dimensions: ViewDimensions, context: RenderContext
    ) -> Double? {
        guard providesAlignmentGuide else { return nil }
        var childContext = renderContext(under: context)
        childContext.availableWidth = dimensions.width
        childContext.availableHeight = dimensions.height
        childContext.isMeasuring = true
        return TUIkitFoundation.explicitGuide(of: wrappedView, query, in: dimensions, context: childContext)
    }
}

/// The explicit values `children` give `query`'s guide, each translated into
/// the container by where the child sits, merged by the guide's rule — what a
/// container reports for a guide it does not set itself. `nil` when no child
/// gives one.
@MainActor
func mergedExplicitGuide(
    _ query: AlignmentGuideQuery, of children: [ChildView],
    frames: [(x: Int, y: Int, width: Int, height: Int)], context: RenderContext
) -> Double? {
    var values: [Double?] = []
    values.reserveCapacity(children.count)
    for (child, frame) in zip(children, frames) {
        values.append(
            child.explicitGuide(
                query, at: ViewDimensions(width: frame.width, height: frame.height), context: context
            ).map { query.translated($0, by: (x: frame.x, y: frame.y)) })
    }
    return query.combine(values)
}

extension _AlignmentGuideView: AlignmentGuideQuerying {
    /// This wrapper's own guide, or whatever its content has for any other —
    /// a guide set further in, or one a container inside reports.
    func explicitGuide(
        _ query: AlignmentGuideQuery, in dimensions: ViewDimensions, context: RenderContext
    ) -> Double? {
        if query.key == key { return computeValue(dimensions) }
        return TUIkitFoundation.explicitGuide(
            of: content, query, in: dimensions,
            context: context.withChildIdentity(type: Body.self))
    }
}

// MARK: - Placing a Run of Siblings

/// Where a run of siblings sits on one axis once explicit guides are taken into
/// account.
///
/// This is built **only** when some sibling gives an explicit value for the
/// guide the container aligns on — decided on the VALUES, not on whether a
/// sibling carries a guide at all. Without one, every container keeps the
/// arithmetic it always had: the general guide formula merges the run's guides
/// and floors once *per run*, the per-child rule floors once *per child*, and
/// the two need not agree (a child wider than a fixed region is placed
/// differently, for one). Deciding on the flag instead meant a sibling's
/// `.alignmentGuide(.leading)` switched a `VStack(alignment: .center)` onto the
/// run's arithmetic for a guide nobody had set — and it would have done the
/// same for every container a guide merely passes through.
struct AlignmentGuideRun {
    /// Each child's leading (or top) offset within ``extent``.
    let offsets: [Int]

    /// The extent the run occupies along the axis.
    let extent: Int

    /// Resolves placement from already-merged guide positions.
    ///
    /// Every child's guide is put on one line: the run's merged guide
    /// `max(resolved)`, or the region's own guide when the region is larger and
    /// its guide sits further along. Offsets are then floored — the fraction
    /// only ever exists *between* two guides — and clamped so no child is
    /// placed outside the region.
    ///
    /// - Parameters:
    ///   - resolved: Each child's guide position within itself. A value that is
    ///     not a cell coordinate is taken as the child's own origin — see
    ///     ``coordinate(_:within:)``.
    ///   - sizes: Each child's extent along the axis.
    ///   - fixedExtent: The region's extent when the container does not size to
    ///     content; `nil` to grow to fit the run.
    ///   - minimumExtent: A floor on a content-sized region's extent.
    ///   - regionGuide: The region's own guide, given its final extent.
    static func resolve(
        resolved: [Double],
        sizes: [Int],
        fixedExtent: Int?,
        minimumExtent: Int,
        regionGuide: (Int) -> Double
    ) -> Self {
        // Sanitised BEFORE `merged`, not at the conversions below: one
        // child's non-coordinate poisons every sibling's base through the
        // maximum, and the child that set it gets `∞ - ∞`, i.e. NaN, for its
        // own.
        let positions = zip(resolved, sizes).map { coordinate($0.0, within: $0.1) }
        let merged = positions.max() ?? 0

        // A child's distance from the run's leading edge is how far its guide
        // falls short of the merged one — so the child with the largest guide
        // sits flush and every other is pushed along.
        var bases: [Double] = []
        bases.reserveCapacity(positions.count)
        var contentExtent = 0
        for (index, guide) in positions.enumerated() {
            let base = merged - guide
            bases.append(base)
            contentExtent = max(
                contentExtent, Int(clamping: (base + Double(sizes[index])).rounded(.up)))
        }

        let extent = fixedExtent ?? max(contentExtent, minimumExtent)
        // In a region bigger than the run, the run as a whole still has to be
        // positioned: its guide meets the region's. `max` keeps every offset
        // non-negative when the region's guide sits before the merged one
        // (`.leading` with a guide pushed inward, say).
        let anchor = max(merged, coordinate(regionGuide(extent), within: extent))

        var offsets: [Int] = []
        offsets.reserveCapacity(positions.count)
        for (index, guide) in positions.enumerated() {
            let raw = Int(clamping: (anchor - guide).rounded(.down))
            offsets.append(min(max(0, raw), max(0, extent - sizes[index])))
        }
        return Self(offsets: offsets, extent: extent)
    }

    /// `value` as a cell coordinate within a view of extent `size`.
    ///
    /// A guide is a position INSIDE its own view, so a real one lives in that
    /// view's extent. This is NOT the clamp into the region — that happens per
    /// child further down, exactly as
    /// ``HorizontalAlignment/childOffset(childWidth:in:)`` clamps its result —
    /// it is a filter on values that are not positions at all. A guide is
    /// caller arithmetic: `Double(d.width) / Double(d.height)` on a child that
    /// is legitimately zero-height during a measure pass is `+∞`, `0 / 0` is
    /// NaN, and a runaway expression is a finite astronomical number. Every one
    /// used to reach `Int(_: Double)`, which traps on NaN, on either infinity
    /// and on any magnitude past `Int`'s range — and even a finite one that a
    /// saturating conversion let through would grow a content-sized region to
    /// `Int.max` cells and try to allocate a buffer that wide.
    ///
    /// So a non-finite guide becomes the view's own origin — the position a
    /// view with no guide has; NaN has no order and so no nearer edge to fall
    /// back to. A finite one is held within the view's own geometry, a full
    /// extent of overshoot to either side (which covers aligning one child's
    /// far edge to another's near one) — rather than an arbitrary constant, so
    /// the extent a content-sized run grows to is bounded by the children's
    /// real sizes and never by a magic number.
    private static func coordinate(_ value: Double, within size: Int) -> Double {
        guard value.isFinite else { return 0 }
        let reach = Double(max(1, size))
        return min(max(-reach, value), 2 * reach)
    }
}

/// Whether any of `children` sets an explicit alignment guide.
///
/// The test both guide-run builders open with, hoisted out so a caller can make
/// it BEFORE building the arrays it would otherwise pass in. Every call site was
/// assembling two or three temporary arrays — a spacer-filtered `placed`, its
/// children, and their sizes — to hand to a function whose first line throws
/// them away, and no view sets a guide in the overwhelming majority of stacks.
///
/// A caller that has only the unfiltered children may ask with those: a spacer
/// never provides a guide, so the answer is the same, and a wider set can only
/// ever say "yes" where the narrower one would have said "no" — which costs the
/// arrays, not correctness.
@MainActor
func anyAlignmentGuide(in children: [ChildView]) -> Bool {
    children.contains(where: \.providesAlignmentGuide)
}

/// The horizontal placement of `children`, or `nil` when none of them gives an
/// explicit value for `alignment` and the caller should keep its own
/// arithmetic.
///
/// - Parameters:
///   - children: The children being placed, in order.
///   - sizes: Each child's rendered size, for evaluating its guide.
///   - alignment: The container's alignment.
///   - fixedExtent: The container's width when it does not size to content.
///   - minimumExtent: A floor on a content-sized container's width.
///   - context: The container's context, which a child that is itself a
///     container needs to work out a guide it holds further in.
@MainActor
func horizontalGuideRun(
    _ children: [ChildView],
    sizes: [(width: Int, height: Int)],
    alignment: HorizontalAlignment,
    fixedExtent: Int? = nil,
    minimumExtent: Int = 0,
    context: RenderContext
) -> AlignmentGuideRun? {
    guard children.contains(where: \.providesAlignmentGuide) else { return nil }
    var resolved: [Double] = []
    resolved.reserveCapacity(children.count)
    var anyExplicit = false
    for (child, size) in zip(children, sizes) {
        let dimensions = ViewDimensions(width: size.width, height: size.height)
        if let explicit = child.explicitGuide(.horizontal(alignment), at: dimensions, context: context) {
            anyExplicit = true
            resolved.append(explicit)
        } else {
            resolved.append(alignment[dimensions: dimensions])
        }
    }
    guard anyExplicit else { return nil }
    return .resolve(
        resolved: resolved, sizes: sizes.map(\.width),
        fixedExtent: fixedExtent, minimumExtent: minimumExtent
    ) { extent in
        alignment[dimensions: ViewDimensions(width: extent, height: 0)]
    }
}

// MARK: - Placing a Single Child

/// The horizontal offset at which to place `view` in a fixed-width region so
/// its explicit guide meets the region's — or `nil` when it set no guide.
///
/// The single-child counterpart of the run helpers, for the modifiers that
/// place exactly one child in a region whose size is already decided:
/// `.frame(alignment:)`, `.overlay(alignment:)`, `.background(alignment:)`.
/// There is no run to merge, so the child's guide simply meets the region's.
/// `context` is the one `view` was rendered in.
@MainActor
func horizontalGuidePlacement<V: View>(
    of view: V, size: (width: Int, height: Int), alignment: HorizontalAlignment, in extent: Int,
    context: RenderContext
) -> Int? {
    guard V._providesAlignmentGuide,
        let guide = explicitGuide(
            of: view, .horizontal(alignment),
            in: ViewDimensions(width: size.width, height: size.height), context: context)
    else { return nil }
    return AlignmentGuideRun.resolve(
        resolved: [guide], sizes: [size.width], fixedExtent: extent, minimumExtent: extent
    ) { alignment[dimensions: ViewDimensions(width: $0, height: 0)] }.offsets[0]
}

/// The vertical twin of ``horizontalGuidePlacement(of:size:alignment:in:context:)``.
@MainActor
func verticalGuidePlacement<V: View>(
    of view: V, size: (width: Int, height: Int), alignment: VerticalAlignment, in extent: Int,
    context: RenderContext
) -> Int? {
    guard V._providesAlignmentGuide,
        let guide = explicitGuide(
            of: view, .vertical(alignment),
            in: ViewDimensions(width: size.width, height: size.height), context: context)
    else { return nil }
    return AlignmentGuideRun.resolve(
        resolved: [guide], sizes: [size.height], fixedExtent: extent, minimumExtent: extent
    ) { alignment[dimensions: ViewDimensions(width: 0, height: $0)] }.offsets[0]
}

/// The vertical placement of `children`, or `nil` when none of them gives an
/// explicit value for `alignment`.
///
/// The vertical twin of ``horizontalGuideRun(_:sizes:alignment:fixedExtent:minimumExtent:context:)``.
@MainActor
func verticalGuideRun(
    _ children: [ChildView],
    sizes: [(width: Int, height: Int)],
    alignment: VerticalAlignment,
    fixedExtent: Int? = nil,
    minimumExtent: Int = 0,
    context: RenderContext
) -> AlignmentGuideRun? {
    guard children.contains(where: \.providesAlignmentGuide) else { return nil }
    var resolved: [Double] = []
    resolved.reserveCapacity(children.count)
    var anyExplicit = false
    for (child, size) in zip(children, sizes) {
        let dimensions = ViewDimensions(width: size.width, height: size.height)
        if let explicit = child.explicitGuide(.vertical(alignment), at: dimensions, context: context) {
            anyExplicit = true
            resolved.append(explicit)
        } else {
            resolved.append(alignment[dimensions: dimensions])
        }
    }
    guard anyExplicit else { return nil }
    return .resolve(
        resolved: resolved, sizes: sizes.map(\.height),
        fixedExtent: fixedExtent, minimumExtent: minimumExtent
    ) { extent in
        alignment[dimensions: ViewDimensions(width: 0, height: extent)]
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension _AlignmentGuideView: SingleContentWrapper {
    public var wrappedContent: Content { content }
}
