//  🖥️ TUI — A Terminal UI framework for Swift
//  ShapeBackgroundModifier.swift
//
//  A shape filled behind a view: `background(_:in:fillStyle:)`, whose rounded
//  corners and caps show through the view's blank cells.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import TUICore
import TUIView

/// ``View/background(_:in:fillStyle:)``'s view: the shape filled, laid in the
/// view's frame and drawn behind it as ``View/background(alignment:content:)``
/// draws any view — with one difference, which is what makes a shape behind
/// padded text look like the shape.
///
/// Behind a view, a background's GLYPH shows only where the view draws no cell,
/// and padding is cells: blank ones. A capsule behind `Text("Tag").padding(.horizontal,
/// 1)` would lose its caps `▐ ▌` under the padding, and a rounded rectangle its
/// quadrant corners. So where the shape's fill draws a glyph — a cap, a quadrant
/// corner, a half block — and the view's cell there shows nothing — a space with
/// no field, no reverse and no line drawn across it — the view's cell is claimed
/// at a field of 0: the compositor's "nothing at all", which leaves the shape's
/// cell as it was. Everywhere else the view is in front, as behind any
/// background; a cell the fill paints whole is field, which shows through a
/// blank cell anyway. A shape covering whole cells (a rectangle) claims nothing.
///
/// The glyphs are the fill's own, drawn as it will draw them, not read off the
/// path's coverage: the box tier cuts a quadrant from every rounded corner
/// however small its radius, and a radius of a quarter column covers its corner
/// cell whole.
nonisolated struct _ShapeBackground<Content: View, S: Shape, Style: ShapeStyle>: View {
    let content: Content
    let shape: S
    let style: Style
    let fillStyle: FillStyle

    @MainActor var body: Never { fatalError("_ShapeBackground renders via Renderable") }
}

@MainActor extension _ShapeBackground: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var base = TUIView.renderToBuffer(content, context: context.raisingBackgroundProminence(under: style))
        if base.width > 0, base.height > 0 { base.opacityRegions += claims(over: base, context: context) }
        return compositeLayer(
            shape.fill(style, style: fillStyle), under: base, alignment: .center, context: context,
            modifierType: Self.self)
    }

    /// The claims that let the fill's glyphs show through `base`'s blank
    /// cells: one wherever the fill draws a glyph over a cell of `base` that
    /// shows nothing.
    private func claims(over base: FrameBuffer, context: RenderContext) -> [OpacityRegion] {
        let (columns, rows) = (base.width, base.height)
        let environment = context.environment
        let aspect = environment.imageCellAspect
        let drawn = resolvedDrawing(of: shape, as: .fill(fillStyle), in: context, columns: columns, rows: rows)
        let painter = ShapePainter(
            paint: style.paint(in: environment).unshadowed,
            extent: context.gradientFrame ?? GradientFrame(width: columns, height: rows),
            aspect: aspect, palette: environment.palette)
        // In colour: with none, a field is a block glyph, and the view's blank
        // cells have always covered those.
        let cells = ShapeCells.drawing(
            drawn.shape, as: drawn.drawing, frame: ShapeFrame(columns: columns, rows: rows, aspect: aspect),
            painter: painter, monochrome: false, wholeCells: !environment.blockElementsFillTheLine)
        return base.claimsShowingGlyphs(of: cells)
    }
}

@MainActor extension _ShapeBackground: Layoutable {
    /// The view's size: the shape is laid in it.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context.raisingBackgroundProminence(under: style))
    }
}
