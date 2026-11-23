//  🖥️ TUI — A Terminal UI framework for Swift
//  LayerComposite+Kept.swift
//
//  A layer composite served from the last frame's while a `TimelineView` is
//  live (`LayerCompositeKeep`): the half of `compositeDrawnLayer` that asks for
//  one and keeps one.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// One composite of `compositeDrawnLayer`'s, looked for in the render cache's
/// ``LayerCompositeKeep`` and kept there: `nil` when no timeline is live, on a
/// measure, or with no cache.
///
/// Asked before the composite is made (``served()``) and told of the one made
/// (``keep(_:askedForAWake:)``). Under `TUI_VERIFY_RENDER_MEMO` a composite that
/// would be served is made again instead, and the two are compared.
@MainActor
struct KeptLayerComposite {
    private let store: LayerCompositeKeep
    private let slot: Int
    private let inputs: LayerCompositeKeep.Inputs
    private let context: RenderContext
    /// What ``served()`` found under the verifier, which ``keep(_:askedForAWake:)``
    /// compares with the composite made again.
    private var verifying: FrameBuffer?

    /// - Parameters:
    ///   - direction: Whether `layer` goes over `base` or under it.
    ///   - layer: The layer, inside the base's frame at `offset`.
    ///   - offset: Where the layer lands in the base's frame.
    ///   - base: The base.
    ///   - composite: What the environment says about spending claims.
    ///   - context: The modifier's context.
    ///   - modifierType: The modifier's own type: with the identity, the place
    ///     kept at, since `.overlay { A }.overlay { B }` composites twice at one
    ///     identity.
    init?(
        _ direction: LayerCompositeKeep.Direction, layer: FrameBuffer, at offset: (x: Int, y: Int),
        base: FrameBuffer, _ composite: CompositeEnvironment, _ context: RenderContext, _ modifierType: Any.Type
    ) {
        guard !context.isMeasuring, let cache = context.renderCache, cache.plainMemo.frameBodies.timelinesLive,
            cache.plainMemo.frameBodies.isOn
        else { return nil }
        store = cache.plainMemo.layerComposites
        slot = context.identity.structuralHash ^ ObjectIdentifier(modifierType).hashValue
        inputs = LayerCompositeKeep.Inputs(
            direction, layer: layer, at: offset, base: base, palette: composite.palette,
            linearLight: composite.linearLight, images: composite.images)
        self.context = context
    }

    /// A stack's layers, composited on a blank `width` × `height` canvas
    /// (`FrameBuffer.layered`): `nil` when no timeline is live, on a measure,
    /// or with no cache.
    ///
    /// - Parameters:
    ///   - layers: Each layer's picture and where it lands, in drawing order.
    ///   - width: The canvas's width.
    ///   - height: The canvas's height.
    ///   - splitsOverhang: Whether a layer past the canvas is drawn past it.
    ///   - context: The stack's context.
    ///   - stackType: The stack's own type: with the identity, the place kept at.
    init?(
        stacking layers: [(buffer: FrameBuffer, x: Int, y: Int)], width: Int, height: Int, splitsOverhang: Bool,
        _ context: RenderContext, _ stackType: Any.Type
    ) {
        guard !context.isMeasuring, let cache = context.renderCache, cache.plainMemo.frameBodies.timelinesLive,
            cache.plainMemo.frameBodies.isOn
        else { return nil }
        let composite = CompositeEnvironment(context.environment)
        store = cache.plainMemo.layerComposites
        slot = context.identity.structuralHash ^ ObjectIdentifier(stackType).hashValue
        inputs = LayerCompositeKeep.Inputs(
            .stacked(width: width, height: height, splitsOverhang: splitsOverhang),
            placed: layers.map { LayerCompositeKeep.Placed($0.buffer, x: $0.x, y: $0.y) },
            palette: composite.palette, linearLight: composite.linearLight, images: composite.images)
        self.context = context
    }

    /// Whether a composite of these inputs may ask for a wake: one does where
    /// a later layer shows a field of an earlier one's animated runs, which no
    /// layer without runs has. A cheap superset, for a composite that does not
    /// say whether it asked.
    var mayAskForAWake: Bool {
        inputs.placed.contains { !$0.buffer.animatedCells.isEmpty }
    }

    /// The composite of these inputs the last frame made, or `nil`.
    mutating func served() -> FrameBuffer? {
        guard let kept = store.served(at: slot, inputs) else { return nil }
        guard RenderCache.verifiesRenderMemo else { return kept }
        verifying = kept
        return nil
    }

    /// Notes `result`, the composite of these inputs, and keeps it unless
    /// making it did what a serve would not do again: asked for a wake, or
    /// may have drawn into the image store.
    func keep(_ result: FrameBuffer, askedForAWake: Bool) {
        store.counts.composited &+= 1
        if let verifying, verifying != result, let cache = context.renderCache {
            cache.noteRenderMemoMismatch(
                viewType: "layer composite (\(inputs.direction))", served: verifying, fresh: result,
                identity: context.identity.path)
        }
        guard !askedForAWake, !inputs.placed.contains(where: { Self.mayDrawIntoTheImageStore($0.buffer, inputs.images) })
        else { return }
        store.keep(result, at: slot, inputs)
    }

    /// Whether compositing `buffer` may have made a registration in the image
    /// store: a claim that frosts (its backdrop), or, with a store to draw a
    /// faded copy into, a picture's cell under a claim. Any scalar past
    /// U+FFFFF begins with the byte 0xF4 in UTF-8, the picture placeholder
    /// (U+10EEEE) among them: a cheap superset, read only as a composite is kept.
    private static func mayDrawIntoTheImageStore(_ buffer: FrameBuffer, _ images: AnyObject?) -> Bool {
        if buffer.opacityRegions.contains(where: \.frosts) { return true }
        guard images != nil else { return false }
        return buffer.lines.contains { $0.utf8.contains(0xF4) }
    }
}
