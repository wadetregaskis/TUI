//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OpacityFading.swift
//
//  Marking what a subtree drew as faded: the claim `.opacity(_:)` stamps, the
//  colour effects' layer tint, and the default transition's fade — one rule for
//  the lines and one for the layers drawn past them. Moved here from
//  `_OpacityView` (TUIkitFoundation) so the default transition, below it,
//  fades a view's displaced drawing as `.opacity` does (decisions B-O4-2).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// How a fade is marked on what a subtree drew. See ``fading(_:by:cycle:wholeOf:appendingRectangle:)``
/// and ``fadingOverlays(_:by:cycle:)``.
package enum OpacityFading {
    /// `regions` multiplied by `factor`, with this view's own rectangle after
    /// them.
    ///
    /// **Nesting multiplies**, as it does in SwiftUI: a `0.5` group inside a
    /// `0.5` group shows at `0.25`. Doing it here rather than at the composite
    /// is what makes that fall out — an inner region already carries the
    /// product of everything inside it, so scaling by this view's factor is the
    /// whole of the rule.
    ///
    /// The order is load-bearing: the resolution takes the LAYER alpha from the
    /// first region covering a cell, so the inner product has to come before the
    /// outer rectangle that also covers it. (Ink and field are multiplied across
    /// every covering region instead, which is why this scales only `opacity` —
    /// scaling them here would double-count them there.) See
    /// ``FrameBuffer/resolvingOpacity(over:at:surface:palette:)``.
    package static func fading(
        _ regions: [OpacityRegion], by factor: Double, cycle: OpacityCycle?,
        wholeOf buffer: FrameBuffer, appendingRectangle: Bool
    ) -> [OpacityRegion] {
        var result = regions.map { region -> OpacityRegion in
            var scaled = region
            scaled.opacity *= factor
            // An inner cycle scales with everything else about the inner
            // region: a breathing badge inside a half-faded panel breathes
            // between half the values it would alone.
            scaled.cycle = region.cycle?.scaled(by: factor)
            return scaled
        }
        guard appendingRectangle else { return result }
        // The whole of what this subtree drew. Ragged lines are not a problem:
        // a rectangle claiming columns a line does not reach resolves to
        // nothing there, because there is no source cell to blend.
        result.append(
            OpacityRegion(
                offsetX: 0, offsetY: 0, width: buffer.width, height: buffer.lines.count,
                opacity: factor, cycle: cycle))
        return result
    }

    /// `overlays`, with the ones this view actually DREW faded to match its
    /// lines — and the ones it merely hosts left alone.
    ///
    /// The distinction is ``OverlayLayer/isScreenLevel``, and it is the same one
    /// `.hidden()` and `.allowsHitTesting(false)` turn on:
    ///
    /// - an **anchored** layer — an `.offset`/`.position` child, a popover — is
    ///   this subtree's own drawing, displaced. Fading the subtree without
    ///   fading it left the displaced part at full strength beside faded
    ///   siblings.
    /// - a **centred** layer is a `.sheet`/`.alert` panel over the whole
    ///   screen. `.opacity` recolours what this view draws; it is not a way to
    ///   dim a dialog the view opened, any more than it is in SwiftUI, where
    ///   the sheet is hosted by the window and a modifier on the presenter
    ///   cannot reach it.
    ///
    /// Recursive, because a layer's own content can carry layers.
    ///
    /// A layer is marked rather than faded, for the same reason the lines are:
    /// where it lands is where what is behind it is known, and `composited`
    /// lifts an overlay's opacity regions along with the rest of its payload.
    package static func fadingOverlays(
        _ overlays: [OverlayLayer], by factor: Double, cycle: OpacityCycle? = nil
    ) -> [OverlayLayer] {
        // Fully opaque is marked like any other value, for the reason
        // `.opacity(_:)`'s render gives (`_OpacityView`): a displaced child of a `.opacity(1)` subtree
        // has to composite against what it lands on exactly as its siblings in
        // flow do, or the two disagree about what a background-less cell shows.
        overlays.map { layer in
            guard !layer.isScreenLevel else { return layer }
            var faded = layer
            faded.content.opacityRegions = fading(
                layer.content.opacityRegions, by: factor, cycle: cycle,
                wholeOf: layer.content, appendingRectangle: !layer.content.isEmpty)
            faded.content.overlays = fadingOverlays(
                layer.content.overlays, by: factor, cycle: cycle)
            return faded
        }
    }
}
