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
        for (piece, alpha) in Self.shadowPieces(field, spans: nil) where alpha > 0 {
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

    /// The drop shadow's layer: each row of `field` painted from its first cell
    /// with any alpha to its last, in `escape`, and claimed at the alpha of each
    /// cell — `0` at a cell between two shadowed ones that the shadow misses,
    /// which keeps whatever is behind it exactly: compositing replaces every
    /// cell a line spans, and an unclaimed blank there would erase the glyph
    /// behind it.
    static func shadowLayer(_ field: ShadowField, escape: String) -> FrameBuffer {
        var lines: [String] = []
        var lineWidths: [Int] = []
        var spans: [Range<Int>?] = []
        lines.reserveCapacity(field.height)
        for row in 0..<field.height {
            let shadowed = (0..<field.width).filter { field.alpha(column: $0, row: row) > 0 }
            guard let first = shadowed.first, let last = shadowed.last else {
                lines.append("")
                lineWidths.append(0)
                spans.append(nil)
                continue
            }
            lines.append(String.spaces(first) + escape + String.spaces(last + 1 - first) + ANSIRenderer.reset)
            lineWidths.append(last + 1)
            spans.append(first..<(last + 1))
        }
        var layer = FrameBuffer(lines: lines, width: field.width, lineWidths: lineWidths)
        layer.opacityRegions = shadowPieces(field, spans: spans).compactMap { piece, alpha in
            alpha == .max ? nil : piece
        }
        return layer
    }

    /// `field` cut into rectangles of one alpha each, rows cut alike joined —
    /// each a claim on the field of its cells at that alpha. Where `spans` is
    /// given, only the cells inside its row's span are cut, and a row with none
    /// has no rectangle.
    static func shadowPieces(
        _ field: ShadowField, spans: [Range<Int>?]?
    ) -> [(piece: OpacityRegion, alpha: UInt8)] {
        let whole = OpacityRegion(offsetX: 0, offsetY: 0, width: field.width, height: field.height, opacity: 1)
        // `-1` outside a row's span: no claim there at all.
        let pieces = cutting(whole) { row, column -> Int in
            if let spans, !(spans[row]?.contains(column) ?? false) { return -1 }
            return Int(field.alpha(column: column, row: row))
        }
        return pieces.compactMap { piece, kind in
            guard kind >= 0 else { return nil }
            var claimed = piece
            claimed.fieldOpacity = OpacityRegion.opacity(of: UInt8(kind))
            return (claimed, UInt8(kind))
        }
    }
}
