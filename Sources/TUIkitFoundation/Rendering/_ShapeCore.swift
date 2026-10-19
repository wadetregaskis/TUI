//  🖥️ TUIkit — Terminal UI Kit for Swift
//  _ShapeCore.swift
//
//  Where a shape becomes cells: the frame in square units, the paint per cell
//  or per half cell, and the choice between the box-drawing tier and the
//  rasterizer.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import TUIkitCore
import TUIkitStyling
import TUIkitView

// MARK: - The rectangle family

/// A shape whose edges land on its frame's cell boundaries, so the box-drawing
/// tier can draw it (``ShapeBoxCells``): the rectangle family, uninset.
protocol BoxDrawnShape {
    /// The corner radii in `rect`, in square units — `nil` where this value of
    /// the shape is not on cell boundaries after all (an inset one).
    func boxCorners(in rect: CGRect) -> RectangleCornerRadii?
}

/// A shape that stands for another the environment decides — `.buttonBorder`
/// for the button border shape in force, `ContainerRelativeShape` and
/// `ConcentricRectangle` for the container's — drawn as that one.
protocol EnvironmentResolvedShape {
    /// The shape to draw in `context`, for a view `columns` × `rows` cells.
    func resolvedShape(in context: RenderContext, columns: Int, rows: Int) -> any Shape
}

/// `shape` as it is drawn in `context`: the shape it stands for, where it stands
/// for another.
func resolvedShape(_ shape: any Shape, in context: RenderContext, columns: Int, rows: Int) -> any Shape {
    guard let resolving = shape as? any EnvironmentResolvedShape else { return shape }
    return resolving.resolvedShape(in: context, columns: columns, rows: rows)
}

// MARK: - Wrappers stand in for what they wrap

// A shape moved, turned, scaled, transformed, trimmed or resized stands for
// whatever the shape it wraps stands for, wrapped the same way — so
// `ContainerRelativeShape().offset(x: 1)` moves the container's shape, not a
// rectangle.

extension OffsetShape: EnvironmentResolvedShape where Content: EnvironmentResolvedShape {
    func resolvedShape(in context: RenderContext, columns: Int, rows: Int) -> any Shape {
        func wrap<S: Shape>(_ resolved: S) -> any Shape { OffsetShape<S>(shape: resolved, offset: offset) }
        return wrap(shape.resolvedShape(in: context, columns: columns, rows: rows))
    }
}

extension RotatedShape: EnvironmentResolvedShape where Content: EnvironmentResolvedShape {
    func resolvedShape(in context: RenderContext, columns: Int, rows: Int) -> any Shape {
        func wrap<S: Shape>(_ resolved: S) -> any Shape { RotatedShape<S>(shape: resolved, angle: angle, anchor: anchor) }
        return wrap(shape.resolvedShape(in: context, columns: columns, rows: rows))
    }
}

extension ScaledShape: EnvironmentResolvedShape where Content: EnvironmentResolvedShape {
    func resolvedShape(in context: RenderContext, columns: Int, rows: Int) -> any Shape {
        func wrap<S: Shape>(_ resolved: S) -> any Shape { ScaledShape<S>(shape: resolved, scale: scale, anchor: anchor) }
        return wrap(shape.resolvedShape(in: context, columns: columns, rows: rows))
    }
}

extension TransformedShape: EnvironmentResolvedShape where Content: EnvironmentResolvedShape {
    func resolvedShape(in context: RenderContext, columns: Int, rows: Int) -> any Shape {
        func wrap<S: Shape>(_ resolved: S) -> any Shape { TransformedShape<S>(shape: resolved, transform: transform) }
        return wrap(shape.resolvedShape(in: context, columns: columns, rows: rows))
    }
}

extension _TrimmedShape: EnvironmentResolvedShape where Content: EnvironmentResolvedShape {
    func resolvedShape(in context: RenderContext, columns: Int, rows: Int) -> any Shape {
        func wrap<S: Shape>(_ resolved: S) -> any Shape {
            _TrimmedShape<S>(shape: resolved, startFraction: startFraction, endFraction: endFraction)
        }
        return wrap(shape.resolvedShape(in: context, columns: columns, rows: rows))
    }
}

extension _SizedShape: EnvironmentResolvedShape where Content: EnvironmentResolvedShape {
    func resolvedShape(in context: RenderContext, columns: Int, rows: Int) -> any Shape {
        func wrap<S: Shape>(_ resolved: S) -> any Shape { _SizedShape<S>(shape: resolved, size: size, anchor: anchor) }
        return wrap(shape.resolvedShape(in: context, columns: columns, rows: rows))
    }
}

/// What `shape`, asked to draw `drawing` for a view `columns` × `rows` in
/// `context`, draws: the shape it stands for — and a stroke as a shape
/// (`stroke(lineWidth:)`) as the stroke it is, so a rectangle's is the box of
/// glyphs.
func resolvedDrawing(
    of shape: any Shape, as drawing: ShapeDrawing, in context: RenderContext, columns: Int, rows: Int
) -> (shape: any Shape, drawing: ShapeDrawing) {
    let drawn = resolvedShape(shape, in: context, columns: columns, rows: rows)
    guard let stroking = drawn as? any StrokingShape else { return (drawn, drawing) }
    return (
        resolvedShape(stroking.strokedShape.shape, in: context, columns: columns, rows: rows),
        .stroke(stroking.strokedShape.style, antialiased: drawing.isAntialiased)
    )
}

// MARK: - The core

/// A shape drawn: what the public shape views' bodies are made of.
///
/// Reads the frame it is offered, makes it a rectangle in square units — its
/// rows ``EnvironmentValues/imageCellAspect`` units tall — and draws the shape
/// in it by one of two tiers:
///
/// - **Box drawing** (``ShapeBoxCells``) for the rectangle family: always a
///   fill, and a stroke no wider than a column and undashed.
/// - **The rasterizer** (``ShapeHalfBlocks``) for everything else.
///
/// The paint is the style resolved in the environment, through the animator so
/// a colour changed inside `withAnimation` fades; a gradient is sampled per
/// cell for the box tier and per half cell for the rasterizer, over the view's
/// own box or the rectangle a `.gradientExtent(.subtree)` names. A shadowed
/// style's shadows are cast from the cells drawn.
struct _ShapeCore<Content: Shape, Style: ShapeStyle>: View, Renderable, Layoutable {
    let shape: Content
    let style: Style
    let drawing: ShapeDrawing

    var body: Never { fatalError("_ShapeCore renders via Renderable") }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        shape.sizeThatFits(proposal)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let columns = max(0, context.availableWidth)
        let rows = max(0, context.availableHeight)
        guard columns > 0, rows > 0 else { return FrameBuffer(lines: []) }
        let environment = context.environment
        let aspect = environment.imageCellAspect
        let paint = PaintAnimation.resolving(
            Self.paint(style, in: environment).materializingImages(in: context), owner: Self.self, context: context)
        let extent = context.gradientFrame ?? GradientFrame(width: columns, height: rows)
        let painter = ShapePainter(
            paint: paint.unshadowed, extent: extent, aspect: aspect, palette: environment.palette)
        let monochrome = ColorDepth.current == .noColor
        let drawn = resolvedDrawing(of: shape, as: drawing, in: context, columns: columns, rows: rows)
        let cells = ShapeCells.drawing(
            drawn.shape, as: drawn.drawing, frame: ShapeFrame(columns: columns, rows: rows, aspect: aspect),
            painter: painter, monochrome: monochrome, wholeCells: !environment.blockElementsFillTheLine)
        // A shadowed style's shadows, cast from the cells the shape drew — its
        // fill's, or its stroke's (``ShapeStyle/shadow(_:)``).
        return cells.buffer().castingShadows(of: paint, context: context, owner: Self.self)
    }

    /// The style's paint in `environment` — the palette's border for a
    /// separator drawn in the foreground style, as `Divider` is (`ShapeRole`).
    private static func paint(_ style: Style, in environment: EnvironmentValues) -> Paint {
        if Content.role == .separator, Style.self == ForegroundStyle.self {
            return .color(environment.palette.border)
        }
        return style.paint(in: environment)
    }
}

// MARK: - The two tiers

extension ShapeCells {
    /// `shape` drawn as `drawing` in `frame`, by whichever tier it qualifies
    /// for: the box-drawing one for the rectangle family, the rasterizer for
    /// everything else.
    static func drawing(
        _ shape: any Shape, as drawing: ShapeDrawing, frame: ShapeFrame, painter: ShapePainter, monochrome: Bool,
        wholeCells: Bool
    ) -> ShapeCells {
        let (rect, columns, rows, aspect) = (frame.rect, frame.columns, frame.rows, frame.aspect)
        if let box = shape as? any BoxDrawnShape, let radii = box.boxCorners(in: rect) {
            let corners = RoundedCorners(radii)
            switch drawing {
            case .fill:
                var cells = ShapeBoxCells.fill(
                    shape.path(in: rect), columns: columns, rows: rows, aspect: aspect, corners: corners,
                    wholeCells: wholeCells, colour: painter.cellColour)
                if monochrome { cells.dropColours() }
                return cells
            case .stroke(let style, _) where style.dash.isEmpty && style.lineWidth > 0 && style.lineWidth <= 1:
                var cells = ShapeBoxCells.stroke(columns: columns, rows: rows, corners: corners, colour: painter.cellColour)
                if monochrome { cells.dropColours() }
                return cells
            case .stroke:
                break
            }
        }
        return ShapeHalfBlocks.cells(
            shape.path(in: rect), drawing: drawing, columns: columns, rows: rows, aspect: aspect, monochrome: monochrome,
            colour: painter.pixelColour)
    }
}

// MARK: - The frame

/// The cells a shape is drawn in, and the rectangle in square units they are
/// to it: `columns` across, `rows × aspect` down.
struct ShapeFrame {
    let columns: Int
    let rows: Int
    let aspect: Double

    /// The frame in square units.
    var rect: CGRect { CGRect(x: 0, y: 0, width: CGFloat(columns), height: CGFloat(rows) * aspect) }
}

// MARK: - Paint per cell

/// A paint, resolved, asked for its colour at a cell or at a half cell.
///
/// A flat colour is resolved against the palette once. A gradient or a mesh is
/// sampled by ``RampSampler`` — the sampler a `.background` uses — over the
/// view's box at cell resolution for the box tier, and at half-cell resolution
/// for the rasterizer: twice the rows, each half as tall, so a radial ramp's
/// circle stays round.
struct ShapePainter {
    private let flat: Color?
    private let cells: RampSampler?
    private let pixels: RampSampler?
    private let palette: any Palette

    init(paint: Paint, extent: GradientFrame, aspect: Double, palette: any Palette) {
        self.palette = palette
        let depth = ColorDepth.current
        cells = RampSampler(paint: paint, extent: extent, depth: depth, cellAspect: aspect)
        let doubled = GradientFrame(
            originX: extent.originX, originY: extent.originY * 2, width: extent.width, height: extent.height * 2)
        pixels = RampSampler(paint: paint, extent: doubled, depth: depth, cellAspect: aspect / 2)
        flat = cells == nil ? paint.representative.resolve(with: palette) : nil
    }

    /// The paint at cell (`x`, `y`).
    func cellColour(_ x: Int, _ y: Int) -> Color {
        colour(cells, x, y)
    }

    /// The paint at half cell (`x`, `y`) — `y` counting half rows.
    func pixelColour(_ x: Int, _ y: Int) -> Color {
        colour(pixels, x, y)
    }

    private func colour(_ sampler: RampSampler?, _ x: Int, _ y: Int) -> Color {
        guard let sampler else { return flat ?? .default }
        // The entry first: a mesh's ramp grows as entries are named.
        let entry = sampler.entry(column: x, rowTerm: sampler.rowTerm(y))
        return sampler.ramp[entry].resolve(with: palette)
    }
}

extension ShapeCells {
    /// These cells for a terminal with no colour: a field becomes a full
    /// block, a glyph keeps its shape, and neither states a colour.
    mutating func dropColours() {
        for index in cells.indices where !cells[index].isEmpty {
            var cell = cells[index]
            if cell.field != nil, cell.glyph == " " { cell.glyph = "█" }
            cell.ink = nil
            cell.field = nil
            cells[index] = cell
        }
    }
}
