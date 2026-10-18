//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Shape+Modifiers.swift
//
//  A shape moved, turned, scaled, mapped, trimmed, resized or stroked — each
//  one more shape, its path arithmetic on the one it wraps.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

// MARK: - Transforms

extension Shape {
    /// Changes the relative position of this shape using the specified size.
    ///
    /// - Parameter offset: How far to move it, in the shape's unit.
    /// - Returns: The moved shape.
    public func offset(_ offset: CGSize) -> OffsetShape<Self> {
        OffsetShape(shape: self, offset: offset)
    }

    /// Changes the relative position of this shape using the specified point.
    ///
    /// - Parameter offset: How far to move it, in the shape's unit.
    /// - Returns: The moved shape.
    public func offset(_ offset: CGPoint) -> OffsetShape<Self> {
        OffsetShape(shape: self, offset: CGSize(width: offset.x, height: offset.y))
    }

    /// Changes the relative position of this shape using the specified
    /// distances.
    ///
    /// - Parameters:
    ///   - x: How far to move it across.
    ///   - y: How far to move it down.
    /// - Returns: The moved shape.
    public func offset(x: CGFloat = 0, y: CGFloat = 0) -> OffsetShape<Self> {
        OffsetShape(shape: self, offset: CGSize(width: x, height: y))
    }

    /// Rotates this shape around an anchor point at the angle you specify.
    ///
    /// - Parameters:
    ///   - angle: How far to turn it; positive is clockwise on screen.
    ///   - anchor: The point of the frame to turn it about.
    /// - Returns: The turned shape.
    public func rotation(_ angle: Angle, anchor: UnitPoint = .center) -> RotatedShape<Self> {
        RotatedShape(shape: self, angle: angle, anchor: anchor)
    }

    /// Scales this shape without changing its bounding frame.
    ///
    /// - Parameters:
    ///   - scale: The factor, across and down.
    ///   - anchor: The point of the frame to scale it about.
    /// - Returns: The scaled shape.
    public func scale(_ scale: CGFloat, anchor: UnitPoint = .center) -> ScaledShape<Self> {
        ScaledShape(shape: self, scale: CGSize(width: scale, height: scale), anchor: anchor)
    }

    /// Scales this shape without changing its bounding frame.
    ///
    /// - Parameters:
    ///   - x: The factor across.
    ///   - y: The factor down.
    ///   - anchor: The point of the frame to scale it about.
    /// - Returns: The scaled shape.
    public func scale(x: CGFloat = 1, y: CGFloat = 1, anchor: UnitPoint = .center) -> ScaledShape<Self> {
        ScaledShape(shape: self, scale: CGSize(width: x, height: y), anchor: anchor)
    }

    /// Applies an affine transform to this shape.
    ///
    /// - Parameter transform: The transform, over the shape's unit.
    /// - Returns: The mapped shape.
    public func transform(_ transform: CGAffineTransform) -> TransformedShape<Self> {
        TransformedShape(shape: self, transform: transform)
    }
}

// MARK: - Trimming and sizing

extension Shape {
    /// Trims this shape by a fractional amount based on its representation as
    /// a path — see ``Path/trimmedPath(from:to:)``.
    ///
    /// - Parameters:
    ///   - startFraction: Where drawing starts, `0…1` of the way through.
    ///   - endFraction: Where drawing ends.
    /// - Returns: The kept part, as a shape — animatable, so a progress ring
    ///   animates its `to:`.
    public func trim(from startFraction: CGFloat = 0, to endFraction: CGFloat = 1) -> some Shape {
        _TrimmedShape(shape: self, startFraction: startFraction, endFraction: endFraction)
    }

    /// This shape within a rectangle of `size` at the frame's origin, rather
    /// than the frame itself.
    ///
    /// - Parameter size: The size to constrain the shape to.
    /// - Returns: The constrained shape.
    public func size(_ size: CGSize) -> some Shape {
        _SizedShape(shape: self, size: size, anchor: nil)
    }

    /// This shape within a rectangle `width` by `height` at the frame's
    /// origin, rather than the frame itself.
    ///
    /// - Parameters:
    ///   - width: The rectangle's width.
    ///   - height: Its height.
    /// - Returns: The constrained shape.
    public func size(width: CGFloat, height: CGFloat) -> some Shape {
        _SizedShape(shape: self, size: CGSize(width: width, height: height), anchor: nil)
    }

    /// This shape within a rectangle of `size`, placed in the frame's size by
    /// `anchor`.
    ///
    /// Placed in the frame's SIZE, not at its origin — SwiftUI's arithmetic,
    /// measured: in a frame at (10, 10), `size(_:anchor:)` is centred as though
    /// the frame were at (0, 0), where the form with no anchor keeps the
    /// frame's origin.
    ///
    /// - Parameters:
    ///   - size: The size to constrain the shape to.
    ///   - anchor: Where in the frame to put it.
    /// - Returns: The constrained shape.
    public func size(_ size: CGSize, anchor: UnitPoint) -> some Shape {
        _SizedShape(shape: self, size: size, anchor: anchor)
    }

    /// This shape within a rectangle `width` by `height`, placed in the
    /// frame's size by `anchor` — see ``size(_:anchor:)``.
    ///
    /// - Parameters:
    ///   - width: The rectangle's width.
    ///   - height: Its height.
    ///   - anchor: Where in the frame to put it.
    /// - Returns: The constrained shape.
    public func size(width: CGFloat, height: CGFloat, anchor: UnitPoint) -> some Shape {
        _SizedShape(shape: self, size: CGSize(width: width, height: height), anchor: anchor)
    }
}

// MARK: - The shapes those make

/// ``Shape/trim(from:to:)``'s shape.
nonisolated struct _TrimmedShape<Content: Shape>: Shape {
    var shape: Content
    var startFraction: CGFloat
    var endFraction: CGFloat

    func path(in rect: CGRect) -> Path {
        shape.path(in: rect).trimmedPath(from: startFraction, to: endFraction)
    }

    static var role: ShapeRole { Content.role }

    @MainActor var animatableData: AnimatablePair<Content.AnimatableData, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(shape.animatableData, AnimatablePair(startFraction, endFraction)) }
        set {
            shape.animatableData = newValue.first
            startFraction = newValue.second.first
            endFraction = newValue.second.second
        }
    }
}

/// ``Shape/size(_:)`` and ``Shape/size(_:anchor:)``'s shape.
nonisolated struct _SizedShape<Content: Shape>: Shape {
    var shape: Content
    var size: CGSize
    /// Where in the frame's size; `nil` keeps the frame's origin.
    var anchor: UnitPoint?

    func path(in rect: CGRect) -> Path {
        guard let anchor else { return shape.path(in: CGRect(origin: rect.origin, size: size)) }
        let origin = CGPoint(x: (rect.width - size.width) * anchor.x, y: (rect.height - size.height) * anchor.y)
        return shape.path(in: CGRect(origin: origin, size: size))
    }

    static var role: ShapeRole { Content.role }

    @MainActor var animatableData: AnimatablePair<Content.AnimatableData, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(shape.animatableData, AnimatablePair(size.width, size.height)) }
        set {
            shape.animatableData = newValue.first
            size = CGSize(width: newValue.second.first, height: newValue.second.second)
        }
    }
}

/// ``Shape/stroke(lineWidth:)`` and ``Shape/stroke(style:)``'s shape: the
/// region the stroke covers, as a shape.
///
/// Drawn, it is the stroke itself — ``_ShapeCore`` draws the shape it wraps
/// stroked, so a rectangle's is the box of line glyphs a ``Shape/stroke(_:lineWidth:antialiased:)``
/// draws. Its path, where one is asked for, is the union of the stroke's
/// pieces, filled by the non-zero rule (``ShapeStroker``): what the stroke
/// covers, not an outline of it.
nonisolated struct _StrokedShape<Content: Shape>: Shape {
    var shape: Content
    var style: StrokeStyle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for piece in ShapeStroker.polygons(of: shape.path(in: rect).contours(tolerance: 0.01), style: style) {
            path.addLines(piece)
            path.closeSubpath()
        }
        return path
    }

    static var role: ShapeRole { .stroke }

    @MainActor var animatableData: AnimatablePair<Content.AnimatableData, StrokeStyle.AnimatableData> {
        get { AnimatablePair(shape.animatableData, style.animatableData) }
        set {
            shape.animatableData = newValue.first
            style.animatableData = newValue.second
        }
    }
}

/// A shape drawn by ``_ShapeCore`` as a stroke of another, whatever it is
/// asked to draw — ``_StrokedShape``, the stroke as a shape.
protocol StrokingShape {
    /// The shape it strokes, erased, and the stroke.
    var strokedShape: (shape: any Shape, style: StrokeStyle) { get }
}

extension _StrokedShape: StrokingShape {
    var strokedShape: (shape: any Shape, style: StrokeStyle) { (shape, style) }
}

/// ``StrokeBorderShapeView``'s shape: the shape it borders, inset by half the
/// line — so the line lies inside the frame — and, for the box-drawing tier,
/// still the shape it was: a box of glyphs drawn in the frame's outermost cells
/// is already inside.
nonisolated struct _StrokeBorderInset<Content: InsettableShape>: Shape {
    var shape: Content
    var amount: CGFloat

    func path(in rect: CGRect) -> Path {
        shape.inset(by: amount).path(in: rect)
    }

    static var role: ShapeRole { Content.role }
}

extension _StrokeBorderInset: EnvironmentResolvedShape where Content: EnvironmentResolvedShape {
    /// The border of the shape the bordered one stands for, inset as this one
    /// is — so `ContainerRelativeShape().strokeBorder(…)` borders the container's
    /// shape.
    func resolvedShape(in context: RenderContext, columns: Int, rows: Int) -> any Shape {
        func bordering<S: InsettableShape>(_ resolved: S) -> any Shape {
            _StrokeBorderInset<S>(shape: resolved, amount: amount)
        }
        guard let resolved = shape.resolvedShape(in: context, columns: columns, rows: rows) as? any InsettableShape
        else { return self }
        return bordering(resolved)
    }
}

extension _StrokeBorderInset: BoxDrawnShape {
    func boxCorners(in rect: CGRect) -> RectangleCornerRadii? {
        (shape as? any BoxDrawnShape)?.boxCorners(in: rect)
    }
}
