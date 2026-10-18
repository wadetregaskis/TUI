//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FillShapeView.swift
//
//  A shape filled with a style, over another drawing of it.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// A shape provider that fills its shape — mirrors SwiftUI's `FillShapeView`.
///
/// What ``ShapeView/fill(_:style:)`` returns: the shape filled, drawn over
/// `background` — the drawing it was chained from.
nonisolated public struct FillShapeView<Content: Shape, Style: ShapeStyle, Background: View>: ShapeView {
    /// The shape that this type draws and provides for other drawing
    /// operations.
    public var shape: Content

    /// The style that fills this view's shape.
    public var style: Style

    /// The fill style used when filling this view's shape.
    public var fillStyle: FillStyle

    /// The background shown beneath this view.
    public var background: Background

    /// Create a FillShapeView.
    ///
    /// - Parameters:
    ///   - shape: The shape.
    ///   - style: The style that fills it.
    ///   - fillStyle: The fill rule and antialiasing.
    ///   - background: The drawing beneath.
    public init(shape: Content, style: Style, fillStyle: FillStyle, background: Background) {
        self.shape = shape
        self.style = style
        self.fillStyle = fillStyle
        self.background = background
    }

    /// The fill, over the background.
    @MainActor public var body: some View {
        ZStack {
            background
            _ShapeFill(shape: shape, style: style, fillStyle: fillStyle)
        }
    }
}

extension FillShapeView: Animatable {
    /// The shape's own animatable data.
    @MainActor public var animatableData: Content.AnimatableData {
        get { shape.animatableData }
        set { shape.animatableData = newValue }
    }
}
