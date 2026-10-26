//  🖥️ TUI — A Terminal UI framework for Swift
//  StrokeShapeView.swift
//
//  A shape stroked with a style, over another drawing of it.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// A shape provider that strokes its shape — mirrors SwiftUI's
/// `StrokeShapeView`.
///
/// What ``Shape/stroke(_:lineWidth:antialiased:)`` and
/// ``ShapeView/stroke(_:lineWidth:antialiased:)`` return: the outline traced,
/// centred on the shape's edge, drawn over `background`. A line one column wide
/// or less, undashed, round a shape of the rectangle family is a box of line
/// glyphs; any other is rasterized, and its outer half past the frame is not
/// drawn.
nonisolated public struct StrokeShapeView<Content: Shape, Style: ShapeStyle, Background: View>: ShapeView {
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

    /// Create a StrokeShapeView.
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

    /// The stroke, over the background.
    @MainActor public var body: some View {
        ZStack {
            background
            _ShapeCore(shape: shape, style: style, drawing: .stroke(strokeStyle, antialiased: isAntialiased))
        }
    }
}

extension StrokeShapeView: Animatable {
    /// The shape's own animatable data.
    @MainActor public var animatableData: Content.AnimatableData {
        get { shape.animatableData }
        set { shape.animatableData = newValue }
    }
}
