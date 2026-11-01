//  🖥️ TUI — A Terminal UI framework for Swift
//  ZStack.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - ZStack

/// A view that stacks its children on top of each other (z-axis).
///
/// `ZStack` layers views on top of each other, with later views
/// appearing above earlier ones. Apply ``View/zIndex(_:)`` to a child to
/// override the tree order — higher z-index values draw on top.
///
/// The stack is as wide and tall as its largest child. Each child is placed
/// within that frame according to `alignment`, and compositing is
/// character-level: a smaller child only paints its own cells, so the larger
/// layer beneath shows through around it (and a coloured fill is preserved).
///
/// # Example
///
/// Centre a label over a filled background. There is no need to pad the label
/// to width — `alignment` (default `.center`) positions it:
///
/// ```swift
/// ZStack {
///     Text("████████████████")
///     Text("Overlay")           // → "████Overlay█████"
/// }
/// ```
///
/// ```swift
/// ZStack {
///     Text("BBB").zIndex(1)   // drawn on top despite appearing first
///     Text("AAA")
/// }
/// ```
nonisolated public struct ZStack<Content: View>: View {
    /// The alignment of the children.
    public let alignment: Alignment

    /// The content of the stack.
    public let content: Content

    /// Creates a z-stack with the specified options.
    ///
    /// - Parameters:
    ///   - alignment: The alignment of children (default: .center).
    ///   - content: A ViewBuilder that defines the children.
    public init(
        alignment: Alignment = .center,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.content = content()
    }

    @MainActor public var body: some View {
        _ZStackCore(alignment: alignment, content: content)
    }
}

// MARK: - Internal ZStack Core

/// Internal view that handles the actual rendering of ZStack.
private struct _ZStackCore<Content: View>: View, Renderable {
    let alignment: Alignment
    let content: Content

    var body: Never {
        fatalError("_ZStackCore renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Children resolve through the two-pass `ChildView` API (as
        // `sizeThatFits` below already did), so `ChildViewProvider` content —
        // a `ForEach`, above all — expands to its individual layers with
        // per-child identities. The legacy single-pass `resolveChildInfos`
        // used here before only expanded `ChildInfoProvider`s, which `ForEach`
        // is not, so `ZStack { ForEach }` rendered nothing at all (the ZStack
        // face of issue #8).
        //
        // A container of its own, it takes its sections apart, whatever the
        // walk that drew it kept whole (`RenderContext.takingSectionsApart()`):
        // it publishes no axis, which is how every stack clears that.
        let context = context.takingSectionsApart().offeringAWidth(unless: isStaticallyOneView(Content.self))
        // A layer that has left takes no room, and is drawn where it was while
        // its removal plays (`StackGlide`).
        let split = stackChildren(of: content, context: context)
        let children = split.laidOut

        // Draw children in ascending z-index. Ties keep their tree order, so
        // the sort is made stable by using the original index as a tiebreaker.
        let ordered = children.enumerated().sorted { lhs, rhs in
            if lhs.element.zIndex != rhs.element.zIndex {
                return lhs.element.zIndex < rhs.element.zIndex
            }
            return lhs.offset < rhs.offset
        }.map(\.element)

        // The stack's frame is the union of its children's sizes (like SwiftUI,
        // a ZStack is as wide/tall as its widest/tallest child). Spacers have
        // no visual box in a ZStack.
        let drawn = ordered.filter { !$0.isSpacer }
        let placed = childContexts(drawn, context: context)
        let buffers = drawn.indices.map { index in
            drawn[index].render(
                width: context.availableWidth, height: context.availableHeight,
                context: placed?[index] ?? context)
        }
        // Explicit guides on either axis, when any layer set one. They can grow
        // the frame past the largest layer — a layer hanging off the alignment
        // line pushes the others across — so they are resolved before the frame
        // size is decided.
        let sizes = buffers.map { (width: $0.width, height: $0.height) }
        let horizontalRun = horizontalGuideRun(
            drawn, sizes: sizes, alignment: alignment.horizontal,
            minimumExtent: buffers.map(\.width).max() ?? 0, context: context)
        let verticalRun = verticalGuideRun(
            drawn, sizes: sizes, alignment: alignment.vertical,
            minimumExtent: buffers.map(\.height).max() ?? 0, context: context)
        let frameWidth = horizontalRun?.extent ?? buffers.map(\.width).max() ?? 0
        let frameHeight = verticalRun?.extent ?? buffers.map(\.height).max() ?? 0
        // A zero-size frame means no child drew anything IN FLOW — but a
        // child can still be carrying the whole point of the view as a
        // free-floating layer: `OffsetView` renders exactly that (no lines, one
        // `OverlayLayer` holding the offset content and its hit regions).
        // Returning a bare buffer dropped them, so `ZStack { Text("💨").offset() }`
        // rendered nothing at all. Fold them in instead — the ZStack face of the
        // OverlayModifier bug fixed in 3aedeb1f, and what every other combining
        // op already promises.
        //
        // The in-flow result is unchanged: every buffer reaching this guard is
        // line-empty (a non-empty line would have made `frameWidth > 0`), so
        // `composited` takes its lift-the-layers branch and no line content is
        // produced. The offsets are (0, 0) because a zero-size frame gives every
        // alignment a zero child offset, and each layer's own position already
        // lives inside it. `ZStack {}` still yields a bare buffer — `reduce`
        // over no children returns the initial value.
        guard frameWidth > 0, frameHeight > 0 else {
            if let gliding = context.glidingStackBuffer(
                drawn, buffers: buffers, at: buffers.map { _ in ChildPlacement(x: 0, y: 0) },
                departing: split.departing, width: 0, height: 0)
            {
                return gliding
            }
            return buffers.reduce(FrameBuffer()) {
                $0.compositedCarryingClaimsOverNothing(
                    with: $1, at: (x: 0, y: 0), in: CompositeEnvironment(context.environment))
            }
        }

        // Composite each child onto a blank frame at its alignment offset, in
        // ascending z-order. Character-level compositing (vs. the old whole-line
        // overlay) means a narrower child no longer truncates a wider one beneath
        // it — the uncovered sides of the lower layer show through — and a child's
        // own offset is honoured so `alignment` actually positions it. A child
        // still paints its full bounding box (including blank-but-coloured fills),
        // so backgrounds are preserved; to centre a label over a fill, size the
        // label to its content and let `alignment` place it rather than padding
        // the string by hand.
        //
        // A guided run larger than the space the stack was given keeps every
        // guide on one line, and what hangs past that space is drawn past it,
        // in the layer's place in the stacking order (decisions B-GUIDE-1),
        // rather than being cut by the clamp every view passes through. The
        // canvas is that space, not the run, on a measure pass too, which
        // keeps only what is inside: a run can be 2^20 cells (decisions
        // B-GUIDE-2), and a canvas that size was built every frame.
        let guided = horizontalRun != nil || verticalRun != nil
        let overhangs =
            guided && (frameWidth > context.availableWidth || frameHeight > context.availableHeight)
        let drawnWidth = overhangs ? min(frameWidth, max(0, context.availableWidth)) : frameWidth
        let drawnHeight = overhangs ? min(frameHeight, max(0, context.availableHeight)) : frameHeight
        let layers = buffers.enumerated().map { index, buffer in
            (
                buffer: buffer,
                x: horizontalRun?.offsets[index]
                    ?? alignment.horizontal.childOffset(childWidth: buffer.width, in: frameWidth),
                y: verticalRun?.offsets[index]
                    ?? alignment.vertical.childOffset(childHeight: buffer.height, in: frameHeight)
            )
        }
        // While a layer is on its way to where the alignment now puts it under
        // an animation, or a layer that has left is still leaving, each is
        // drawn where it is (`StackGlide`).
        if let gliding = context.glidingStackBuffer(
            drawn, buffers: buffers, at: layers.map { ChildPlacement(x: $0.x, y: $0.y) },
            departing: split.departing, width: drawnWidth, height: drawnHeight)
        {
            return gliding
        }
        return FrameBuffer.layered(
            layers, width: drawnWidth, height: drawnHeight, splitsOverhang: overhangs,
            wakeToken: "zstack-base-run-\(context.identity.path)", context: context)
    }
}

// MARK: - Placing the Layers

extension _ZStackCore {
    /// Each layer's context, placed where the alignment will put it — for a
    /// ramp spanning the stack and the carried geometry origin — or `nil` when
    /// neither will be read, which is almost always.
    ///
    /// From the layers' MEASURED sizes (the stack's own `sizeThatFits` took the
    /// same measures, so they are memo hits): the rendered ones are a pass
    /// later. Exact wherever measure and render agree; explicit alignment
    /// guides are left to the residual (`GeometryAsk`).
    func childContexts(_ drawn: [ChildView], context: RenderContext) -> [RenderContext]? {
        guard context.placesChildren, !context.isMeasuring else { return nil }
        let proposal = ProposedSize(width: context.availableWidth, height: context.availableHeight)
        let sizes = drawn.map { $0.measure(proposal: proposal, context: context) }
        let frameWidth = sizes.map(\.width).max() ?? 0
        let frameHeight = sizes.map(\.height).max() ?? 0
        let gradientFrame = context.gradientContentFrame(width: frameWidth, height: frameHeight)
        return sizes.map { size in
            context.placingChild(
                gradient: gradientFrame,
                x: alignment.horizontal.childOffset(childWidth: size.width, in: frameWidth),
                y: alignment.vertical.childOffset(childHeight: size.height, in: frameHeight))
        }
    }
}

// MARK: - Layout

extension _ZStackCore: Layoutable {
    /// Measures the z-stack without rendering: it is as wide/tall as its largest
    /// child (the union of their sizes, matching `renderToBuffer`'s frame), and is
    /// flexible on an axis when any child is — a flexible child fills that extent,
    /// so the stack does too. Alignment and z-index affect placement/draw order,
    /// not size.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let context = context.takingSectionsApart().offeringAWidth(unless: isStaticallyOneView(Content.self))
        // A layer that has left takes no room (`StackGlide`).
        let children = stackChildren(of: content, context: context).laidOut
        guard !children.isEmpty else { return ViewSize.fixed(0, 0) }

        var maxWidth = 0
        var maxHeight = 0
        var hasFlexibleWidth = false
        var hasFlexibleHeight = false
        // Built only when a guide will ask for it — the test below already gates
        // the READ, so asking it here too spares an ordinary layered stack an
        // allocation and a fill per pass that nothing reads.
        let hasGuides = anyAlignmentGuide(in: children)
        var guideSizes: [(width: Int, height: Int)] = []
        if hasGuides { guideSizes.reserveCapacity(children.count) }
        let widthLimit = proposal.width ?? context.availableWidth
        // Asked for its ideal width, a stack of layers counts them as a column
        // counts its rows: one that came back filling the limit has no width of
        // its own (`wholeContentWidth(of:limit:)`), and counted, it made the
        // stack as wide as the ladder's rung.
        let asksIdealWidth = proposal.width == nil && context.asksIdealWidth
        for child in children {
            let size = child.measure(proposal: proposal, context: context)
            let width = asksIdealWidth ? wholeContentWidth(of: size, limit: widthLimit) : size.width
            // Spacers have no visual box in a ZStack — `renderToBuffer` filters
            // them — so they must not contribute a guide here either.
            if hasGuides {
                guideSizes.append(
                    child.isSpacer
                        ? (width: 0, height: 0) : (width: width, height: size.height))
            }
            maxWidth = max(maxWidth, width)
            maxHeight = max(maxHeight, size.height)
            hasFlexibleWidth = hasFlexibleWidth || size.isWidthFlexible
            hasFlexibleHeight = hasFlexibleHeight || size.isHeightFlexible
        }
        // A guide can push a layer off the alignment line and grow the frame
        // past the largest child; the render does this, so the measure must.
        if hasGuides {
            let drawn = children.indices.filter { !children[$0].isSpacer }
            if let run = horizontalGuideRun(
                drawn.map { children[$0] }, sizes: drawn.map { guideSizes[$0] },
                alignment: alignment.horizontal, minimumExtent: maxWidth, context: context)
            {
                maxWidth = run.extent
            }
            if let run = verticalGuideRun(
                drawn.map { children[$0] }, sizes: drawn.map { guideSizes[$0] },
                alignment: alignment.vertical, minimumExtent: maxHeight, context: context)
            {
                maxHeight = run.extent
            }
        }
        // Never advertise larger than the constraint (mirrors VStack/HStack) —
        // and, under the ideal-width ask, never call a capped answer flexible,
        // as they do not (`wholeContentFlexibility(_:width:limit:)`).
        let heightLimit = proposal.height ?? context.availableHeight
        let width = min(maxWidth, max(0, widthLimit))
        return ViewSize(
            width: width,
            height: min(maxHeight, max(0, heightLimit)),
            isWidthFlexible: asksIdealWidth
                ? wholeContentFlexibility(hasFlexibleWidth, width: width, limit: widthLimit)
                : hasFlexibleWidth,
            isHeightFlexible: hasFlexibleHeight)
    }
}

// MARK: - Guides Through the Layers

@MainActor extension ZStack {
    /// Its content's answer: the stack lays its content out as its own
    /// layers, so a guide in any of them can be the stack's to report.
    public static var _providesAlignmentGuide: Bool { Content._providesAlignmentGuide }
}

extension _ZStackCore {
    /// See ``ZStack/_providesAlignmentGuide``.
    static var _providesAlignmentGuide: Bool { Content._providesAlignmentGuide }
}

/// See `EdgeGuideReach.swift`: a stack of several layers reports none.
extension _ZStackCore: EdgeGuideReaching {
    static var mayReportEdgeOrCentreGuide: Bool {
        TUIFoundation.mayReportEdgeOrCentreGuide(ofStackContent: Content.self)
    }
}

extension _ZStackCore: AlignmentGuideQuerying {
    /// The guide the layers give, each moved by where the stack puts it,
    /// merged by the guide's rule — an edge or centre guide only out of a
    /// stack that is statically one layer
    /// (``AlignmentGuideQuery/staysInside(contentOf:)``). The placement is `renderToBuffer`'s, from
    /// the layers' sizes at the stack's: each axis its own guide run, or the
    /// stack's alignment within the largest layer.
    func explicitGuide(
        _ query: AlignmentGuideQuery, in dimensions: ViewDimensions, context: RenderContext
    ) -> Double? {
        guard !query.staysInside(contentOf: Content.self) else { return nil }
        let context = context.takingSectionsApart().offeringAWidth(unless: isStaticallyOneView(Content.self))
        let children = stackChildren(of: content, context: context).laidOut
        guard anyAlignmentGuide(in: children) else { return nil }
        let drawn = children.filter { !$0.isSpacer }
        let sizes = drawn.map { child -> (width: Int, height: Int) in
            let size = child.measure(
                proposal: ProposedSize(width: dimensions.width, height: dimensions.height),
                context: context)
            return (width: min(size.width, dimensions.width), height: min(size.height, dimensions.height))
        }
        let widest = sizes.map(\.width).max() ?? 0
        let tallest = sizes.map(\.height).max() ?? 0
        let horizontalRun = horizontalGuideRun(
            drawn, sizes: sizes, alignment: alignment.horizontal, minimumExtent: widest,
            context: context)
        let verticalRun = verticalGuideRun(
            drawn, sizes: sizes, alignment: alignment.vertical, minimumExtent: tallest,
            context: context)
        let frameWidth = horizontalRun?.extent ?? widest
        let frameHeight = verticalRun?.extent ?? tallest
        let frames = sizes.enumerated().map { index, size in
            (
                x: horizontalRun?.offsets[index]
                    ?? alignment.horizontal.childOffset(childWidth: size.width, in: frameWidth),
                y: verticalRun?.offsets[index]
                    ?? alignment.vertical.childOffset(childHeight: size.height, in: frameHeight),
                width: size.width, height: size.height
            )
        }
        return mergedExplicitGuide(query, of: drawn, frames: frames, context: context)
    }
}

// MARK: - Spacing Beside the Layers

@MainActor extension ZStack {
    /// Its content's answer: a `ZStack` states its layers' edges, merged.
    public static var _statesSpacingPreference: Bool { Content._statesSpacingPreference }
}

extension _ZStackCore {
    /// See ``ZStack/_statesSpacingPreference``.
    static var _statesSpacingPreference: Bool { Content._statesSpacingPreference }
}

/// A `ZStack`'s layers each form every edge, so it states them all merged, as
/// SwiftUI's does (measured, `Tools/SwiftUIProbes/Stack spacing per
/// pair/nested.out`: `HStack { ZStack { tight }; box }` keeps no gap).
extension _ZStackCore: SpacingPreferenceProviding {
    func preferredSpacing(context: RenderContext) -> ViewSpacing {
        let context = context.takingSectionsApart().offeringAWidth(unless: isStaticallyOneView(Content.self))
        var merged = ViewSpacing()
        // A spacer's "none" is along a stack's axis, and a `ZStack` has none:
        // a spacer among its layers states nothing (measured: `HStack {
        // ZStack { box; Spacer() }; box }` keeps the default gap).
        for child in stackChildren(of: content, context: context).laidOut where !child.isSpacer {
            if let stated = statedSpacing(of: child, context: context) { merged.formUnion(stated) }
        }
        return merged
    }
}

/// On any edge, any layer's but a spacer's (`mayStateSpacing(_:along:)`): a
/// `ZStack` merges its layers' preferences, and a spacer's states nothing.
extension _ZStackCore: SpacingReaching {
    static func mayStateSpacing(along axis: Axis) -> Bool {
        memberMayStateSpacing(Content.self, along: axis, countingSpacers: false)
    }
}

// MARK: - Equatable

extension ZStack: Equatable where Content: Equatable {
    public static func == (lhs: ZStack<Content>, rhs: ZStack<Content>) -> Bool {
        lhs.alignment == rhs.alignment && lhs.content == rhs.content
    }
}
