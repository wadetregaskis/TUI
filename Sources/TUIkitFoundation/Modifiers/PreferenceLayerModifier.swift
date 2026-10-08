//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PreferenceLayerModifier.swift
//
//  `overlayPreferenceValue` and `backgroundPreferenceValue`: a layer built
//  from a preference the base's subtree published, laid in the base's frame.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// Lays a view built from a preference the base's subtree reduced over, or
/// under, the base — in the base's frame, as `.overlay` and
/// `.background(alignment:content:)` lay theirs.
struct PreferenceLayerModifier<Base: View, K: PreferenceKey, Layer: View>: View {
    /// The base content, whose subtree publishes `K`.
    let base: Base

    /// Builds the layer from the subtree's value of `K`.
    let transform: (K.Value) -> Layer

    /// Where the layer goes in the base's frame.
    let alignment: Alignment

    /// Whether the layer goes behind the base rather than over it.
    let isBackground: Bool

    var body: Never {
        fatalError("PreferenceLayerModifier renders via Renderable")
    }
}

extension PreferenceLayerModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // A measure collects no preferences, so there is no value to build the
        // layer from — and the layer cannot move the size, which is the base's.
        guard !context.isMeasuring else {
            return TUIkitView.renderToBuffer(base, context: context)
        }

        // The base's subtree in a scope of its own, so this reads what IT
        // published; popping merges that into the parent as normal. The layer
        // renders after the pop, so whatever it publishes lands in the parent
        // too — SwiftUI's "the values from both views are combined and made
        // visible to the parent".
        //
        // No memo declaration of its own: a writer in the base already declines
        // every ancestor memo (`PreferenceModifier`), and with none the value is
        // the key's default on every frame, which a cached buffer reproduces.
        let prefs = context.environment.preferenceStorage!
        prefs.push()
        let baseBuffer = TUIkitView.renderToBuffer(base, context: context)
        let value = prefs.pop()[K.self]

        // The base's size on every axis, which is what the measure promised:
        // with no frame on an axis there is nowhere to lay the layer, and
        // `.overlay`'s escape — drawing it whole — would draw a view the
        // measure never saw.
        guard baseBuffer.width > 0, baseBuffer.height > 0 else { return baseBuffer }
        guard let geometry = context.geometryCoordinator, geometry.hasAnchorSites else {
            return composite(value, over: baseBuffer, context)
        }

        // The anchors the base made are where its markers are, in the base's
        // cells — which are the layer's — before the layer is built: a reader
        // in it resolves them exactly, in this frame (`AnchorLayerScope`).
        // Where the reader itself is in the layer is found once the layer has
        // composited, and a reader that drew from a wrong answer — one not at
        // the layer's own origin, on its first frame — has the layer drawn once
        // more. The base is never drawn again: its anchors came from it.
        let layerContext = layerContext(context, modifierType: Self.self)
        guard let scope = geometry.anchorLayer(over: baseBuffer, layer: layerContext.identity) else {
            return composite(value, over: baseBuffer, context)
        }
        let checkpoint = RenderWalkCheckpoint(context: layerContext)
        // The layer's space is the base's frame, whose origin is this view's:
        // carried for the layer (started here when nothing above has), so a
        // reader is told where it is in the layer before it is drawn — at the
        // origin for a reader filling the layer, which is exact.
        let carried = context.carryingGeometryOrigin()
        let owner = geometry.enterOwner(
            of: [scope.space], from: context, in: carried, size: baseBuffer.cellSize)
        geometry.enterAnchorLayer(scope)
        var drawn = composite(value, over: baseBuffer, carried)
        geometry.leaveAnchorLayer(scope)
        geometry.leaveOwner(owner)
        guard geometry.resolve([scope.space], in: drawn, size: baseBuffer.cellSize) else { return drawn }
        geometry.noteCorrection(.layer)
        checkpoint.rollBack(context: layerContext)
        geometry.reenterOwner(owner)
        geometry.enterAnchorLayer(scope)
        drawn = composite(value, over: baseBuffer, carried)
        geometry.leaveAnchorLayer(scope)
        geometry.leaveOwner(owner)
        if geometry.resolve([scope.space], in: drawn, size: baseBuffer.cellSize) { geometry.noteResidual() }
        return drawn
    }

    /// The layer built from `value`, laid over (or under) `baseBuffer`.
    private func composite(_ value: K.Value, over baseBuffer: FrameBuffer, _ context: RenderContext) -> FrameBuffer {
        let layer = transform(value)
        return isBackground
            ? compositeLayer(
                layer, under: baseBuffer, alignment: alignment, context: context, modifierType: Self.self)
            : compositeLayer(
                layer, over: baseBuffer, alignment: alignment, context: context, modifierType: Self.self)
    }
}

extension PreferenceLayerModifier: Layoutable {
    /// The base's size: the layer is laid out inside it and cut to it.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(base, proposal: proposal, context: context)
    }
}
