//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FrameBuffer+Shadow.swift
//
//  A shadow as cells: blank cells in the shadow's colour, each with a claim on
//  its field at the alpha the shadow lays there, composited beneath a view (a
//  drop shadow) or over it (an inner one) by the compositor that already lays a
//  translucent `.background` beneath one and a translucent `.overlay` over one.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling

extension FrameBuffer {

    /// This buffer — a view's drawing — with a drop shadow composited beneath it.
    ///
    /// The shadow is a layer of blank cells in the shadow colour's opaque
    /// spelling, each claiming its field at the shadow's alpha there
    /// (``ShadowField/drop(footprint:style:peak:)``), laid under this buffer as
    /// `.background { … }` lays a translucent view: the part inside the view's
    /// frame is drawn on the canvas the view lands on, so it shows wherever the
    /// view leaves a cell's field to what is behind it and is hidden wherever the
    /// view paints a field of its own; the part past the frame is drawn there at
    /// the view's place in the stacking order (`FrameBuffer.splitPlacing`) — over
    /// the views before it, cut under the ones after it, and clipped by a
    /// container that clips. Either way the shadow's cells are resolved against
    /// what is behind them where that is known, so what is behind darkens, its
    /// glyphs included.
    ///
    /// - Parameters:
    ///   - style: The shadow. Its kind is not read.
    ///   - context: The modifier's context: the palette and the compositor's
    ///     wakes.
    ///   - owner: The modifier's own type, for those wakes.
    /// - Returns: The composite, this buffer's size; this buffer as it is when
    ///   the shadow lays nothing.
    @MainActor
    func castingDropShadow(_ style: ShadowStyle, context: RenderContext, owner: Any.Type) -> FrameBuffer {
        let palette = context.environment.palette
        let colour = style.color.resolve(with: palette)
        guard width > 0, !lines.isEmpty,
            let field = ShadowField.drop(footprint: ShadowFootprint(self), style: style, peak: colour.alpha),
            !field.isEmpty
        else { return self }
        let layer = Self.shadowLayer(field, escape: ANSIRenderer.backgroundCode(for: colour.opaqueSpelling))
        let position = (x: field.originX, y: field.originY)
        guard !layer.fits(at: position, inWidth: width, height: height) else {
            return compositeDrawnLayer(layer, at: position, under: self, context: context, modifierType: owner)
        }
        let placement = layer.splitPlacing(at: position, inWidth: width, height: height)
        return compositeDrawnLayer(
            placement.insideCarryingOverflow, at: placement.insideOrigin, under: self, context: context,
            modifierType: owner)
    }

    /// This buffer — a view's drawing — with an inner shadow composited over the
    /// cells it paints (``ShadowField/inner(footprint:style:peak:)``).
    ///
    /// Laid as `.overlay { … }` lays a translucent view: a blank cell in the
    /// shadow's colour over a glyph veils it, darkening its ink and its field by
    /// the same alpha, and keeps the glyph. One rectangle of one alpha at a time,
    /// because compositing replaces every cell a layer's line spans, and a line
    /// across the view would replace the cells between two veiled ones.
    ///
    /// - Parameters:
    ///   - style: The shadow. Its kind is not read.
    ///   - palette: The palette the colour resolves in and the compositor
    ///     resolves against.
    /// - Returns: The composite, this buffer's size; this buffer as it is when
    ///   the shadow lays nothing.
    func castingInnerShadow(_ style: ShadowStyle, palette: any Palette) -> FrameBuffer {
        let colour = style.color.resolve(with: palette)
        guard width > 0, !lines.isEmpty,
            let field = ShadowField.inner(footprint: ShadowFootprint(self), style: style, peak: colour.alpha),
            !field.isEmpty
        else { return self }
        let escape = ANSIRenderer.backgroundCode(for: colour.opaqueSpelling)
        var result = self
        for (piece, alpha) in Self.shadowPieces(field) where alpha > 0 {
            var block = FrameBuffer(
                lines: Array(
                    repeating: escape + String.spaces(piece.width) + ANSIRenderer.reset, count: piece.height),
                width: piece.width, uniformWidth: true)
            block.opacityRegions += OpacityRegion.claim(
                width: piece.width, height: piece.height, inkAlpha: .max, fieldAlpha: alpha
            ).map { [$0] } ?? []
            result.compositeCarryingClaimsOverNothing(
                with: block, at: (x: piece.offsetX, y: piece.offsetY), palette: palette)
        }
        return result
    }

    /// The drop shadow's layer: the whole of `field`'s rectangle painted in
    /// `escape`, each cell claimed at the shadow's alpha there — and a cell the
    /// shadow misses (a corner past the last ring, the gap in "a b"'s shadow)
    /// claimed with its whole layer at `0`, which leaves whatever is behind it
    /// untouched: compositing replaces every cell a line spans, and an unclaimed
    /// blank there would erase the glyph behind it.
    ///
    /// A rectangle, every line the same, rather than each row from its first
    /// shadowed cell to its last: what is drawn past the view's frame becomes
    /// overflow layers, cut into one for each run of lines that start at the same
    /// column (`OverlayLayer.drawnParts()`), and a shadow's rows each start at
    /// their own column round its corners — sixteen layers for a radius of ten,
    /// sixteen cards of them enough to spend the root compositor's whole budget.
    /// As a rectangle it is at most four, one a side of the frame, whatever the
    /// radius.
    static func shadowLayer(_ field: ShadowField, escape: String) -> FrameBuffer {
        let line = escape + String.spaces(field.width) + ANSIRenderer.reset
        var layer = FrameBuffer(
            lines: Array(repeating: line, count: field.height), width: field.width, uniformWidth: true)
        layer.opacityRegions = shadowPieces(field).compactMap { piece, alpha in
            alpha == .max ? nil : piece
        }
        return layer
    }

    /// `field` cut into rectangles of one alpha each, rows cut alike joined —
    /// each a claim on the field of its cells at that alpha, and at alpha `0` a
    /// claim of the whole layer at `0`: the cells keep what is behind them as it
    /// is, glyph, colours and attributes, rather than blending to it.
    static func shadowPieces(_ field: ShadowField) -> [(piece: OpacityRegion, alpha: UInt8)] {
        let whole = OpacityRegion(offsetX: 0, offsetY: 0, width: field.width, height: field.height, opacity: 1)
        let pieces = cutting(whole) { row, column in field.alpha(column: column, row: row) }
        return pieces.map { piece, alpha in
            var claimed = piece
            if alpha == 0 {
                claimed.opacity = 0
            } else {
                claimed.fieldOpacity = OpacityRegion.opacity(of: alpha)
            }
            return (claimed, alpha)
        }
    }
}
