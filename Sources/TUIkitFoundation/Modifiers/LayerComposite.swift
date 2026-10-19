//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LayerComposite.swift
//
//  A second layer laid out in a base view's frame and composited with it: the
//  shared half of `.overlay`, and of every modifier that draws one more view in
//  another's box.
//
//  Created by LAYERED.work
//  License: MIT

/// The child identity a layer drawn over (or under) a base renders at.
///
/// The base renders at the modifier's own identity; the layer under an identity
/// of its OWN. Rendered through the same context, the two subtrees bind their
/// `@State` under one `StateKey(identity, propertyIndex)`: same-typed properties
/// silently share a box, and differently-typed ones make `storage(for:default:)`
/// swap the box every frame, which resets BOTH sides to their defaults forever.
/// A badge, a focus ring or a loading veil over a stateful card is an ordinary
/// `.overlay()`, and any of them holding state corrupted the view underneath.
///
/// Index 1, with the base left where it was: the same shape
/// `ListRowStyleModifiers` uses for a row's background, and leaving the base at
/// the parent identity means no existing view's `@State` slot or focus id moves.
///
/// The step is keyed on the MODIFIER's type (`modifierType`), not the layer's:
/// in `.overlay { Badge() }.overlay { Badge() }` the outer modifier's base is
/// the inner one, so both render at one identity, and a step keyed on `Badge`
/// put both badges on one path, sharing state. The outer modifier's type
/// contains the inner's, so the two steps differ.
func layerContext(_ context: RenderContext, modifierType: Any.Type) -> RenderContext {
    context.withChildIdentity(erasedType: modifierType, index: 1)
}

/// Where a layer goes in a base's frame — or why it goes nowhere.
private enum LayerPlacement {
    /// The base has nothing at all in it: the layer is what there is to draw.
    case alone(FrameBuffer)
    /// The layer has nothing at all in it: the base is unchanged.
    case baseOnly
    /// The layer, rendered, and its offset in the base's frame. What of it a
    /// guide put past the base's frame rides among its floating layers, drawn
    /// there (`OverflowingPlacement.insideCarryingOverflow`).
    case placed(FrameBuffer, at: (x: Int, y: Int))
}

/// `layer` rendered in `baseBuffer`'s frame and placed in it by `alignment` —
/// the half an overlay and a background share.
@MainActor
private func placeLayer<Layer: View>(
    _ layer: Layer, in baseBuffer: FrameBuffer, alignment: Alignment,
    context: RenderContext, modifierType: Any.Type
) -> LayerPlacement {
    let overlayContext = layerContext(context, modifierType: modifierType)

    // Shortcut a layer with NOTHING in it — but `isEmpty` only inspects
    // in-flow lines, and a line-empty buffer can still be carrying the
    // whole point of the view. `OffsetView` documents exactly that output:
    // no lines, one `OverlayLayer` holding the offset content, plus its hit
    // regions. Returning the other layer then threw that away — the base
    // side losing the content AND its interactivity, the overlay side
    // losing a `.offset()`-positioned badge entirely. Falling through to
    // `composited(with:at:)` is correct for both: it keeps this buffer's
    // layers and regions and lifts the other's, shifted into place, and it
    // already special-cases a line-empty overlay for exactly this reason.
    if baseBuffer.isEmpty, baseBuffer.overlays.isEmpty, baseBuffer.hitTestRegions.isEmpty {
        return .alone(TUIkitView.renderToBuffer(layer, context: overlayContext))
    }

    // The overlay is laid out IN the base's frame, so it is offered the
    // size the base came back at rather than the whole space this modifier
    // was given. That is SwiftUI's rule, and it is what makes an overlay
    // whose own layout consumes its width — `.overlay { HStack { Spacer();
    // Text("!") } }` — pin to the base's trailing edge instead of to the
    // terminal's, eighty columns away and then clipped off.
    //
    // An axis the base has NO extent on is left alone: a zero-wide frame
    // draws nothing at all, and a base whose whole payload floats (an
    // `OffsetView`) reaches here with no in-flow lines and a layer.
    var framedContext = overlayContext
    if baseBuffer.width > 0 { framedContext.availableWidth = baseBuffer.width }
    if baseBuffer.height > 0 { framedContext.availableHeight = baseBuffer.height }
    // Where the alignment will put the layer, for a ramp spanning the base and
    // the carried geometry origin — from the layer's MEASURED size, worked out
    // only when one of them will be read. A layer that fills the base (a
    // `GeometryReader`) lands at its origin for every alignment.
    if framedContext.placesChildren, !framedContext.isMeasuring {
        let measured = measureChild(
            layer,
            proposal: ProposedSize(width: framedContext.availableWidth, height: framedContext.availableHeight),
            context: framedContext)
        framedContext = framedContext.placingChild(
            gradient: framedContext.gradientFrame,
            x: alignment.horizontal.childOffset(childWidth: measured.width, in: baseBuffer.width),
            y: alignment.vertical.childOffset(childHeight: measured.height, in: baseBuffer.height))
    }
    let overlayBuffer = TUIkitView.renderToBuffer(layer, context: framedContext)

    if overlayBuffer.isEmpty, overlayBuffer.overlays.isEmpty,
        overlayBuffer.hitTestRegions.isEmpty
    {
        return .baseOnly
    }

    // Calculate horizontal position — from the overlay's own explicit
    // `.alignmentGuide` when it set one, so a badge can hang off the corner
    // it is aligned to rather than sit squarely on it.
    let overlaySize = (width: overlayBuffer.width, height: overlayBuffer.height)
    let horizontalGuide = horizontalGuidePlacement(
        of: layer, size: overlaySize, alignment: alignment.horizontal, in: baseBuffer.width,
        context: framedContext)
    let horizontalOffset =
        horizontalGuide ?? alignment.horizontal.childOffset(childWidth: overlaySize.width, in: baseBuffer.width)

    // Calculate vertical position
    let verticalGuide = verticalGuidePlacement(
        of: layer, size: overlaySize, alignment: alignment.vertical, in: baseBuffer.height,
        context: framedContext)
    let verticalOffset =
        verticalGuide ?? alignment.vertical.childOffset(childHeight: overlaySize.height, in: baseBuffer.height)

    // A guide can put the layer partly or wholly outside the base's frame,
    // where SwiftUI draws it — a badge hung off a corner sits beside its label,
    // not on it (measured, `Tools/SwiftUIProbes/Alignment guides/guide2.out`,
    // `guide5.out`). The part the frame holds is composited into it; the rest is
    // drawn past it, at the layer's place in the stacking order. Only where the
    // base has a frame on both axes (see above for one with none), never on a
    // measure pass, which draws nothing and cuts the layer to the base, and
    // only along a guided axis: a layer larger than its base on an axis its
    // alignment places is cut to the base as it always was
    // (decisions-GUIDE3 B-GUIDE3-1), so the region there holds all of it and
    // the clamp below cuts it.
    let position = (x: horizontalOffset, y: verticalOffset)
    if horizontalGuide != nil || verticalGuide != nil, baseBuffer.width > 0, baseBuffer.height > 0,
        !framedContext.isMeasuring
    {
        let region = (
            width: horizontalGuide == nil ? max(baseBuffer.width, position.x + overlaySize.width) : baseBuffer.width,
            height: verticalGuide == nil
                ? max(baseBuffer.height, position.y + overlaySize.height) : baseBuffer.height)
        if !overlayBuffer.fits(at: position, inWidth: region.width, height: region.height) {
            let placement = overlayBuffer.splitPlacing(at: position, inWidth: region.width, height: region.height)
            return .placed(placement.insideCarryingOverflow, at: placement.insideOrigin)
        }
    }
    return .placed(overlayBuffer, at: position)
}

/// `composite` cut back to `baseBuffer`'s box.
///
/// `composited` grows to fit a layer that reaches past the base, and a layer
/// that resizes what it is laid over or under is a `ZStack` — the one thing
/// `.overlay` and `.background` are not. Cut back to the base's box with the
/// clamp every container already uses on content that came back larger than
/// the space it was given; it keeps the free-floating layers (a badge
/// `.offset()` off the corner still hangs there) and trims the in-flow hit and
/// opacity regions to what survives.
///
/// Per axis, and only where there is a frame to cut to: see `placeLayer` for
/// the base that has no in-flow lines.
private func clampedToBase(_ composite: FrameBuffer, _ baseBuffer: FrameBuffer) -> FrameBuffer {
    composite.clamped(
        toWidth: baseBuffer.width > 0 ? baseBuffer.width : composite.width,
        height: baseBuffer.height > 0 ? baseBuffer.height : composite.height)
}

/// The wake token for runs a layer shows the field of.
///
/// Asked under the modifier's type as well as its identity, the key
/// `AnimationStore` gives a modifier's animations: the base renders at this
/// identity, so `.overlay { A }.overlay { B }` puts two overlays at one path,
/// and a wake is kept per token. Under the path alone the outer's request
/// replaced the inner's, and the inner's label held its field between the
/// outer run's steps. The outer's `Base` holds the inner's type, so the two
/// are never one type — unless each one's base is an `AnyView`, which draws
/// its content at its own identity too. The type is spelled by its metadata
/// pointer, which no two types share, not by a hash of it, which two could.
private func layerWakeToken(_ prefix: String, context: RenderContext, modifierType: Any.Type) -> String {
    "\(prefix)-\(context.identity.path)-\(UInt(bitPattern: ObjectIdentifier(modifierType)))"
}

/// `layer` laid out in `baseBuffer`'s frame, by `alignment`, and composited
/// over it, cut back to the base's box.
///
/// - Parameters:
///   - layer: The view to lay over the base.
///   - baseBuffer: The base, already rendered at `context`'s identity.
///   - alignment: Where the layer goes in the base's frame.
///   - context: The modifier's context.
///   - modifierType: The modifier's own type — see ``layerContext(_:modifierType:)``.
/// - Returns: The composite, the base's size.
@MainActor
func compositeLayer<Layer: View>(
    _ layer: Layer, over baseBuffer: FrameBuffer, alignment: Alignment,
    context: RenderContext, modifierType: Any.Type
) -> FrameBuffer {
    let (overlayBuffer, offset): (FrameBuffer, (x: Int, y: Int))
    switch placeLayer(layer, in: baseBuffer, alignment: alignment, context: context, modifierType: modifierType) {
    case .alone(let buffer): return buffer
    case .baseOnly: return baseBuffer
    case .placed(let buffer, let at): (overlayBuffer, offset) = (buffer, at)
    }
    return compositeDrawnLayer(overlayBuffer, at: offset, over: baseBuffer, context: context, modifierType: modifierType)
}

/// `overlayBuffer`, already drawn and placed at `offset` in `baseBuffer`'s
/// frame, composited over the base, cut back to the base's box: the half of
/// ``compositeLayer(_:over:alignment:context:modifierType:)`` that follows the
/// placement, for a layer that is not a view.
///
/// - Parameters:
///   - overlayBuffer: The layer, inside the base's frame at `offset`.
///   - offset: Where the layer lands in the base's frame.
///   - baseBuffer: The base, already rendered at `context`'s identity.
///   - context: The modifier's context.
///   - modifierType: The modifier's own type — see ``layerContext(_:modifierType:)``.
/// - Returns: The composite, the base's size.
@MainActor
func compositeDrawnLayer(
    _ overlayBuffer: FrameBuffer, at offset: (x: Int, y: Int), over baseBuffer: FrameBuffer,
    context: RenderContext, modifierType: Any.Type
) -> FrameBuffer {
    // Composite the overlay onto the base, asking for a render at each step of a
    // run of the base whose field the overlay shows and whose frames turn it: the
    // composite punches the run there.
    let showingThrough = baseBuffer.runsShowingThrough(overlayBuffer, at: offset)
    if !showingThrough.isEmpty {
        context.requestWake(
            token: layerWakeToken("overlay-base-run", context: context, modifierType: modifierType),
            forNextStepOf: showingThrough.map { ($0.clock, $0.frameTicks) })
    }
    // What the layer draws past the base's frame rides among its floating
    // layers, lifted after the base's: over whatever the base floats past it.
    return clampedToBase(
        baseBuffer.compositedCarryingClaimsOverNothing(
            with: overlayBuffer, at: offset, palette: context.environment.palette),
        baseBuffer)
}

/// `layer` laid out in `baseBuffer`'s frame, by `alignment`, with the base
/// composited over it, cut back to the base's box.
///
/// "Behind" is exact here because compositing keeps two statements per cell:
/// a base cell that names no field of its own keeps the layer's field under
/// it, so `.background { Color.red }` colours every cell the base does not
/// colour itself, translucent fields included. What a cell cannot hold is two
/// glyphs, so a background GLYPH under any cell the base draws — a space
/// included — is covered: `ZStack`'s rule, for the same reason.
///
/// - Parameters:
///   - layer: The view to lay under the base.
///   - baseBuffer: The base, already rendered at `context`'s identity.
///   - alignment: Where the layer goes in the base's frame.
///   - context: The modifier's context.
///   - modifierType: The modifier's own type — see ``layerContext(_:modifierType:)``.
/// - Returns: The composite, the base's size.
@MainActor
func compositeLayer<Layer: View>(
    _ layer: Layer, under baseBuffer: FrameBuffer, alignment: Alignment,
    context: RenderContext, modifierType: Any.Type
) -> FrameBuffer {
    let (layerBuffer, offset): (FrameBuffer, (x: Int, y: Int))
    switch placeLayer(layer, in: baseBuffer, alignment: alignment, context: context, modifierType: modifierType) {
    case .alone(let buffer): return buffer
    case .baseOnly: return baseBuffer
    case .placed(let buffer, let at): (layerBuffer, offset) = (buffer, at)
    }
    return compositeDrawnLayer(layerBuffer, at: offset, under: baseBuffer, context: context, modifierType: modifierType)
}

/// `layerBuffer`, already drawn and placed at `offset` in `baseBuffer`'s frame,
/// with the base composited over it, cut back to the base's box: the half of
/// ``compositeLayer(_:under:alignment:context:modifierType:)`` that follows the
/// placement, for a layer that is not a view.
///
/// What the layer draws past the base's frame rides among its floating layers
/// (`OverflowingPlacement.insideCarryingOverflow`), and `offset` is where the
/// part inside the frame lands.
///
/// - Parameters:
///   - layerBuffer: The layer, inside the base's frame at `offset`.
///   - offset: Where the layer lands in the base's frame.
///   - baseBuffer: The base, already rendered at `context`'s identity.
///   - context: The modifier's context.
///   - modifierType: The modifier's own type — see ``layerContext(_:modifierType:)``.
/// - Returns: The composite, the base's size.
@MainActor
func compositeDrawnLayer(
    _ layerBuffer: FrameBuffer, at offset: (x: Int, y: Int), under baseBuffer: FrameBuffer,
    context: RenderContext, modifierType: Any.Type
) -> FrameBuffer {
    // `_ZStackCore`'s sequence for two children: a blank canvas the base's
    // size, the layer onto it at its offset, then the base over both — asking
    // for a render at each step of a run of the layer whose field the base
    // shows and whose frames turn it.
    let palette = context.environment.palette
    var result = FrameBuffer(emptyWithWidth: baseBuffer.width, height: baseBuffer.height)
    // What the layer draws past the base's frame rides among its floating
    // layers, lifted before the base's: under whatever the base floats past
    // it, and cut under the base's cells as the base lands.
    result.compositeCarryingClaimsOverNothing(with: layerBuffer, at: offset, palette: palette)
    let showingThrough = result.runsShowingThrough(baseBuffer, at: (x: 0, y: 0))
    if !showingThrough.isEmpty {
        context.requestWake(
            token: layerWakeToken("background-layer-run", context: context, modifierType: modifierType),
            forNextStepOf: showingThrough.map { ($0.clock, $0.frameTicks) })
    }
    result.compositeCarryingClaimsOverNothing(with: baseBuffer, at: (x: 0, y: 0), palette: palette)
    return clampedToBase(result, baseBuffer)
}

/// The size of a base with `layer` laid in its frame: the base's, flexibility
/// and all, except on an axis the base has no extent on.
///
/// The layer is laid out inside the base and ``compositeLayer(_:over:alignment:context:modifierType:)``
/// cuts the composite back to it, so on an axis the base spans the layer cannot
/// contribute a cell.
///
/// - Parameters:
///   - layer: The view laid in the base's frame.
///   - baseSize: The base's measured size.
///   - proposal: The proposal the base was measured with.
///   - context: The modifier's context.
///   - modifierType: The modifier's own type — see ``layerContext(_:modifierType:)``.
/// - Returns: The modifier's size.
@MainActor
func layeredSize<Layer: View>(
    _ layer: Layer, baseSize: ViewSize, proposal: ProposedSize,
    context: RenderContext, modifierType: Any.Type
) -> ViewSize {
    // Returned whole — `isNaturalSize` included, which this is entitled to
    // pass on because the answer IS the base's answer and consumes no other
    // measurement. The overlay is not measured at all here: it cannot move
    // the result, and a badge over a card is a subtree walked once per
    // enclosing measure pass for nothing.
    if baseSize.width > 0, baseSize.height > 0 { return baseSize }

    // No frame on at least one axis, so on that axis the overlay is what
    // there is to draw — the measure half of the two escapes in
    // ``compositeLayer(_:over:alignment:context:modifierType:)``, and it has to
    // agree with them.
    //
    // The same child identity the render uses, or the two passes resolve
    // different `@State` and measure a different view than they draw; and
    // the same frame on the axis that has one, or they disagree about how
    // much room the overlay was offered.
    var overlayContext = layerContext(context, modifierType: modifierType)
    var overlayProposal = proposal
    if baseSize.width > 0 {
        overlayContext.availableWidth = baseSize.width
        overlayProposal.width = baseSize.width
    }
    if baseSize.height > 0 {
        overlayContext.availableHeight = baseSize.height
        overlayProposal.height = baseSize.height
    }
    let overlaySize = measureChild(
        layer, proposal: overlayProposal, context: overlayContext)
    return ViewSize(
        width: baseSize.width > 0 ? baseSize.width : overlaySize.width,
        height: baseSize.height > 0 ? baseSize.height : overlaySize.height,
        isWidthFlexible: baseSize.width > 0
            ? baseSize.isWidthFlexible : overlaySize.isWidthFlexible,
        isHeightFlexible: baseSize.height > 0
            ? baseSize.isHeightFlexible : overlaySize.isHeightFlexible)
}
