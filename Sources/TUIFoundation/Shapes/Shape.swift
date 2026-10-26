//  🖥️ TUI — A Terminal UI framework for Swift
//  Shape.swift
//
//  A 2D shape you can draw: SwiftUI's `Shape`, its path in square units.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

// MARK: - Shape

/// A 2D shape that you can use when drawing a view — mirrors SwiftUI's
/// `Shape`.
///
/// A shape is ``path(in:)``: its outline in the rectangle it is given. Used as
/// a view it fills the space it is offered, as a ``Color`` does, and without an
/// explicit ``fill(_:style:)`` or ``stroke(_:lineWidth:antialiased:)`` it is
/// filled with the foreground style.
///
/// ```swift
/// struct Triangle: Shape {
///     func path(in rect: CGRect) -> Path {
///         Path { path in
///             path.move(to: CGPoint(x: rect.midX, y: rect.minY))
///             path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
///             path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
///             path.closeSubpath()
///         }
///     }
/// }
///
/// Triangle().fill(.orange).frame(width: 12, height: 6)
/// ```
///
/// ## The unit of a shape
///
/// The rectangle is in **square units**: one column across, and a row down is
/// ``EnvironmentValues/imageCellAspect`` units — about two, a cell's height over
/// its width (refusal review O0, ruled 2026-10-12). So a 12 × 6-cell frame is a
/// 12 × 12 rectangle, and a shape computed from `rect.midX` and
/// `rect.width * k`, as most are, comes out the proportions it was drawn for:
/// a circle is round. Literal lengths — a line width, a corner radius, a dash —
/// are in columns, the same deliberate choice `.padding(2)` is. Where the
/// terminal does not report its cell size the aspect is 2.
///
/// ## How a shape is drawn
///
/// Two ways, chosen per shape and per drawing:
///
/// - **The rectangle family** — ``Rectangle``, ``RoundedRectangle``,
///   ``UnevenRoundedRectangle``, ``Capsule``, ``ContainerRelativeShape`` —
///   whose edges land on cell boundaries, draws in the terminal's own
///   vocabulary: a stroke is a box of line glyphs, `┌` where a corner's radius
///   is zero and `╭` where it is not; a fill is cells of the paint, its rounded
///   corners cut in quadrants, one row ending in the caps `▐ ▌`. A wide or
///   dashed stroke is drawn by the rasterizer instead.
/// - **Everything else** — ``Circle``, ``Ellipse``, a ``Path``, a shape of your
///   own, a transformed or trimmed shape — is rasterized: each cell's two halves
///   are drawn at the share of them the shape covers, as alpha, which the
///   compositor blends into whatever is behind. That is antialiasing; a
///   ``FillStyle`` that turns it off draws a half where at least half is
///   covered.
///
/// A shape draws within its frame: a stroke centred on the frame's edge loses
/// its outer half, where SwiftUI draws it past the frame. Use
/// ``InsettableShape/strokeBorder(_:lineWidth:antialiased:)`` for the whole of
/// the line.
nonisolated public protocol Shape: Sendable, Animatable, View {
    /// Describes this shape as a path within a rectangular frame of
    /// reference.
    ///
    /// - Parameter rect: The frame of reference, in square units — see the
    ///   protocol's discussion.
    /// - Returns: A path that describes this shape.
    func path(in rect: CGRect) -> Path

    /// An indication of how to style a shape. ``ShapeRole/fill`` unless a
    /// shape says otherwise.
    static var role: ShapeRole { get }

    /// The size of the view that will render the shape, given a proposed
    /// size.
    ///
    /// In TUI's layout terms, as a custom `Layout`'s `sizeThatFits` is:
    /// cells, and whether each axis fills what it is offered. The default fills
    /// both, from nothing, as ``Color`` does — SwiftUI's own default, the
    /// proposal itself.
    ///
    /// - Parameter proposal: The space offered, in cells.
    /// - Returns: The size the shape needs, and whether it fills more.
    func sizeThatFits(_ proposal: ProposedSize) -> ViewSize
}

// MARK: - ShapeRole

/// Ways of styling a shape — mirrors SwiftUI's `ShapeRole`.
public enum ShapeRole: Hashable, Sendable {
    /// Indicates to the shape's style that the shape is filled.
    case fill
    /// Indicates to the shape's style that the shape is stroked.
    case stroke
    /// Indicates to the shape's style that the shape is a separator.
    case separator
}

// MARK: - Defaults

extension Shape {
    /// A shape is a fill unless it says otherwise.
    public static var role: ShapeRole { .fill }

    /// Fills whatever it is offered, from nothing, as a ``Color`` does.
    public func sizeThatFits(_ proposal: ProposedSize) -> ViewSize {
        ViewSize(width: 0, height: 0, isWidthFlexible: true, isHeightFlexible: true)
    }

    /// A shape as a view is the shape filled with the foreground style.
    @MainActor public var body: _ShapeView<Self, ForegroundStyle> {
        _ShapeView(shape: self, style: ForegroundStyle())
    }
}

// MARK: - Filling and stroking

extension Shape {
    /// Fills this shape with a style.
    ///
    /// - Parameters:
    ///   - content: The style to fill with — the foreground style unless
    ///     given.
    ///   - style: The fill rule and antialiasing.
    /// - Returns: The shape, filled.
    public func fill<S: ShapeStyle>(_ content: S = .foreground, style: FillStyle = FillStyle()) -> _ShapeView<Self, S> {
        _ShapeView(shape: self, style: content, fillStyle: style)
    }

    /// Traces the outline of this shape with a style.
    ///
    /// A line one column wide or less, undashed, round a shape of the
    /// rectangle family is a box of line glyphs; any other is rasterized.
    ///
    /// - Parameters:
    ///   - content: The style to trace with.
    ///   - lineWidth: The line's width, in columns.
    ///   - antialiased: Whether the rasterized line's edges blend.
    /// - Returns: The shape, stroked.
    public func stroke<S: ShapeStyle>(
        _ content: S, lineWidth: CGFloat = 1, antialiased: Bool = true
    ) -> StrokeShapeView<Self, S, EmptyView> {
        StrokeShapeView(
            shape: self, style: content, strokeStyle: StrokeStyle(lineWidth: lineWidth), isAntialiased: antialiased,
            background: EmptyView())
    }

    /// Traces the outline of this shape with a style, in `style`'s width,
    /// caps, joins and dashes.
    ///
    /// - Parameters:
    ///   - content: The style to trace with.
    ///   - style: The stroke's characteristics.
    ///   - antialiased: Whether the rasterized line's edges blend.
    /// - Returns: The shape, stroked.
    public func stroke<S: ShapeStyle>(
        _ content: S, style: StrokeStyle, antialiased: Bool = true
    ) -> StrokeShapeView<Self, S, EmptyView> {
        StrokeShapeView(shape: self, style: content, strokeStyle: style, isAntialiased: antialiased, background: EmptyView())
    }

    /// The outline of this shape stroked `lineWidth` wide, as a shape — which
    /// is then filled, with the foreground style unless told otherwise.
    ///
    /// - Parameter lineWidth: The line's width, in columns.
    /// - Returns: The stroke, as a shape.
    public func stroke(lineWidth: CGFloat = 1) -> some Shape {
        _StrokedShape(shape: self, style: StrokeStyle(lineWidth: lineWidth))
    }

    /// The outline of this shape stroked in `style`, as a shape.
    ///
    /// - Parameter style: The stroke's characteristics.
    /// - Returns: The stroke, as a shape.
    public func stroke(style: StrokeStyle) -> some Shape {
        _StrokedShape(shape: self, style: style)
    }
}

// MARK: - Path is a shape

extension Path: Shape {
    /// A path is the shape it describes, wherever it is drawn: the rectangle
    /// is not consulted.
    public func path(in _: CGRect) -> Path { self }
}

extension Path: Animatable {
    /// A path has nothing to animate.
    public typealias AnimatableData = EmptyAnimatableData
}
