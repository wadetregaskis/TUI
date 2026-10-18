//  🖥️ TUIkit — Terminal UI Kit for Swift
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
import TUIkitCore
import TUIkitView

/// ``View/background(_:in:fillStyle:)``'s view: the shape filled, laid in the
/// view's frame and drawn behind it as ``View/background(alignment:content:)``
/// draws any view — with one difference, which is what makes a shape behind
/// padded text look like the shape.
///
/// Behind a view, a background's GLYPH shows only where the view draws no cell,
/// and padding is cells: blank ones. A capsule behind `Text("Tag").padding(.horizontal,
/// 1)` would lose its caps `▐ ▌` under the padding, and a rounded rectangle its
/// quadrant corners. So where the shape covers only part of a cell, and the view's
/// cell there shows nothing — a space with no field, no reverse and no line drawn
/// across it — the view's cell is claimed at a field of 0: the compositor's
/// "nothing at all", which leaves the shape's cell as it was. Everywhere else the
/// view is in front, as behind any background. A shape covering whole cells
/// (a rectangle) claims nothing.
struct _ShapeBackground<Content: View, S: Shape, Style: ShapeStyle>: View {
    let content: Content
    let shape: S
    let style: Style
    let fillStyle: FillStyle

    var body: Never { fatalError("_ShapeBackground renders via Renderable") }
}

extension _ShapeBackground: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var base = TUIkitView.renderToBuffer(content, context: context)
        let (columns, rows) = (base.width, base.height)
        if columns > 0, rows > 0 {
            let drawn = resolvedShape(shape, in: context, columns: columns, rows: rows)
            let coverage = ShapeCoverage(
                cellsOf: drawn, evenOdd: fillStyle.isEOFilled,
                frame: ShapeFrame(columns: columns, rows: rows, aspect: context.environment.imageCellAspect))
            var claims: [OpacityRegion] = []
            for (row, line) in base.lines.enumerated() {
                let partial = coverage.runs(row: row) { $0 > 0 && $0 < 1 }
                guard !partial.isEmpty else { continue }
                let nothing = line.columnsShowingNothing(width: columns)
                for run in partial {
                    for column in run where nothing[column] {
                        claims.appendCoalescing(
                            OpacityRegion.claim(
                                offsetX: column, offsetY: row, width: 1, height: 1, inkAlpha: .max, fieldAlpha: 0))
                    }
                }
            }
            base.opacityRegions += claims
        }
        return compositeLayer(
            shape.fill(style, style: fillStyle), under: base, alignment: .center, context: context,
            modifierType: Self.self)
    }
}

extension _ShapeBackground: Layoutable {
    /// The view's size: the shape is laid in it.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}
