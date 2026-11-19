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
        store.counts.composited += 1
        if let verifying, verifying != result, let cache = context.renderCache {
            cache.noteRenderMemoMismatch(
                viewType: "layer composite (\(inputs.direction))", served: verifying, fresh: result,
                identity: context.identity.path)
        }
        guard !askedForAWake, !Self.mayDrawIntoTheImageStore(inputs.layer, inputs.images),
            !Self.mayDrawIntoTheImageStore(inputs.base, inputs.images)
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
