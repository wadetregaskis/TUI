//  🖥️ TUI — A Terminal UI framework for Swift
//  LayoutCore+Pulled.swift
//
//  SCROLL-FIT's pull through an app's own `Layout` (design B-SCROLLFIT-13):
//  a layout holding a pulled view — `MyLayout { header; LazyVStack(10k);
//  footer }` in scroll content — is served by the placements its own
//  `placeSubviews` makes, which the render pays for anyway. The subviews
//  placed beside the pulled ones are drawn with them in the parallel shape
//  (`ScrollParallelFill.swift`); those placed wholly below follow where the
//  pulled ones' drawing ends, as a column places what follows a pulled child.
//  A layout whose rects the adapter cannot serve — pulled views one below
//  another, whose places hang on each other's drawing — is drawn whole, its
//  lazy stacks drawn whole in it as they were before the pull.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// `StateStorage` property indices for `_LayoutCore` (file-scope: a generic
/// type cannot hold static storage).
private enum LayoutStateIndex {
    /// The pulled layout's positions (``PulledParallelState``). Negative: a
    /// lone composite subview is drawn at the layout's own identity. Range
    /// -220, claimed in ``StateStorage/StateKey``'s table.
    static let pulledLayout = -222
}

/// A lazy stack among an app's layout's subviews is pulled because the
/// layout hands its request on — unless the layout's placements say it
/// cannot (``LayoutPull/follows(_:pulled:identities:)``), when it is filed as
/// drawn whole (``PullConsumers/noteLayout(_:places:)``) and its stacks are
/// not. The conformance answers where the layout has an identity of its own;
/// the filing, wherever it is drawn (``noteLayout(context:)``).
extension _LayoutCore: ScrollPlacing {}

/// One subview as the layout placed it: where, and at the size it is drawn.
struct LayoutPlacedSubview {
    let child: ChildView
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

/// Reading a layout's placements as a shape the fill serves.
enum LayoutPull {
    /// For each placed subview, whether it follows the pulled ones — placed
    /// wholly below the lead (the tallest pulled one), so where the lead's
    /// drawing ends, not where its estimate put it, places it — or `nil` when
    /// the placements cannot be served: no pulled subview is placed, one is
    /// placed twice (two requests at one identity), or a pulled one stands
    /// beyond the lead's lines rather than beside them, its place hanging on
    /// the lead's drawing (or the lead's on its own).
    static func follows(_ placed: [LayoutPlacedSubview], pulled: [Bool], identities: [ViewIdentity]) -> [Bool]? {
        // The lead as the fill picks it.
        let pulledIndices = placed.indices.filter { pulled[$0] }
        guard let lead = pulledIndices.max(by: { placed[$0].height < placed[$1].height }) else { return nil }
        guard Set(pulledIndices.map { identities[$0] }).count == pulledIndices.count else { return nil }
        let top = placed[lead].y
        let end = top + placed[lead].height
        for index in pulledIndices {
            let y = placed[index].y
            let beside =
                placed[index].height == 0 ? (top...end).contains(y) : y < end && y + placed[index].height > top
            guard beside else { return nil }
        }
        return placed.indices.map { !pulled[$0] && placed[$0].y >= end }
    }
}

@MainActor extension _LayoutCore {
    /// Files this layout, in scroll content, as a container that places its
    /// subviews against a request (``PullConsumers/noteLayout(_:places:)``),
    /// before its subviews are measured: they are siblings at the identity it
    /// is drawn at, which is whatever holds it — a branch, an `AnyView`, an
    /// app's view — so its type is not on their identity chain for
    /// `isPulledWhereItStands` to read, as `_VStackCore`'s is on its rows'.
    func noteLayout(context: RenderContext) {
        guard context.scrollContentOriginDepth != 0 else { return }
        context.renderCache?.pullConsumers.noteLayout(context.identity, places: true)
    }

    /// Whether this layout, measured as holding a pulled view, can be served
    /// by its placements, made here at the size just measured; when it
    /// cannot, it is filed as drawn whole and its subtree's measures are
    /// dropped, so that its lazy stacks measure again as stacks drawn whole
    /// (`isPulledWhereItStands`), and `false`: the caller measures again.
    func servesPull(
        subviews: LayoutSubviews, placements: LayoutPlacements, size: ViewSize, proposal: ProposedViewSize,
        cache: inout L.Cache, context: RenderContext
    ) -> Bool {
        guard let renderCache = context.renderCache else { return false }
        // Already drawn whole, and measured so: a view below that is filed
        // whatever this layout does (one in a nested scroll view's content).
        guard renderCache.pullConsumers.layoutPlaces(context.identity) != false else {
            renderCache.pullConsumers.note(context.identity, as: nil)
            return true
        }
        let bounds = CellRect(x: 0, y: 0, width: max(0, size.width), height: max(0, size.height))
        layout.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
        let placed = placedSubviews(subviews, placements: placements, context: context)
        let identities = placed.map { $0.child.identity(under: context) }
        let pulled = identities.map { renderCache.pullConsumers.holdsConsumer(below: $0) }
        if LayoutPull.follows(placed, pulled: pulled, identities: identities) != nil { return true }
        renderCache.pullConsumers.noteLayout(context.identity, places: false)
        renderCache.clearAffected(by: context.identity)
        renderCache.forgetPassMeasures()
        return false
    }

    /// Each placement, with the size its subview is drawn at: the proposal's,
    /// else the subview's measure for it.
    func placedSubviews(
        _ subviews: LayoutSubviews, placements: LayoutPlacements, context: RenderContext
    ) -> [LayoutPlacedSubview] {
        placements.entries.map { entry in
            let child = subviews[entry.index].child
            let size = child.measure(proposal: entry.proposal, context: context)
            return LayoutPlacedSubview(
                child: child, x: entry.x, y: entry.y, width: entry.proposal.width ?? size.width,
                height: entry.proposal.height ?? size.height)
        }
    }

    /// The band a request asks of this layout, when it holds a pulled view
    /// and a request reaches it (its own measure filed it); `nil` otherwise,
    /// and the layout draws its subviews whole.
    ///
    /// Served by the placements just made: each pulled subview is handed the
    /// request at its place, every other one drawn whole at its own and cut
    /// to the band, and one placed wholly below the pulled ones moved by how
    /// far the lead's drawing ends from where its estimate put it. Drawn at
    /// the layout's places across, through the eager drawing's glide and
    /// z-order (``composited(_:pictures:at:departing:width:height:context:)``).
    func renderPulledLayout(
        subviews: LayoutSubviews, placements: LayoutPlacements, departing: [ChildView], width: Int,
        gradientFrame: GradientFrame?, context: RenderContext
    ) -> FrameBuffer? {
        guard !context.isMeasuring, let window = context.environment.scrollContentWindow, window.reply != nil,
            window.isAtOrigin(context.identity),
            let cache = context.renderCache, cache.pullConsumers.kind(of: context.identity) == .pullsChildren
        else { return nil }
        let placed = placedSubviews(subviews, placements: placements, context: context)
        let identities = placed.map { $0.child.identity(under: context) }
        let pulled = identities.map { cache.pullConsumers.holdsConsumer(below: $0) }
        guard let follows = LayoutPull.follows(placed, pulled: pulled, identities: identities) else { return nil }
        let children = placed.indices.map { index in
            PulledParallelChild(
                identity: identities[index], y: placed[index].y, height: placed[index].height,
                isPulled: pulled[index], follows: follows[index])
        }
        guard
            let band = PulledParallel.fill(
                window: window, children: children, state: pulledLayoutState(context: context), context: context,
                holder: { PulledParallel.holder(of: $0, count: placed.count, child: { placed[$0].child }, context: context) },
                place: { index, seek in
                    PulledParallel.place(
                        of: seek, in: placed[index].child, width: placed[index].width, height: placed[index].height,
                        context: context)
                },
                render: { index, childContext, height in
                    placed[index].child.render(
                        width: placed[index].width, height: height,
                        context: childContext.placingChild(gradient: gradientFrame, x: placed[index].x, y: placed[index].y))
                })
        else { return nil }
        return composited(
            placed.map(\.child), pictures: band.pieces.map { $0?.buffer },
            at: placed.indices.map { ChildPlacement(x: placed[$0].x, y: band.pieces[$0]?.y ?? 0) },
            departing: departing, width: width, height: band.height, context: context)
    }

    /// The height `child`, placed at line `y` and `height` tall, is drawn at.
    ///
    /// `height`, but under a measuring render of a layout holding a pulled
    /// view, for a pulled child: only down to the bottom of the lines the
    /// render was given. A scroll view's measuring render — the first frame's
    /// walk of the page for its chrome — draws its content only down to the
    /// viewport's bottom, and a lazy stack under a measure takes no request,
    /// so one drawn at the height its measure estimated built every row.
    func measuringHeight(_ height: Int, of child: ChildView, at y: Int, context: RenderContext) -> Int {
        guard context.isMeasuring, let cache = context.renderCache,
            cache.pullConsumers.kind(of: context.identity) == .pullsChildren,
            cache.pullConsumers.holdsConsumer(below: child.identity(under: context))
        else { return height }
        return min(height, max(0, context.availableHeight - y))
    }

    /// The pulled layout's positions, kept at its own identity.
    private func pulledLayoutState(context: RenderContext) -> PulledParallelState {
        let stateStorage = context.stateStorage!
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: LayoutStateIndex.pulledLayout)
        let box: StateBox<PulledParallelState> = stateStorage.storage(for: key, default: PulledParallelState())
        // Nothing else marks the layout's own identity active.
        stateStorage.markActive(context.identity)
        return box.value
    }
}
