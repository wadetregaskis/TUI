//  🖥️ TUI — A Terminal UI framework for Swift
//  ZStackPulledLayers.swift
//
//  SCROLL-FIT's parallel shape through a `ZStack` (design B-SCROLLFIT-12): a
//  z-stack holding a pulled view hands the scroll view's request to each
//  pulled layer at its place in the stack's frame and draws the band of
//  every layer, layered as the stack layers them (`ScrollParallelFill.swift`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// `StateStorage` property indices for `_ZStackCore` (file-scope: a generic
/// type cannot hold static storage).
private enum ZStackStateIndex {
    /// The pulled layers' positions (``PulledParallelState``). Negative, and
    /// apart from the row's: a lone row in a z-stack is drawn at the stack's
    /// own identity. Range -220, claimed in ``StateStorage/StateKey``'s table.
    static let pulledLayers = -221
}

extension _ZStackCore: ScrollPlacing {}

@MainActor extension _ZStackCore {
    /// The band a request asks of this stack, when it holds a pulled view and
    /// a request reaches it (its own measure filed it); `nil` otherwise, and
    /// the stack draws its layers whole.
    ///
    /// Each layer stands where the alignment puts it at its measured size in
    /// the frame of the largest, as the stack places them, drawn in z-order.
    /// What the stack adds for a glide or an explicit alignment guide is left
    /// out, as it is for a pulled row.
    func renderPulledLayers(context: RenderContext) -> FrameBuffer? {
        guard !context.isMeasuring, let window = context.environment.scrollContentWindow, window.reply != nil,
            window.isAtOrigin(context.identity),
            let cache = context.renderCache, cache.pullConsumers.kind(of: context.identity) == .pullsChildren
        else { return nil }
        let drawn = stackChildren(of: content, context: context).laidOut.enumerated().sorted { lhs, rhs in
            lhs.element.zIndex != rhs.element.zIndex
                ? lhs.element.zIndex < rhs.element.zIndex : lhs.offset < rhs.offset
        }.map(\.element).filter { !$0.isSpacer }
        guard !drawn.isEmpty else { return nil }
        let proposal = ProposedViewSize(width: context.availableWidth, height: nil)
        let sizes = drawn.map { $0.measure(proposal: proposal, context: context) }
        let frameWidth = sizes.map(\.width).max() ?? 0
        let frameHeight = sizes.map(\.height).max() ?? 0
        let placed = drawn.indices.map { index -> PulledParallelChild in
            let identity = drawn[index].identity(under: context)
            return PulledParallelChild(
                identity: identity,
                y: alignment.vertical.childOffset(childHeight: sizes[index].height, in: frameHeight),
                height: sizes[index].height, isPulled: cache.pullConsumers.holdsConsumer(below: identity))
        }
        guard
            let pieces = PulledParallel.fill(
                window: window, children: placed, state: pulledLayersState(context: context), context: context,
                render: { index, layerContext, height in
                    drawn[index].render(width: context.availableWidth, height: height, context: layerContext)
                })
        else { return nil }
        let bandHeight = pieces.lazy.compactMap { $0?.height }.first ?? 0
        let layers = pieces.compactMap { $0 }.map { piece in
            (buffer: piece, x: alignment.horizontal.childOffset(childWidth: piece.width, in: frameWidth), y: 0)
        }
        return FrameBuffer.layered(
            layers, width: frameWidth, height: bandHeight, splitsOverhang: false,
            wakeToken: "zstack-base-run-\(context.identity.path)", context: context)
    }

    /// The pulled layers' positions, kept at the stack's own identity.
    private func pulledLayersState(context: RenderContext) -> PulledParallelState {
        let stateStorage = context.stateStorage!
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: ZStackStateIndex.pulledLayers)
        let box: StateBox<PulledParallelState> = stateStorage.storage(for: key, default: PulledParallelState())
        stateStorage.markActive(context.identity)
        return box.value
    }
}
