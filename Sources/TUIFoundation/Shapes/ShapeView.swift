//  🖥️ TUI — A Terminal UI framework for Swift
//  ShapeView.swift
//
//  A view that draws a shape, and the chaining that layers one drawing of a
//  shape over another.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

// MARK: - ShapeView

/// A view that provides a shape that you can use for drawing operations —
/// mirrors SwiftUI's `ShapeView`.
///
/// Each drawing of a shape is one of these, and each can be drawn again, the
/// earlier drawing beneath:
///
/// ```swift
/// Circle()
///     .fill(.yellow)
///     .stroke(.orange, lineWidth: 1)
/// ```
public protocol ShapeView<Content>: View {
    /// The type of shape this can provide.
    associatedtype Content: Shape

    /// The shape that this type draws and provides for other drawing
    /// operations.
    var shape: Content { get }
}

extension ShapeView {
    /// Fills the shape with a style, over this drawing.
    ///
    /// - Parameters:
    ///   - content: The style to fill with — the foreground style unless
    ///     given.
    ///   - style: The fill rule and antialiasing.
    /// - Returns: The shape filled, over this.
    public func fill<S: ShapeStyle>(
        _ content: S = .foreground, style: FillStyle = FillStyle()
    ) -> FillShapeView<Content, S, Self> {
        FillShapeView(shape: shape, style: content, fillStyle: style, background: self)
    }

    /// Traces the outline of the shape with a style, over this drawing.
    ///
    /// - Parameters:
    ///   - content: The style to trace with.
    ///   - lineWidth: The line's width, in columns.
    ///   - antialiased: Whether the rasterized line's edges blend.
    /// - Returns: The shape stroked, over this.
    public func stroke<S: ShapeStyle>(
        _ content: S, lineWidth: CGFloat = 1, antialiased: Bool = true
    ) -> StrokeShapeView<Content, S, Self> {
        StrokeShapeView(
            shape: shape, style: content, strokeStyle: StrokeStyle(lineWidth: lineWidth), isAntialiased: antialiased,
            background: self)
    }

    /// Traces the outline of the shape in `style`'s width, caps, joins and
    /// dashes, over this drawing.
    ///
    /// - Parameters:
    ///   - content: The style to trace with.
    ///   - style: The stroke's characteristics.
    ///   - antialiased: Whether the rasterized line's edges blend.
    /// - Returns: The shape stroked, over this.
    public func stroke<S: ShapeStyle>(
        _ content: S, style: StrokeStyle, antialiased: Bool = true
    ) -> StrokeShapeView<Content, S, Self> {
        StrokeShapeView(shape: shape, style: content, strokeStyle: style, isAntialiased: antialiased, background: self)
    }
}

extension ShapeView where Content: InsettableShape {
    /// Traces the outline of the shape inside its frame, over this drawing.
    ///
    /// - Parameters:
    ///   - content: The style to trace with — the foreground style unless
    ///     given.
    ///   - lineWidth: The line's width, in columns.
    ///   - antialiased: Whether the rasterized line's edges blend.
    /// - Returns: The shape's border, over this.
    public func strokeBorder<S: ShapeStyle>(
        _ content: S = .foreground, lineWidth: CGFloat = 1, antialiased: Bool = true
    ) -> StrokeBorderShapeView<Content, S, Self> {
        StrokeBorderShapeView(
            shape: shape, style: content, strokeStyle: StrokeStyle(lineWidth: lineWidth), isAntialiased: antialiased,
            background: self)
    }

    /// Traces the outline of the shape inside its frame in `style`'s width,
    /// caps, joins and dashes, over this drawing.
    ///
    /// - Parameters:
    ///   - content: The style to trace with — the foreground style unless
    ///     given.
    ///   - style: The stroke's characteristics.
    ///   - antialiased: Whether the rasterized line's edges blend.
    /// - Returns: The shape's border, over this.
    public func strokeBorder<S: ShapeStyle>(
        _ content: S = .foreground, style: StrokeStyle, antialiased: Bool = true
    ) -> StrokeBorderShapeView<Content, S, Self> {
        StrokeBorderShapeView(shape: shape, style: content, strokeStyle: style, isAntialiased: antialiased, background: self)
    }
}

// MARK: - The default drawing

/// A shape filled with a style — what ``Shape/fill(_:style:)`` returns, and
/// what a shape used as a view is, with the foreground style. Mirrors
/// SwiftUI's `_ShapeView`.
nonisolated public struct _ShapeView<Content: Shape, Style: ShapeStyle>: View {
    /// The shape.
    public var shape: Content
    /// The style it is filled with.
    public var style: Style
    /// The fill rule and antialiasing.
    public var fillStyle: FillStyle

    /// A shape filled with a style.
    ///
    /// - Parameters:
    ///   - shape: The shape.
    ///   - style: The style to fill it with.
    ///   - fillStyle: The fill rule and antialiasing.
    public init(shape: Content, style: Style, fillStyle: FillStyle = FillStyle()) {
        self.shape = shape
        self.style = style
        self.fillStyle = fillStyle
    }

    /// The shape, filled.
    @MainActor public var body: some View {
        _ShapeFill(shape: shape, style: style, fillStyle: fillStyle)
    }
}

extension _ShapeView: ShapeView {}

extension _ShapeView: Animatable {
    /// The shape's own animatable data, so a corner radius or a trim changed
    /// inside `withAnimation` moves.
    @MainActor public var animatableData: Content.AnimatableData {
        get { shape.animatableData }
        set { shape.animatableData = newValue }
    }
}

// MARK: - Fill, the one decision

/// A shape filled with a style: a ``Rectangle`` exactly as a ``Color`` used as
/// a view is drawn — the same `.background` over the same blank block, so
/// `Rectangle().fill(.red)` and `Color.red` are one picture, gradient pictures
/// included — and every other shape by ``_ShapeCore``.
struct _ShapeFill<Content: Shape, Style: ShapeStyle>: View {
    let shape: Content
    let style: Style
    let fillStyle: FillStyle

    @ViewBuilder var body: some View {
        if Content.self == Rectangle.self, (shape as? Rectangle)?.insetAmount == 0 {
            _StyleFillBlock().background(style)
        } else {
            _ShapeCore(shape: shape, style: style, drawing: .fill(fillStyle))
        }
    }
}
