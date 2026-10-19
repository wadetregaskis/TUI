//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AlignmentGuide.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
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
    /// The value is used as given, as SwiftUI's is, even when it lies outside
    /// the view: `.alignmentGuide(.leading) { _ in 5 }` on a one-cell view
    /// indents its siblings by five cells, and a `ZStack` in a `ScrollView`
    /// can place its views by guide down a canvas a million cells long.
    ///
    /// One guide may push a view at most 1,048,576 cells (2^20) along its
    /// container, or as far as the container's extent or its widest view if
    /// that is further. A guide that would push one further is a logic error
    /// — a division by a value near zero, a unit mix-up — and so is a guide
    /// that is not a finite number (`.nan`, `.infinity`, `-.infinity`) on a
    /// view with a width and a height: a debug build stops with an assertion,
    /// and a release build reports it once (to `TUIKIT_DIAGNOSTICS_FILE`, or
    /// to stderr when the app gives the terminal back) and places the view as
    /// if its guide were at its own origin. SwiftUI places a finite one
    /// without a word, stops on `.infinity` or `.nan`, and places a view whose
    /// guide is `-.infinity` at an infinite x without stopping (measured). A
    /// canvas that really is larger can raise the bound with the
    /// `TUIKIT_MAX_ALIGNMENT_PUSH` environment variable, a number of cells up
    /// to 2^30.
    ///
    /// `.frame(alignment:)`, `.overlay(alignment:)` and
    /// `.background(alignment:)` place their one view where its guide meets
    /// theirs, outside the region if that is where it falls, and draw it
    /// there, as SwiftUI does: over the views before it, under the views
    /// after it, clicked where it is drawn. So a badge hung off a label's
    /// corner by its guides sits beside the label, not on it. A scroll view,
    /// a `List`, a `Table`, a menu, a sheet and `.clipped()` still keep it
    /// inside them, and since a cell has no transparency, what it draws past
    /// the region hides what is beneath it.
    ///
    /// ## How far a guide travels
    ///
    /// As in SwiftUI, a guide travels up through the views that place their
    /// content at a known offset, each moving it by that offset, and what
    /// leaves a container depends on the guide's kind:
    ///
    /// - A **custom** guide (your own ``AlignmentID``) and a **text
    ///   baseline** leave `VStack`, `HStack`, `ZStack` and a ``Layout``,
    ///   merged by the alignment's ``HorizontalAlignment/combineExplicit(_:)``
    ///   when several children set one (the mean; the topmost first
    ///   baseline, the bottommost last one). So a decimal-point guide set on
    ///   a `Text` inside each row of a column aligns the rows on the point.
    /// - An **edge or centre** guide (`.leading`, `.center`, `.trailing`,
    ///   `.top`, `.bottom`) places a container's children and stays in it,
    ///   unless the container's content is statically one view: `VStack { G
    ///   }` reports `G`'s leading guide, `VStack { G; S }`, a `ForEach` of one
    ///   row and an `if` do not. To line views up across containers by an
    ///   edge, declare a custom ``AlignmentID`` whose default is that edge.
    ///
    /// A custom ``Layout`` can state one of its own
    /// (``Layout/explicitAlignment(of:in:proposal:subviews:cache:)-(HorizontalAlignment,_,_,_,_)``).
    ///
    /// A guide passes the modifiers written after it, each moving it by where
    /// it puts its content, as SwiftUI's does: `.padding` by its inset,
    /// `.frame` by where it places its content, `.position` by where it
    /// centres it, `.border()` by its ring (a line and a blank cell across,
    /// a line down — SwiftUI strokes inside the view, so its guide does not
    /// move); `.offset` passes it unmoved, being laid out where its view is;
    /// `.overlay` and `.background` pass their base's; and a modifier that
    /// keeps its content where it is — environment, style, effect, focus,
    /// gesture and lifecycle modifiers, `.id`, `.tag`, `.badge`, `.opacity`,
    /// `.fixedSize()` — passes it unmoved, the content laid out as the
    /// modifier lays it out: under `.textCase(.uppercase)` a guide is placed
    /// in the uppercased text.
    /// A view type of your own reports what its `body` does, through an `if`,
    /// an `if`/`else` and a `switch` too, so a guide inside `struct Row:
    /// View`'s body travels out of `Row` as SwiftUI's does.
    ///
    /// - Important: It stops at a modifier that moves or resizes its content
    ///   without saying by how much — a `.toolbar`, a list row's insets or
    ///   colours, a ``BufferModifier`` of your own (unless it states
    ///   ``BufferModifier/_keepsContentGeometry``). Put the guide outside such a
    ///   modifier. A guide is a closure evaluated against the dimensions the
    ///   view laid out at, and a wrapper that does not translate it would
    ///   report a position from the wrong coordinate space.
    ///
    /// - Parameters:
    ///   - g: The guide to set.
    ///   - computeValue: The guide's position in this view's own
    ///     coordinates, given the view's dimensions. It need not lie inside
    ///     the view.
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
    /// How far it travels, and through which modifiers, is as for the
    /// horizontal overload.
    ///
    /// - Parameters:
    ///   - g: The guide to set.
    ///   - computeValue: The guide's position in this view's own
    ///     coordinates, given the view's dimensions. It need not lie inside
    ///     the view.
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
package enum AlignmentGuideQuery {
    case horizontal(HorizontalAlignment)
    case vertical(VerticalAlignment)

    /// The guide asked about.
    var key: AlignmentKey {
        switch self {
        case .horizontal(let alignment): alignment.key
        case .vertical(let alignment): alignment.key
        }
    }

    /// Whether the guide is an edge or the centre of its axis, which a
    /// container of several views places them by and reports none of, where a
    /// text baseline or a custom guide travels on out of it: SwiftUI's rule,
    /// measured (decisions A-GUIDE-2).
    var isEdgeOrCentre: Bool {
        switch self {
        case .horizontal(let alignment): alignment.isEdgeOrCentre
        case .vertical(let alignment): alignment.isEdgeOrCentre
        }
    }

    /// Whether a container whose content is a value of `Content` keeps this
    /// guide to itself: an edge or centre guide, unless the content is
    /// statically one view — SwiftUI's stacks report every guide of
    /// `VStack { G }` and `VStack { G; EmptyView() }`, and no edge or centre
    /// guide of `VStack { G; S }`, a `ForEach` of one row or an `if`
    /// (``staticViewListCount(_:)``; decisions A-GUIDE-2).
    @MainActor
    func staysInside<Content: View>(contentOf _: Content.Type) -> Bool {
        isEdgeOrCentre && staticViewListCount(Content.self) != 1
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
package protocol AlignmentGuideQuerying {
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
/// view whose type cannot hold a guide is answered without a cast, and for an
/// edge or centre guide, one whose type keeps every guide it holds inside a
/// stack of several views (``mayReportEdgeOrCentreGuide(_:)``). Past it, a
/// view answers itself (``AlignmentGuideQuerying``, or the public
/// ``AlignmentGuideProviding``), or — a framework composite such as `VStack`,
/// whose witness forwards its content's, or a view of the app's own, whose
/// witness is its body's — its `body` is asked, at the identity its body
/// renders at.
@MainActor
package func explicitGuide<V: View>(
    of view: V, _ query: AlignmentGuideQuery, in dimensions: ViewDimensions,
    context: RenderContext
) -> Double? {
    guard V._providesAlignmentGuide else { return nil }
    if query.isEdgeOrCentre, !mayReportEdgeOrCentreGuide(V.self) { return nil }
    if let querying = view as? AlignmentGuideQuerying {
        return querying.explicitGuide(query, in: dimensions, context: context)
    }
    if let provider = view as? AlignmentGuideProviding {
        return provider.explicitAlignmentGuide(for: query.key, in: dimensions)
    }
    // A wrapper that lays its content out where it is itself: its content's
    // guide, unmoved, laid out in the context the wrapper gives it — or none
    // where the wrapper has not said what that is.
    if let wrapper = view as? any SingleContentWrapper, keepsItsContentGeometry(wrapper) {
        return explicitGuide(ofContentOf: wrapper, query, in: dimensions, context: context)
    }
    guard V.Body.self != Never.self, !(view is Renderable) else { return nil }
    // The body as the measure walk evaluates it: `@Environment` resolved and
    // `@State` bound at this view's identity, so it is the body that is drawn.
    let childContext = context.withChildIdentity(type: V.Body.self)
    guard let plan = propertyPlan(for: V.self) else {
        return explicitGuide(of: view.body, query, in: dimensions, context: childContext)
    }
    return explicitGuide(
        of: preparedBody(of: view, plan: plan, context: context, isMeasuring: true), query, in: dimensions,
        context: childContext)
}

/// Whether `wrapper` lays its content out where it is itself
/// (`keepsContentGeometry(_:)`), the existential opened.
@MainActor
private func keepsItsContentGeometry<W: SingleContentWrapper>(_: W) -> Bool {
    keepsContentGeometry(W.self)
}

/// ``explicitGuide(of:_:in:context:)`` of `wrapper`'s content, the existential
/// opened: unmoved, as a wrapper that keeps its content's geometry draws it,
/// in the context the wrapper lays it out in
/// (``SingleContentWrapper/wrappedContentContext(_:)``) — `.textCase(_:)`'s
/// style, `.environment(_:_:)`'s value, which can change what the content
/// lays out. Asked in the wrapper's own, it answered from a layout that is
/// never drawn: `HStack { Text("ßß"); Text("x").alignmentGuide(…) }
/// .textCase(.uppercase)` placed the guide two cells in, where the drawn row
/// is `SSSSX` (found in review). `nil`, a stop, where the wrapper has not
/// said: a wrong position is worse than none.
@MainActor
private func explicitGuide<W: SingleContentWrapper>(
    ofContentOf wrapper: W, _ query: AlignmentGuideQuery, in dimensions: ViewDimensions, context: RenderContext
) -> Double? {
    guard let contentContext = wrapper.wrappedContentContext(context) else { return nil }
    return explicitGuide(of: wrapper.wrappedContent, query, in: dimensions, context: contentContext)
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
    package func explicitGuide(
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

    /// The furthest, in cells, one guide falling short of another may push a
    /// child along the run: 2^20 (1,048,576), unless the
    /// `TUIKIT_MAX_ALIGNMENT_PUSH` environment variable says otherwise
    /// (``maximumPush(environment:)``).
    ///
    /// SwiftUI uses a guide exactly as given, inside its own view or not
    /// (measured 2026-10-11: a 1-wide view whose leading guide is 25 indents
    /// its sibling by 25), so nothing here holds a guide to its view's size,
    /// and a canvas that places its views by guide — a `ZStack` in a vertical
    /// `ScrollView` putting each item at `.alignmentGuide(.top) { _ in -row }`
    /// — can be a million rows tall, as SwiftUI's can (measured 2026-10-12 to
    /// 100,000 rows; decisions B-GUIDE-2).
    ///
    /// What is bounded is the push, because a push past this is a logic error,
    /// not a layout: a guide is caller arithmetic, and a runaway expression (a
    /// division by a value near zero, a unit mix-up, `.greatestFiniteMagnitude`
    /// meaning "far away") is a finite astronomical number. Unbounded, a guide
    /// of `1e300` asks for a buffer `Int.max` cells wide and traps on
    /// arithmetic overflow sizing a line (measured), and a push of `1e7` to
    /// `1e12` pads a line of that many spaces for each pushed row on every
    /// frame; neither names the guide. So a push past the bound is reported
    /// through `SoftTrap` (an assertion in a debug build, reported once in a
    /// release build) and the guide that caused it is taken as its view's own
    /// origin, as a guide that is not a number is — not as a view placed at
    /// the bound, which would build a million-cell buffer every frame on a
    /// bug path.
    ///
    /// A row count is the size of real data, and TUIkit lets an eager `VStack`
    /// of a million rows build its buffer; a push is one number that runs away
    /// when the arithmetic behind it is wrong, hence a bound here and none
    /// there. A run is never bounded below its region's own extent or its
    /// widest child, which are drawn already. The bound reads no budget: a row
    /// reports its height without reading the vertical one
    /// (`_HStackCore.clipSizeThatFits`), so the measure and the render bound
    /// the run alike.
    static let maximumPush = maximumPush(environment: ProcessInfo.processInfo.environment)

    /// ``maximumPush`` when the environment does not set one: 2^20 cells.
    static let defaultMaximumPush = 1 << 20

    /// The most `TUIKIT_MAX_ALIGNMENT_PUSH` can raise the bound to: 2^30 cells.
    ///
    /// A pushed run is drawn as lines that long, and its extent plus a view's
    /// size must still fit an `Int` where `Int` is 32 bits (WebAssembly's
    /// wasm32), so the variable is a safety net for a canvas past 2^20, not a
    /// way to turn the bound off.
    static let largestMaximumPush = 1 << 30

    /// The rule behind ``maximumPush``, posed on its input so it can be asked
    /// without changing what a whole process reads.
    ///
    /// `TUIKIT_MAX_ALIGNMENT_PUSH` set to a whole number of cells from 1 up
    /// replaces ``defaultMaximumPush``, held to ``largestMaximumPush``; unset,
    /// or anything else, leaves the default.
    static func maximumPush(environment: [String: String]) -> Int {
        guard let text = environment["TUIKIT_MAX_ALIGNMENT_PUSH"],
            let cells = Int(text.trimmingCharacters(in: .whitespaces)), cells > 0
        else { return defaultMaximumPush }
        return min(cells, largestMaximumPush)
    }

    /// Resolves placement from already-merged guide positions.
    ///
    /// Every child's guide is put on one line: the run's merged guide
    /// `max(resolved)`, or toward the region's own guide when the region is
    /// larger and its guide sits further along, as far as the whole run still
    /// fits. Offsets are then floored — the fraction only ever exists
    /// *between* two guides — and, unless the caller draws past the region,
    /// clamped so no child is placed outside a region too small for the run.
    ///
    /// - Parameters:
    ///   - resolved: Each child's guide position within itself, used as given.
    ///     A value that is not a cell coordinate is taken as the child's own
    ///     origin — see ``coordinate(_:)``.
    ///   - sizes: Each child's extent along the axis.
    ///   - fixedExtent: The region's extent when the container does not size to
    ///     content; `nil` to grow to fit the run.
    ///   - minimumExtent: A floor on a content-sized region's extent.
    ///   - report: Where a guide that would push a view past ``maximumPush``
    ///     is reported — ``guideErrorReporter(in:)``: ``reportGuideError(_:)``
    ///     on a render pass, `nil` on a measure pass, which works out the
    ///     same placement and says nothing.
    ///   - holdsChildrenInside: Whether a child the run would put past the
    ///     far edge of a region too small for it is pulled back inside — `true`
    ///     for a caller that cannot draw past the region. `false` keeps every
    ///     guide on the line, and the caller draws the overhang past the edge
    ///     (`FrameBuffer.placedHorizontallyDrawingOverhang(inWidth:offset:isMeasuring:)`;
    ///     decisions B-GUIDE-1).
    ///   - regionGuide: The region's own guide, given its final extent.
    static func resolve(
        resolved: [Double],
        sizes: [Int],
        fixedExtent: Int?,
        minimumExtent: Int,
        report: ((String) -> Void)?,
        holdsChildrenInside: Bool = true,
        regionGuide: (Int) -> Double
    ) -> Self {
        // Sanitised BEFORE `merged`, not at the conversions below: one
        // child's non-coordinate poisons every sibling's base through the
        // maximum, and the child that set it gets `∞ - ∞`, i.e. NaN, for its
        // own.
        var positions = resolved.map { coordinate($0) }
        let reach = Double(max(Self.maximumPush, minimumExtent, fixedExtent ?? 0))
        // A push is how far one guide falls short of the largest, so the
        // furthest push is the spread of the guides. Past `reach`, the guides
        // furthest from their own views' origins are the runaways — `1e300`
        // beside a `0`, `-1e300` beside a `-row` — and become those origins,
        // as a guide that is not a number does (``zeroRunaways(_:reach:)``).
        // Reported once for the run: one report is the logic error, and a
        // release build keeps only the first.
        if let lowest = positions.min(), let highest = positions.max(), highest - lowest > reach {
            report?(Self.pushPastTheBoundMessage(bound: Int(reach)))
            Self.zeroRunaways(&positions, reach: reach)
        }
        let merged = positions.max() ?? 0

        // A child's distance from the run's leading edge is how far its guide
        // falls short of the merged one — so the child with the largest guide
        // sits flush and every other is pushed along, at most `reach`.
        var contentExtent = 0
        for (index, guide) in positions.enumerated() {
            contentExtent = max(
                contentExtent, Int(clamping: (merged - guide + Double(sizes[index])).rounded(.up)))
        }

        let extent = fixedExtent ?? max(contentExtent, minimumExtent)
        // In a region bigger than the run, the run as a whole still has to be
        // positioned: its guide meets the region's. `max` keeps every offset
        // non-negative when the region's guide sits before the merged one
        // (`.leading` with a guide pushed inward, say). `min` moves the run
        // only as far as the room the region has past it, so the whole run
        // stays inside and every child's guide stays on one line. A
        // content-sized run has no room, so its line is `merged`: SwiftUI's
        // rule. Without the `min`, a child hanging past the line grew the
        // run, which moved a `.trailing` or `.center` region's guide past
        // `merged`, shifted the whole run, and the per-child clamp below
        // pulled back only the child that hung out. Measured against SwiftUI
        // 2026-10-11: in `VStack(alignment: .trailing)`, a 3-wide view with
        // trailing guide 0 above a 6-wide one leaves the 6-wide one at 0, not
        // 3. A region smaller than the run has no room either, so the run
        // keeps its leading edge on the region's; past its far edge, either
        // the caller draws the overhang there, every guide still on the line
        // (SwiftUI's picture, decisions B-GUIDE-1), or the per-child clamp
        // pulls back each child that would fall outside.
        let room = Double(max(0, extent - contentExtent))
        let anchor = min(max(merged, coordinate(regionGuide(extent))), merged + room)

        var offsets: [Int] = []
        offsets.reserveCapacity(positions.count)
        for (index, guide) in positions.enumerated() {
            let raw = max(0, Int(clamping: (anchor - guide).rounded(.down)))
            offsets.append(holdsChildrenInside ? min(raw, max(0, extent - sizes[index])) : raw)
        }
        return Self(offsets: offsets, extent: extent)
    }

    /// Takes the runaway guides in `positions` as their views' origins (`0`)
    /// until the spread of what is left, those zeros included, is at most
    /// `reach`.
    ///
    /// The rule is one guide at a time, furthest from its origin first (the
    /// first of equals), since the next one out may be legitimate once the
    /// runaway is gone: `-1e300` goes and a canvas row's `-3` stays. Done
    /// literally, each step rescans the run, so a canvas of 20,000 rows with
    /// a unit mix-up cost about 10^9 comparisons a resolve, and a resolve runs
    /// on every measure and render. Here the order is sorted once, and the
    /// spread left after each step is read off the minimum and maximum of
    /// the rest of that order, kept from its far end: O(n log n), on a path
    /// that is a logic error already.
    private static func zeroRunaways(_ positions: inout [Double], reach: Double) {
        let order = positions.indices.sorted { lhs, rhs in
            let (left, right) = (abs(positions[lhs]), abs(positions[rhs]))
            return left != right ? left > right : lhs < rhs
        }
        // `lowest[k]`, `highest[k]`: the extremes of the guides still standing
        // once the first `k` in `order` are zeroed.
        var lowest = [Double](repeating: .infinity, count: order.count + 1)
        var highest = [Double](repeating: -.infinity, count: order.count + 1)
        for step in order.indices.reversed() {
            lowest[step] = min(lowest[step + 1], positions[order[step]])
            highest[step] = max(highest[step + 1], positions[order[step]])
        }
        // Zeroing one or more puts a 0 among them; zeroing all of them leaves
        // a spread of 0, so the search always ends.
        // Typed throughout: with bare `0` literals the generic `max` and `min`
        // took the solver past CI's type-check bound (`typecheck_guard`).
        let zeroed: Int =
            (1...order.count).first { (step: Int) -> Bool in
                let spread: Double = Swift.max(0.0, highest[step]) - Swift.min(0.0, lowest[step])
                return spread <= reach
            } ?? order.count
        for step in 0..<zeroed { positions[order[step]] = 0 }
    }

    /// Where one view goes in a region `extent` cells long whose own guide is
    /// `regionGuide`, when the view's is `guide`: SwiftUI's single-child rule,
    /// the region's guide less the view's, floored — outside the region where
    /// that falls outside it.
    ///
    /// Bounded as a run's push is (``maximumPush``, or the region's extent if
    /// that is further): a guide that would put the view further from the
    /// region's guide is reported and taken as the view's own origin, and the
    /// result is held to the bound whatever the region's guide says, so a
    /// runaway custom guide cannot place a view `Int.max` cells away.
    static func place(guide: Double, regionGuide: Double, extent: Int, report: ((String) -> Void)?) -> Int {
        let region = coordinate(regionGuide)
        let reach = Double(max(Self.maximumPush, extent))
        var offset = region - coordinate(guide)
        if !(abs(offset) <= reach) {
            report?(Self.pushPastTheBoundMessage(bound: Int(reach)))
            offset = min(max(region, -reach), reach)
        }
        return Int(offset.rounded(.down))
    }

    /// `value` as a cell coordinate: the view's own origin when it is not
    /// finite, and otherwise `value`, as given.
    ///
    /// A guide is caller arithmetic: `Double(d.width) / Double(d.height)` on a
    /// child that is legitimately zero-height during a measure pass is `+∞`,
    /// and `0 / 0` is NaN. Either used to reach `Int(_: Double)`, which traps
    /// on both. A non-finite guide becomes the position a view with no guide
    /// has; NaN has no order and so no nearer edge to fall back to. Where its
    /// view has a width and a height it is a logic error, and is reported
    /// (`checkedGuide(_:dimensions:context:)`).
    ///
    /// A finite guide is NOT held to its own view. It used to be held to
    /// `[-w, 2w]` of the view's extent `w`, on the premise that a guide is a
    /// position inside its view, so a 1-wide view's guide of 5 indented its
    /// sibling by 2. SwiftUI uses it as given (measured 2026-10-11, 135
    /// placements), so a finite guide passes through, and what bounds the run
    /// is how far it pushes a child (``maximumPush``), with every conversion
    /// to `Int` saturating.
    private static func coordinate(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }
}

// MARK: - Reporting a Guide That Is a Logic Error

extension AlignmentGuideRun {
    /// Where ``reportGuideError(_:)`` sends a report instead of `SoftTrap`,
    /// while a task binds it: the render path's injectable reporter.
    ///
    /// ``resolve(resolved:sizes:fixedExtent:minimumExtent:report:holdsChildrenInside:regionGuide:)``
    /// takes its reporter as a parameter, as `SoftTrap`'s other callers do,
    /// but a stack reaches it from `renderToBuffer`, which a test cannot hand
    /// a closure through, and a debug build would stop at the assertion.
    /// Task-local, as the other render-path test seams are
    /// (`TerminalWidthTraits`), so suites running in parallel do not see each
    /// other's reports.
    @TaskLocal static var guideErrorReporter: (@Sendable (String) -> Void)?

    /// Reports a guide that is a logic error: to ``guideErrorReporter`` when a
    /// task binds one, and otherwise through `SoftTrap`.
    static func reportGuideError(_ message: String) {
        if let reporter = guideErrorReporter {
            reporter(message)
        } else {
            SoftTrap.report(message)
        }
    }

    /// The report for a guide that would push a view more than `bound` cells.
    ///
    /// Without the guide's value: a runaway guide often varies from frame to
    /// frame, and a release build keeps every distinct message it reports.
    static func pushPastTheBoundMessage(bound: Int) -> String {
        "An alignment guide (alignmentGuide(_:computeValue:)) would push a view more than \(bound) cells "
            + "along its container: a logic error, such as a division by a value near zero or a unit mix-up. "
            + "The view is placed as if its guide were at its own origin. "
            + "TUIKIT_MAX_ALIGNMENT_PUSH raises the bound for a canvas that really is that large."
    }

    /// The report for a guide that is `value`, not a number, on a view with a
    /// width and a height.
    static func nonFiniteGuideMessage(_ value: Double) -> String {
        "An alignment guide (alignmentGuide(_:computeValue:)) returned \(value) for a view with a width "
            + "and a height, which is not a position. The view is placed as if its guide were at its own origin."
    }
}

/// `value`, the guide a view of `dimensions` gives, reported first when it is
/// a logic error: not a number, on a view with a width and a height, on a
/// render pass.
///
/// Not on a view with no width or no height: TUIkit measures at sizes SwiftUI
/// never offers (the zero-height measure the run's fallback was written for),
/// and a small terminal can squeeze a row to nothing, so a
/// `d.width / d.height` guide is legitimately `+∞` there. Not on a measure
/// pass, which proposes such sizes. Either way the run takes the value as the
/// view's own origin.
@MainActor
func checkedGuide(_ value: Double, dimensions: ViewDimensions, context: RenderContext) -> Double {
    if !value.isFinite, dimensions.width > 0, dimensions.height > 0, !context.isMeasuring {
        AlignmentGuideRun.reportGuideError(AlignmentGuideRun.nonFiniteGuideMessage(value))
    }
    return value
}

/// The reporter a run resolved in `context` gives a runaway push to:
/// `AlignmentGuideRun.reportGuideError(_:)` on a render pass, and none on a
/// measure pass, which works out the same placement.
@MainActor
func guideErrorReporter(in context: RenderContext) -> ((String) -> Void)? {
    guard !context.isMeasuring else { return nil }
    return { AlignmentGuideRun.reportGuideError($0) }
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
///   - holdsChildrenInside: Whether a child past the far edge of a region too
///     small for the run is pulled back inside, or left on the line for the
///     caller to draw past the edge — see
///     ``AlignmentGuideRun/resolve(resolved:sizes:fixedExtent:minimumExtent:report:holdsChildrenInside:regionGuide:)``.
///   - context: The container's context, which a child that is itself a
///     container needs to work out a guide it holds further in.
@MainActor
func horizontalGuideRun(
    _ children: [ChildView],
    sizes: [(width: Int, height: Int)],
    alignment: HorizontalAlignment,
    fixedExtent: Int? = nil,
    minimumExtent: Int = 0,
    holdsChildrenInside: Bool = true,
    context: RenderContext
) -> AlignmentGuideRun? {
    guard children.contains(where: \.providesAlignmentGuide) else { return nil }
    var resolved: [Double] = []
    resolved.reserveCapacity(children.count)
    var anyExplicit = false
    for (child, size) in zip(children, sizes) {
        let dimensions = ViewDimensions(width: size.width, height: size.height)
        let guide: Double
        if let explicit = child.explicitGuide(.horizontal(alignment), at: dimensions, context: context) {
            anyExplicit = true
            guide = explicit
        } else {
            guide = alignment[dimensions: dimensions]
        }
        resolved.append(checkedGuide(guide, dimensions: dimensions, context: context))
    }
    guard anyExplicit else { return nil }
    return .resolve(
        resolved: resolved, sizes: sizes.map(\.width),
        fixedExtent: fixedExtent, minimumExtent: minimumExtent, report: guideErrorReporter(in: context),
        holdsChildrenInside: holdsChildrenInside
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
/// There is no run to merge, so the child's guide simply meets the region's,
/// wherever that puts it: SwiftUI places a single child at the region's guide
/// less its own, outside the region if need be (measured,
/// `Tools/SwiftUIProbes/Alignment guides/guide2.out`, `guide5.out`: in
/// `.frame(width: 20, alignment: .leading)` a 6-wide view whose leading guide
/// is 5 is at -5, and with `.trailing` and guide 0 at 20). The caller draws
/// what falls outside past the region
/// (`FrameBuffer.splitPlacing(at:inWidth:height:)`). `context` is the one
/// `view` was rendered in.
@MainActor
func horizontalGuidePlacement<V: View>(
    of view: V, size: (width: Int, height: Int), alignment: HorizontalAlignment, in extent: Int,
    context: RenderContext
) -> Int? {
    guard V._providesAlignmentGuide else { return nil }
    let dimensions = ViewDimensions(width: size.width, height: size.height)
    guard let guide = explicitGuide(of: view, .horizontal(alignment), in: dimensions, context: context) else { return nil }
    return AlignmentGuideRun.place(
        guide: checkedGuide(guide, dimensions: dimensions, context: context),
        regionGuide: alignment[dimensions: ViewDimensions(width: extent, height: 0)], extent: extent,
        report: guideErrorReporter(in: context))
}

/// The vertical twin of ``horizontalGuidePlacement(of:size:alignment:in:context:)``.
@MainActor
func verticalGuidePlacement<V: View>(
    of view: V, size: (width: Int, height: Int), alignment: VerticalAlignment, in extent: Int,
    context: RenderContext
) -> Int? {
    guard V._providesAlignmentGuide else { return nil }
    let dimensions = ViewDimensions(width: size.width, height: size.height)
    guard let guide = explicitGuide(of: view, .vertical(alignment), in: dimensions, context: context) else { return nil }
    return AlignmentGuideRun.place(
        guide: checkedGuide(guide, dimensions: dimensions, context: context),
        regionGuide: alignment[dimensions: ViewDimensions(width: 0, height: extent)], extent: extent,
        report: guideErrorReporter(in: context))
}

/// The vertical placement of `children`, or `nil` when none of them gives an
/// explicit value for `alignment`.
///
/// The vertical twin of ``horizontalGuideRun(_:sizes:alignment:fixedExtent:minimumExtent:holdsChildrenInside:context:)``.
@MainActor
func verticalGuideRun(
    _ children: [ChildView],
    sizes: [(width: Int, height: Int)],
    alignment: VerticalAlignment,
    fixedExtent: Int? = nil,
    minimumExtent: Int = 0,
    holdsChildrenInside: Bool = true,
    context: RenderContext
) -> AlignmentGuideRun? {
    guard children.contains(where: \.providesAlignmentGuide) else { return nil }
    var resolved: [Double] = []
    resolved.reserveCapacity(children.count)
    var anyExplicit = false
    for (child, size) in zip(children, sizes) {
        let dimensions = ViewDimensions(width: size.width, height: size.height)
        let guide: Double
        if let explicit = child.explicitGuide(.vertical(alignment), at: dimensions, context: context) {
            anyExplicit = true
            guide = explicit
        } else {
            guide = alignment[dimensions: dimensions]
        }
        resolved.append(checkedGuide(guide, dimensions: dimensions, context: context))
    }
    guard anyExplicit else { return nil }
    return .resolve(
        resolved: resolved, sizes: sizes.map(\.height),
        fixedExtent: fixedExtent, minimumExtent: minimumExtent, report: guideErrorReporter(in: context),
        holdsChildrenInside: holdsChildrenInside
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
