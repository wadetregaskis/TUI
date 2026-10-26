//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameBuffer+Overlays.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation

extension FrameBuffer {
    /// Composites every accumulated ``overlays`` layer onto this buffer in
    /// z-order — ascending ``OverlayLevel`` (popover < modal < alert <
    /// notification), then ``OverlayLayer/zIndex`` — resolving each layer's
    /// placement against a `maxWidth` × `maxHeight` area.
    ///
    /// A layer that ``OverlayLayer/centered`` is placed in the centre of that
    /// area; otherwise it draws at its (clamped, flip-on-overflow) offset. A layer
    /// that ``OverlayLayer/dimsBackground`` first dims everything beneath it into a
    /// flat, inert backdrop (using `palette` for the colours) — so a screen-level
    /// modal reads as modal over the whole screen no matter where it was attached.
    ///
    /// Layers that a composited layer itself emits join the same ordered queue
    /// and take their place by level, bounded by a cap against a pathological
    /// re-emitting layer.
    ///
    /// This is exactly what `RenderLoop` runs at the screen root; it's public so
    /// tests can reproduce the composited result a headless `renderToBuffer`
    /// otherwise leaves pending in ``overlays``.
    public func compositingOverlays(maxWidth: Int, maxHeight: Int, palette: any Palette) -> FrameBuffer {
        compositingOverlays(maxWidth: maxWidth, maxHeight: maxHeight, palette: palette, images: nil)
    }

    /// ``compositingOverlays(maxWidth:maxHeight:palette:)`` knowing the pictures
    /// the app has put in the terminal, so a translucent layer over one draws a
    /// copy of it with the layer applied (`OpacityBlend+Pictures.swift`);
    /// without them, a layer over a picture is blended as if the picture's
    /// cells were colours. What the screen root runs.
    package func compositingOverlays(
        maxWidth: Int, maxHeight: Int, palette: any Palette, images: TerminalImageStore?
    ) -> FrameBuffer {
        // The page's OWN opacity resolves first, before anything is drawn over
        // it. This is the screen root, so nothing is behind the page but the
        // surface — and if a region were still pending when a layer composited
        // over it, the region would go on naming those cells and the LAYER's
        // cells would be faded at the root instead of the page's.
        var result = resolvingOpacity(surface: palette.background, palette: palette, images: images)
        // ONE queue, re-sorted every time a layer is drawn. A layer nested in
        // another layer's content — an alert presented from inside a sheet —
        // is lifted into `overlays` only when its host composites, and a pass
        // that sorted its snapshot and drained it would draw the newcomer
        // after everything in that pass: a `.notification` toast, declared
        // topmost, was buried by the nested alert's dimming. Lifted layers
        // join the queue behind what is still pending and take their place by
        // level; a drawn host is drawn, so its own nested layers land above it
        // whatever their level. A cap guards against a pathological layer that
        // keeps re-emitting itself; 256 is far beyond real use. It counts the
        // draws that LIFT layers, the only ones that can feed the queue: one
        // that lifts nothing (content past a region, a shadow's cells) only
        // drains it, so every layer queued is drawn however many there are.
        // Counting every draw, the lowest levels went first and the cap fell
        // on the highest: 256 drop shadows' worth of overflow, at `.popover`
        // under the displaced-drawing z index, and the alert over them was
        // never drawn, an invisible dialog holding the input.
        // A pinned section header or footer that got here passed no vertical
        // scroll view — a pinned stack that is not scrolled — and the flow
        // already shows it where it belongs (`OverlayLayer.scrollPin`). So
        // is one lifted out of a layer's content below.
        // Panels drawn as a set (`.tooltips(.always)`) are placed together,
        // here and in each lifted batch, where every one of them is known.
        var queue = OverlayLayer.arrangingPeers(
            result.overlays.filter { $0.scrollPin == nil }, maxWidth: maxWidth, maxHeight: maxHeight
        ).enumerated().map { (order: $0.offset, layer: $0.element) }
        result.overlays = []
        var nextOrder = queue.count
        var liftsRemaining = 256
        while !queue.isEmpty {
            queue.sort { lhs, rhs in
                if lhs.layer.level != rhs.layer.level {
                    return lhs.layer.level < rhs.layer.level
                }
                if lhs.layer.zIndex != rhs.layer.zIndex {
                    return lhs.layer.zIndex < rhs.layer.zIndex
                }
                // Content past its region is its view's own cells at its place
                // in the stacking order (`OverlayLayer.isOverflow`) — `.offset`
                // and `.position` too since L6 moved them there. A layer that
                // floats — a matched view in flight (Deliberate deviations A8) —
                // is over every view, after it as well as before it. So at one
                // level and z index the overflow goes first, whatever order the
                // tree emitted them in: a removal playing past its stack, later
                // in the tree, covered a matched view carried over it.
                if lhs.layer.isOverflow != rhs.layer.isOverflow {
                    return lhs.layer.isOverflow
                }
                return lhs.order < rhs.order
            }
            let layer = queue.removeFirst().layer
            // A surface's box, for the overflow its content carries (below).
            var surface: (x: Int, y: Int, width: Int, height: Int)?
            // Whether a layer hung beside its anchor went to the anchor's
            // leading side, which its own such layers then try first
            // (`OverlayLayer.opensLeading`).
            var wentLeading = false
            do {
                // A modal/alert layer dims everything beneath it first.
                if layer.dimsBackground {
                    // Expand to the full area first, so the backdrop dims the whole
                    // screen and the centred layer has room — even when the page
                    // beneath is shorter or narrower than the screen. Padding moves
                    // no content, so the (already-shifted) layers are preserved.
                    if result.height < maxHeight || result.width < maxWidth {
                        let target = max(result.height, maxHeight)
                        let expanded = (0..<target).map { row -> String in
                            row < result.lines.count
                                ? result.lines[row].padToVisibleWidth(maxWidth)
                                : String.spaces(maxWidth)
                        }
                        result = result.replacingLines(expanded)
                    }
                    result = result.veiledAsBackdrop(
                        by: palette.overlayBackground, surface: palette.background, palette: palette, images: images)
                }
                let placed = layer.placed(maxWidth: maxWidth, maxHeight: maxHeight)
                wentLeading = layer.besideAnchorWidth != nil && placed.x < layer.offsetX
                if layer.isOpaque {
                    surface = (x: placed.x, y: placed.y, width: placed.content.width, height: placed.content.height)
                }
                // A surface hides what is behind it, so its blanks are painted
                // onto the surface colour BEFORE anything else happens to them —
                // see ``OverlayLayer/isOpaque``. Cells that already state a
                // background are untouched, so a dialog that paints itself
                // comes back byte-identical.
                //
                // Before the blend, not after, and that ordering is the whole
                // of what makes a fading toast still fade: `resolvingOpacity`
                // blends the layer against what is behind it, so painting first
                // gives it a background to fade FROM. Painting afterwards would
                // stamp the surface colour over the blend and freeze every
                // translucent layer fully opaque.
                var content =
                    layer.isOpaque
                    ? placed.content.paintedOver(
                        background: ANSIRenderer.backgroundCode(
                            for: palette.background.resolve(with: palette)))
                    : placed.content
                // And a surface is the backdrop of every fade INSIDE it (§96.2): a
                // label faded in a sheet fades into the sheet, whose surface stays
                // put. Only a centred layer — a sheet, an alert, a cover — because a
                // fade outside the presenter never reaches one (`OpacityFading.fadingOverlays`),
                // so every region it carries is its own content's. An anchored layer
                // may carry the presenter's fade, which must take the surface with
                // it, in the same list as its content's, and cannot be told apart
                // here.
                if layer.isOpaque, layer.isScreenLevel {
                    content = content.resolvingOpacity(
                        onOpaqueFill: { nil }, surface: palette.background, palette: palette)
                }
                // Painted, a surface states every cell's field, so it is composited
                // as it is. Asked what it lands on, its own `ESC[49m` — the surface
                // on a palette whose page is the terminal's own — is what compositing
                // reads as no field and fills, and every such menu, drop-down,
                // popover and toast showed the colour under its first cell through
                // it (`Opacity as composition.md` §98).
                //
                // A run of what is below that the layer shows the field of, and whose
                // frames turn it, is punched here as a `ZStack` punches one, but nothing
                // asks for a render at its steps (`FrameBuffer.runsShowingThrough`): this
                // runs after the walk, with no render context to ask from, so an
                // `.offset` label over a breathing fill holds the drawn frame's field
                // between renders — a known gap (§109).
                result = result.compositedResolvingOpacity(
                    with: content, at: (x: placed.x, y: placed.y), palette: palette,
                    overlayIsPainted: layer.isOpaque, images: images)
            }
            // What this layer's content carried, lifted by the composite: into
            // the queue, not the next pass.
            //
            // A surface keeps what its content drew past a placement's region
            // (`OverlayLayer.isOverflow`) inside its box: a menu's, a
            // popover's or a dialog's content belongs on the surface, and drawn
            // past its border it reads as corruption of the page.
            guard !result.overlays.isEmpty, liftsRemaining > 0 else {
                result.overlays = []
                continue
            }
            liftsRemaining -= 1
            let liftedLayers = OverlayLayer.arrangingPeers(result.overlays, maxWidth: maxWidth, maxHeight: maxHeight)
            for lifted in liftedLayers where lifted.scrollPin == nil {
                var kept = lifted
                if wentLeading, kept.besideAnchorWidth != nil { kept.opensLeading = true }
                if let box = surface, lifted.isOverflow {
                    guard let cut = lifted.cropped(x: box.x, y: box.y, width: box.width, height: box.height)
                    else { continue }
                    kept = cut
                }
                queue.append((order: nextOrder, layer: kept))
                nextOrder += 1
            }
            result.overlays = []
        }
        return result
    }
}
