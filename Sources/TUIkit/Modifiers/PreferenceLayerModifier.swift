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
            return TUIkit.renderToBuffer(base, context: context)
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
        let baseBuffer = TUIkit.renderToBuffer(base, context: context)
        let layer = transform(prefs.pop()[K.self])

        // The base's size on every axis, which is what the measure promised:
        // with no frame on an axis there is nowhere to lay the layer, and
        // `.overlay`'s escape — drawing it whole — would draw a view the
        // measure never saw.
        guard baseBuffer.width > 0, baseBuffer.height > 0 else { return baseBuffer }
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
