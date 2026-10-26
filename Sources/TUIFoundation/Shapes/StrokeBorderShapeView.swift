//  🖥️ TUI — A Terminal UI framework for Swift
//  StrokeBorderShapeView.swift
//
//  A shape stroked inside its frame, over another drawing of it.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// A shape provider that strokes the border of its shape — mirrors SwiftUI's
/// `StrokeBorderShapeView`.
///
/// What ``InsettableShape/strokeBorder(_:lineWidth:antialiased:)`` and
/// ``ShapeView/strokeBorder(_:lineWidth:antialiased:)`` return: the outline of
/// the shape inset by half the line's width, traced, so the whole line lies
/// inside the frame — drawn over `background`. Round a shape of the rectangle
/// family a line one column wide or less, undashed, is the same box of line
/// glyphs a stroke is: a box drawn in the frame's outermost cells is already
/// inside it.
nonisolated public struct StrokeBorderShapeView<Content: InsettableShape, Style: ShapeStyle, Background: View>: ShapeView {
    /// The shape that this type draws and provides for other drawing
    /// operations.
    public var shape: Content

    /// The style that strokes the border of this view's shape.
    public var style: Style

    /// The stroke style used when stroking this view's shape.
    public var strokeStyle: StrokeStyle

    /// Whether this shape should be drawn antialiased.
    public var isAntialiased: Bool

    /// The background shown beneath this view.
    public var background: Background

    /// Create a StrokeBorderShapeView.
    ///
    /// - Parameters:
    ///   - shape: The shape.
    ///   - style: The style that strokes it.
    ///   - strokeStyle: The stroke's width, caps, joins and dashes.
    ///   - isAntialiased: Whether the rasterized line's edges blend.
    ///   - background: The drawing beneath.
    public init(shape: Content, style: Style, strokeStyle: StrokeStyle, isAntialiased: Bool, background: Background) {
        self.shape = shape
        self.style = style
        self.strokeStyle = strokeStyle
        self.isAntialiased = isAntialiased
        self.background = background
    }

    /// The border, over the background.
    @MainActor public var body: some View {
        ZStack {
            background
            _ShapeCore(
                shape: _StrokeBorderInset(shape: shape, amount: strokeStyle.lineWidth / 2), style: style,
                drawing: .stroke(strokeStyle, antialiased: isAntialiased))
        }
    }
}

extension StrokeBorderShapeView: Animatable {
    /// The shape's own animatable data.
    @MainActor public var animatableData: Content.AnimatableData {
        get { shape.animatableData }
        set { shape.animatableData = newValue }
    }
}
