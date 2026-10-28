//  🖥️ TUI — A Terminal UI framework for Swift
//  Layout.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUICore
import TUIView

// MARK: - Layout

/// A type that arranges a collection of subviews itself.
///
/// Conform to `Layout` when neither a stack nor a frame expresses the
/// arrangement you want, then call the layout like a function:
///
/// ```swift
/// struct Diagonal: Layout {
///     func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
///         let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
///         return ViewSize(
///             width: sizes.reduce(0) { $0 + $1.width },
///             height: sizes.reduce(0) { $0 + $1.height })
///     }
///
///     func placeSubviews(in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()) {
///         var x = bounds.x, y = bounds.y
///         for subview in subviews {
///             subview.place(at: (x: x, y: y), proposal: .unspecified)
///             let size = subview.sizeThatFits(.unspecified)
///             x += size.width
///             y += size.height
///         }
///     }
/// }
///
/// Diagonal {
///     Text("one")
///     Text("two")
///     Text("three")
/// }
/// ```
///
/// ## Geometry is whole cells
///
/// ``sizeThatFits(proposal:subviews:cache:)`` answers in ``ViewSize`` and
/// ``placeSubviews(in:proposal:subviews:cache:)`` receives a ``CellRect`` —
/// integers, not `CGSize` and `CGRect`. A terminal has no half-column, and the
/// reasoning is recorded on ``AlignmentID``. Two consequences worth knowing:
///
/// - **Divide last.** `let each = total / count` then `i * each` silently drops
///   up to `count - 1` cells; `i * total / count` drops none and stays within a
///   cell of even. Floating point hid this by rounding at placement.
/// - **A fractional intermediate is fine — just floor it once, at the end.**
///   A radial layout computing with `cos`/`sin` is perfectly reasonable; the
///   cell boundary is where the rounding belongs, and
///   ``LayoutSubview/place(at:anchor:proposal:)`` does it for you.
///
/// ## Publishing a guide to the parent
///
/// ``explicitAlignment(of:in:proposal:subviews:cache:)-(HorizontalAlignment,_,_,_,_)``
/// and its vertical twin give the layout's own value for a guide, which a
/// parent aligning on that guide uses to place the whole layout. Left alone,
/// they merge the guides the subviews set for a custom ``AlignmentID`` — each
/// moved by where it was placed — and give none for the built-in alignments,
/// which is what SwiftUI was measured to do.
///
/// ## Spacing
///
/// Each subview states the spacing it prefers (``LayoutSubview/spacing``, a
/// ``ViewSpacing``), which a layout may use to space its subviews, and a layout
/// states its own for the container around it
/// (``spacing(subviews:cache:)``). In cells, every view prefers one column
/// beside it and no row above or below — see ``ViewSpacing``.
///
/// ## What SwiftUI has here that this does not
///
/// - **`Animatable`.** There is no tween space in a terminal — see the
///   compatibility notes on animation.
@MainActor
public protocol Layout {
    /// Per-layout scratch space, if the layout wants any. Defaults to `Void`.
    associatedtype Cache = Void

    /// The collection of views this layout arranges.
    typealias Subviews = LayoutSubviews

    /// Creates the cache. Called once per layout pass.
    func makeCache(subviews: Subviews) -> Cache

    /// Updates the cache when the subviews may have changed.
    func updateCache(_ cache: inout Cache, subviews: Subviews)

    /// The size this layout needs for `proposal`.
    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout Cache) -> ViewSize

    /// Positions each subview within `bounds`.
    ///
    /// Call one of the `place` methods on every subview: one that is never
    /// placed is not drawn. Placement order is draw order, so a layout may
    /// deliberately overlap its subviews.
    func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout Cache)

    /// The position of the given horizontal alignment guide along the x axis,
    /// or `nil` when the layout gives it no explicit value.
    ///
    /// The value places the layout as a whole within its parent; it does not
    /// change how the layout arranges its subviews. Called after
    /// ``placeSubviews(in:proposal:subviews:cache:)``, with the same bounds:
    ///
    /// ```swift
    /// func explicitAlignment(
    ///     of guide: HorizontalAlignment, in bounds: CellRect, proposal: ProposedSize,
    ///     subviews: Subviews, cache: inout ()
    /// ) -> Double? {
    ///     guide == .leading ? Double(bounds.x + 10) : nil
    /// }
    /// ```
    ///
    /// The default merges the explicit values the subviews give a custom
    /// guide, each moved by where it was placed, by the guide's
    /// ``HorizontalAlignment/combineExplicit(_:)``; for the built-in guides it
    /// gives none, as SwiftUI's does.
    ///
    /// - Parameters:
    ///   - guide: The guide to give a position for.
    ///   - bounds: The region the layout was given, in the parent's space.
    ///   - proposal: The size proposed to the layout.
    ///   - subviews: The subviews, already placed.
    ///   - cache: The layout's cache.
    /// - Returns: The guide's position, in the coordinate space of `bounds`;
    ///   `nil` for no explicit value.
    func explicitAlignment(
        of guide: HorizontalAlignment, in bounds: CellRect, proposal: ProposedSize,
        subviews: Subviews, cache: inout Cache
    ) -> Double?

    /// The position of the given vertical alignment guide along the y axis, or
    /// `nil` when the layout gives it no explicit value.
    ///
    /// The vertical twin of
    /// ``explicitAlignment(of:in:proposal:subviews:cache:)-(HorizontalAlignment,_,_,_,_)``.
    func explicitAlignment(
        of guide: VerticalAlignment, in bounds: CellRect, proposal: ProposedSize,
        subviews: Subviews, cache: inout Cache
    ) -> Double?

    /// The spacing this layout prefers around itself, for the container that
    /// places it.
    ///
    /// It affects the space around the layout, not how the layout arranges its
    /// subviews. The default merges every subview's preference on every edge;
    /// a stack-like layout would merge only the subviews at each end on the
    /// edges they touch:
    ///
    /// ```swift
    /// func spacing(subviews: Subviews, cache: inout ()) -> ViewSpacing {
    ///     var spacing = ViewSpacing()
    ///     for index in subviews.indices {
    ///         var edges: Edge.Set = [.leading, .trailing]
    ///         if index == 0 { edges.formUnion(.top) }
    ///         if index == subviews.count - 1 { edges.formUnion(.bottom) }
    ///         spacing.formUnion(subviews[index].spacing, edges: edges)
    ///     }
    ///     return spacing
    /// }
    /// ```
    ///
    /// A custom layout around this one reads it as this layout's
    /// ``LayoutSubview/spacing``.
    func spacing(subviews: Subviews, cache: inout Cache) -> ViewSpacing

    /// Static witness: whether this layout may give a guide an explicit value
    /// its subviews did not — that is, whether it implements
    /// ``explicitAlignment(of:in:proposal:subviews:cache:)-(HorizontalAlignment,_,_,_,_)``
    /// itself.
    ///
    /// `true` unless a layout says otherwise, because an override cannot be
    /// detected from the type. The framework's own layouts keep the default
    /// merge and say `false`, so a parent aligning on a guide asks them about
    /// it only when a subview might hold one — the rule every other container
    /// follows. A layout that says `true` and keeps the default is found out
    /// the first time the default answers for it, and asked as one that says
    /// `false` from then on (`LayoutDefaultGuides`).
    static var _definesExplicitAlignment: Bool { get }

    /// Properties of this kind of layout: which way it stacks, if it does.
    ///
    /// Its subviews see the ``LayoutProperties/stackOrientation`` as their
    /// container's axis, exactly as a stack's children see the stack's — a hint
    /// for the few views that care (a ``Divider`` picks its orientation from
    /// it), never a claim about placement. Defaults to no orientation, the
    /// answer a `ZStack` gives.
    static var layoutProperties: LayoutProperties { get }
}

/// Layout-specific properties of a layout container.
public struct LayoutProperties: Sendable {
    /// The orientation of the containing stack-like container, or `nil` for a
    /// container that does not stack along an axis.
    ///
    /// A ``Divider`` among the subviews draws across it: a vertical rule in a
    /// horizontal stack, a horizontal one otherwise.
    public var stackOrientation: Axis?

    /// Creates properties with no stack orientation.
    public init() {}
}

extension Layout {
    /// Default: no stack orientation.
    public static var layoutProperties: LayoutProperties { LayoutProperties() }

    /// Default: the subviews' explicit values for a custom guide, merged by
    /// ``HorizontalAlignment/combineExplicit(_:)``, and none for an edge or
    /// the centre, which a layout of several views places them by and keeps
    /// to itself, as SwiftUI's default does (measured: decisions A-GUIDE-2).
    ///
    /// Running, it records that this layout's type answers by it
    /// (`LayoutDefaultGuides`), so an edge guide is not asked of it again.
    public func explicitAlignment(
        of guide: HorizontalAlignment, in bounds: CellRect, proposal: ProposedSize,
        subviews: Subviews, cache: inout Cache
    ) -> Double? {
        LayoutDefaultGuides.noteDefault(type(of: self), along: .horizontal)
        guard !guide.isEdgeOrCentre else { return nil }
        return subviews.mergedExplicitGuide(.horizontal(guide))
    }

    /// Default: the subviews' explicit values for a custom guide or a text
    /// baseline, merged by ``VerticalAlignment/combineExplicit(_:)`` (a first
    /// baseline is the topmost, a last one the bottommost), and none for an
    /// edge or the centre, which a layout of several views places them by and
    /// keeps to itself, as SwiftUI's default does (measured: decisions
    /// A-GUIDE-2). Recorded as the horizontal one is.
    public func explicitAlignment(
        of guide: VerticalAlignment, in bounds: CellRect, proposal: ProposedSize,
        subviews: Subviews, cache: inout Cache
    ) -> Double? {
        LayoutDefaultGuides.noteDefault(type(of: self), along: .vertical)
        guard !guide.isEdgeOrCentre else { return nil }
        return subviews.mergedExplicitGuide(.vertical(guide))
    }

    /// Default: a layout may define its own guides — see
    /// ``Layout/_definesExplicitAlignment``.
    public static var _definesExplicitAlignment: Bool { true }

    /// Default: every subview's preference, merged on every edge
    /// (``ViewSpacing/union(_:edges:)``), and ``ViewSpacing/zero`` for a layout
    /// with no subviews, an `EmptyView` counting as none — as SwiftUI's default answers
    /// (`Tools/SwiftUIProbes/Stack spacing per pair/distances.out`, the
    /// `merging` rows).
    public func spacing(subviews: Subviews, cache: inout Cache) -> ViewSpacing {
        subviews.mergedSpacing
    }
}

extension Layout {
    /// Default: the cache is not updated between passes — see
    /// ``Layout/makeCache(subviews:)``.
    public func updateCache(_ cache: inout Cache, subviews: Subviews) {}
}

extension Layout where Cache == Void {
    /// Default for a layout that wants no cache.
    public func makeCache(subviews: Subviews) -> Cache { () }
}

extension Layout {
    /// Arranges `content` with this layout.
    ///
    /// Lets a layout be written where a container goes: `Diagonal { … }`.
    ///
    /// - Parameter content: The views to arrange.
    /// - Returns: A view that arranges them.
    public func callAsFunction<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        _LayoutCore(layout: self, content: content())
    }
}

// MARK: - Core

/// Drives a ``Layout``: resolves the children, asks the layout for a size and
/// for placements, then composites each placed subview into the result.
///
/// - Important: Framework infrastructure. Created by ``Layout/callAsFunction(_:)``.
public struct _LayoutCore<L: Layout, Content: View>: View, Renderable, Layoutable {
    let layout: L
    let content: Content

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and TUIGrid makes these, for the lazy grids.
    package init(layout: L, content: Content) {
        self.layout = layout
        self.content = content
    }

    public var body: Never {
        fatalError("_LayoutCore renders via Renderable")
    }

    /// A layout can give a guide an explicit value of its own, which no
    /// static fact rules out unless the layout says so; past that, a subview
    /// may hold one for the default merge to report.
    public static var _providesAlignmentGuide: Bool {
        L._definesExplicitAlignment || Content._providesAlignmentGuide
    }

    /// The subview proxies and the sink their placements land in.
    ///
    /// A layout that lays out grid cells (``GridLayout``, and the stack
    /// layouts it is switched with) sees a `ForEach` row that is a `GridRow`
    /// as the row's cells — see `expandingWholeGridRows(_:context:)`.
    private func resolve(context: RenderContext) -> (LayoutSubviews, LayoutPlacements, departing: [ChildView]) {
        let placements = LayoutPlacements()
        let all = resolveChildViews(from: content, context: context)
        // Row ids by position among ALL the children, a slot still leaving
        // included: a position is what matches a row to its loop.
        let rowIDs = FlattenedRowIDs<AnyHashable>(content: content, children: all)
        // A subview that has left is not one the layout is handed, as SwiftUI's
        // `Subviews` never hold a removed view: it is drawn where it last was
        // while its removal plays (`StackGlide`), and the rest close up.
        var children = all
        var kept: [Int]?
        var departing: [ChildView] = []
        if context.leavingTakesNoRoom(among: all) {
            let indices = all.indices.filter { !all[$0].isDeparting }
            children = indices.map { all[$0] }
            departing = all.filter(\.isDeparting)
            kept = indices
        }
        if (layout as? any WholeGridRowExpanding)?.expandsWholeGridRows == true,
            let expanded = expandingWholeGridRows(children, context: context)
        {
            return (
                LayoutSubviews(
                    children: expanded.children, context: context, placements: placements,
                    rowIDs: rowIDs, sourceIndices: expanded.sourceIndices.map { kept?[$0] ?? $0 },
                    mayStateSpacing: Content._statesSpacingPreference),
                placements, departing
            )
        }
        return (
            LayoutSubviews(
                children: children, context: context, placements: placements, rowIDs: rowIDs,
                sourceIndices: kept, mayStateSpacing: Content._statesSpacingPreference),
            placements, departing
        )
    }

    /// The cache lives for ONE pass rather than across them.
    ///
    /// `makeCache` therefore runs per pass and `updateCache` immediately after,
    /// so a conforming layout sees the sequence it expects and behaves
    /// identically — it just does not get the cross-pass saving SwiftUI's
    /// persistent layout graph provides. Persisting it would mean writing to
    /// `StateStorage` from inside a render, which is the measure-side-effect
    /// bug class: the write invalidates the render cache and the frame that
    /// wrote it schedules another.
    private func freshCache(_ subviews: LayoutSubviews) -> L.Cache {
        var cache = layout.makeCache(subviews: subviews)
        layout.updateCache(&cache, subviews: subviews)
        return cache
    }

    /// The context the children resolve, measure and render in: this one with
    /// the wrapped layout's axis published, when it has one.
    ///
    /// ``Divider`` picks its orientation from the enclosing container's axis,
    /// and `HStackLayout`/`VStackLayout` are that container as surely as
    /// `HStack`/`VStack` are — but nothing here published one, so a rule inside
    /// `AnyLayout(HStackLayout())` fell back to the no-stack default: the
    /// horizontal, WIDTH-FLEXIBLE spelling, which is then the row's only
    /// flexible child and takes all of its slack. `aa │ bb` at width 20 came
    /// out as `aa`, fourteen `─`, `bb`.
    ///
    /// Rebound once at the top of each entry point — the shape
    /// `_HStackCore.renderToBuffer` and `_GridCore` already use — so `resolve`,
    /// every `LayoutSubview` measure and every child render see the same axis,
    /// rather than the measure and the render answering different questions.
    ///
    /// `nil` for a layout with no axis — `ZStackLayout`, the lazy grids,
    /// anything an app writes that does not state a `stackOrientation` — which
    /// leaves the divider its default unchanged. ``AnyLayout``'s static
    /// properties cannot know what it erased, so it forwards through
    /// `AxisPublishingLayout` instead.
    ///
    /// Either way the layout is a container of its own, and takes its sections
    /// apart (`RenderContext.takingSectionsApart()`): in a row of a lazy stack
    /// that keeps its own sections whole, a layout with no axis kept them
    /// whole too, one subview each. And it offers its subviews a width as it
    /// places them (``EnvironmentValues/offeredNoWidth``), unless it lays them
    /// along the width or holds statically one view, as SwiftUI's stack
    /// layouts do (`HStackLayout` passes an unspecified width on,
    /// `VStackLayout` and `ZStackLayout` of several do not).
    private func publishingChildAxis(_ context: RenderContext) -> RenderContext {
        guard
            let axis = L.layoutProperties.stackOrientation
                ?? (layout as? any AxisPublishingLayout)?.containerAxis
        else {
            return context.takingSectionsApart().offeringAWidth(unless: isStaticallyOneView(Content.self))
        }
        return context.publishingContainerAxis(
            axis, passesNoWidthOn: axis == .horizontal || isStaticallyOneView(Content.self))
    }

    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let context = publishingChildAxis(context)
        let (subviews, _, _) = resolve(context: context)
        var cache = freshCache(subviews)
        return layout.sizeThatFits(
            proposal: grounded(proposal, in: context), subviews: subviews, cache: &cache)
    }

    /// Fills in an unconstrained proposal from what is actually on screen.
    ///
    /// ``renderToBuffer(context:)`` builds its proposal from
    /// `context.availableWidth`/`Height` and ignores the one it was measured
    /// with, so a `nil` here means the measure and the render answer different
    /// questions. For most layouts that is harmless — a stack's height does not
    /// depend on its width. For one whose SHAPE depends on the extent it is
    /// given, it is a real divergence: a reflowing grid asked "how tall are you
    /// at no particular width" has no honest answer, and whichever it invents
    /// is the number a parent stack then budgets rows for.
    ///
    /// Grounding both passes in the same numbers makes measure/render parity
    /// structural here, the way `Text.displayString` does for text.
    private func grounded(_ proposal: ProposedSize, in context: RenderContext) -> ProposedSize {
        ProposedSize(
            width: proposal.width ?? max(0, context.availableWidth),
            height: proposal.height ?? max(0, context.availableHeight))
    }

    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let context = publishingChildAxis(context)
        let (subviews, placements, departing) = resolve(context: context)
        guard !subviews.isEmpty else {
            // Nothing to place, and still a subview the change took out may
            // be playing a transition of its own where it was; and asked, so
            // the record lasts for a subview that comes to fade in
            // (`ChildFade`).
            return context.glidingStackBuffer([], buffers: [], at: [], departing: departing, width: 0, height: 0)
                ?? FrameBuffer()
        }

        var cache = freshCache(subviews)
        let proposal = ProposedSize(
            width: max(0, context.availableWidth), height: max(0, context.availableHeight))
        let size = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)

        let bounds = CellRect(
            x: 0, y: 0, width: max(0, size.width), height: max(0, size.height))
        layout.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)

        // A blank canvas at the size the layout reported, so an arrangement
        // that leaves gaps keeps them — and so the measure it just gave its
        // parent is the size it actually occupies.
        var result = FrameBuffer(emptyWithWidth: bounds.width, height: bounds.height)
        // A `.gradientExtent(.subtree)` ramp spanning this layout: the bounds
        // are the rectangle it runs across and each entry is exactly where its
        // subview sits in it, both already worked out above. One answer here
        // covers the lazy grids, `AnyLayout` and any layout an app writes for
        // itself. NOT `Grid`, which is not a `Layout` — a lattice is not
        // something `LayoutSubviews` can describe — and gives its own answer in
        // `_GridCore`. Saying otherwise here is what hid a bug for a month.
        let gradientFrame = context.gradientContentFrame(
            width: bounds.width, height: bounds.height)
        let entries = placements.entries
        let children = entries.map { subviews[$0.index].child }
        let pictures = entries.indices.map { index in
            let entry = entries[index]
            let childSize = children[index].measure(proposal: entry.proposal, context: context)
            return children[index].render(
                width: entry.proposal.width ?? childSize.width,
                height: entry.proposal.height ?? childSize.height,
                context: context.placingChild(gradient: gradientFrame, x: entry.x, y: entry.y))
        }
        // While a subview is on its way to where the layout now places it
        // under an animation, each is drawn where it is (`StackGlide`).
        if let gliding = context.glidingStackBuffer(
            children, buffers: pictures, at: entries.map { ChildPlacement(x: $0.x, y: $0.y) }, departing: departing,
            width: bounds.width, height: bounds.height)
        {
            return gliding
        }
        var showingThrough: [AnimatedCellRun] = []
        for (entry, rendered) in zip(entries, pictures) {
            // In place: `composited` rebuilds every line of the canvas per
            // call, so folding n children through it is n × canvas even though
            // each child covers a couple of rows.
            showingThrough += result.runsShowingThrough(rendered, at: (x: entry.x, y: entry.y))
            result.compositeCarryingClaimsOverNothing(
                with: rendered, at: (x: entry.x, y: entry.y), in: CompositeEnvironment(context.environment))
        }
        // An earlier subview's runs a later one shows the field of, whose frames turn
        // it: punched under the later one, they ask for a render at their steps.
        if !showingThrough.isEmpty {
            context.requestWake(
                token: "layout-base-run-\(context.identity.path)",
                forNextStepOf: showingThrough.map { ($0.clock, $0.frameTicks) })
        }
        return result
    }
}

// MARK: - Publishing a Guide

extension _LayoutCore: AlignmentGuideQuerying {
    /// The layout's ``Layout/explicitAlignment(of:in:proposal:subviews:cache:)-(HorizontalAlignment,_,_,_,_)``
    /// for the guide asked about, after a layout pass at `dimensions` — the
    /// pass `renderToBuffer` makes, so the subviews are where they will be
    /// drawn when the default merges their guides.
    ///
    /// Nothing is laid out for a layout that defines no guide of its own and
    /// whose content can hold none: `AnyLayout` asks what it erased. Nor for
    /// one whose content's type says a subview MAY carry a guide and whose
    /// subviews, resolved, carry none — a loop over subviews, `ForEach(subviews:
    /// content) { $0 }`, whose proxy's type cannot know (`Subview`'s witness is
    /// `true` for every member): the default merges only the subviews' own
    /// guides, so the answer is `nil` without the pass. Nor, for an edge or
    /// the centre, for any layout that defines none of its own along the
    /// guide's axis — one that says so, or one whose type the default has
    /// answered for before (`LayoutDefaultGuides`) — but a stack layout of
    /// one view, which passes its view's.
    package func explicitGuide(
        _ query: AlignmentGuideQuery, in dimensions: ViewDimensions, context: RenderContext
    ) -> Double? {
        let passesOneView = L.self is any PassesEveryGuideOfOneView.Type && staticViewListCount(Content.self) == 1
        let defines = layout.definesExplicitAlignment(along: query.axis)
        // A layout that gives no guide a value of its own answers by the
        // default, which keeps an edge or the centre to itself: nothing to
        // lay out to find that out, but for a stack layout of one view.
        if !defines, query.isEdgeOrCentre, !passesOneView { return nil }
        guard defines || Content._providesAlignmentGuide else { return nil }
        let context = publishingChildAxis(context)
        let (subviews, _, _) = resolve(context: context)
        guard defines || anyAlignmentGuide(in: subviews.children) else { return nil }
        var cache = freshCache(subviews)
        let proposal = ProposedSize(
            width: max(0, dimensions.width), height: max(0, dimensions.height))
        let size = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
        let bounds = CellRect(x: 0, y: 0, width: max(0, size.width), height: max(0, size.height))
        layout.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
        if passesOneView { return subviews.mergedExplicitGuide(query) }
        switch query {
        case .horizontal(let guide):
            return layout.explicitAlignment(
                of: guide, in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
        case .vertical(let guide):
            return layout.explicitAlignment(
                of: guide, in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
        }
    }
}

/// A stack layout of the framework's — `VStackLayout`, `HStackLayout`,
/// `ZStackLayout` — which reports every guide of content that is statically
/// one view, edges and centre included, as SwiftUI's do and as the stacks
/// themselves do: `VStackLayout { G }` reports `G`'s leading guide, where an
/// `AnyLayout` around the same layout, and a layout of the app's own, report
/// none (measured, decisions A-GUIDE-2).
protocol PassesEveryGuideOfOneView {}

extension VStackLayout: PassesEveryGuideOfOneView {}
extension HStackLayout: PassesEveryGuideOfOneView {}
extension ZStackLayout: PassesEveryGuideOfOneView {}

/// A layout that knows at run time whether what it wraps defines guides of its
/// own — `AnyLayout`, whose static answer cannot.
@MainActor
protocol ExplicitAlignmentForwarding {
    /// Whether the wrapped layout may give a guide along `axis` a value of its
    /// own (``Layout/definesExplicitAlignment(along:)``).
    func definesExplicitAlignment(along axis: Axis) -> Bool
}

// MARK: - Spacing Around a Layout

/// A view that states the spacing it prefers around itself — a ``Layout``,
/// whose ``Layout/spacing(subviews:cache:)`` says.
@MainActor
protocol SpacingPreferenceProviding {
    /// The spacing this view prefers, laid out in `context` (its own).
    func preferredSpacing(context: RenderContext) -> ViewSpacing
}

extension _LayoutCore: SpacingPreferenceProviding {
    /// The layout's ``Layout/spacing(subviews:cache:)``, over its subviews as
    /// they resolve here, with a fresh cache — the one each pass gets.
    func preferredSpacing(context: RenderContext) -> ViewSpacing {
        var context = publishingChildAxis(context)
        context.isMeasuring = true
        let (subviews, _, _) = resolve(context: context)
        var cache = freshCache(subviews)
        return layout.spacing(subviews: subviews, cache: &cache)
    }
}
