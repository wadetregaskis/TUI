//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Rectangle.swift
//
//  The rectangle: the frame itself.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// A rectangular shape aligned inside the frame of the view containing it —
/// mirrors SwiftUI's `Rectangle`.
///
/// Its edges are the frame's cells' edges, so it draws in the terminal's own
/// vocabulary: filled, it is the frame's cells painted — exactly what a
/// ``Color`` used as a view is, gradients and all; stroked, it is a box of line
/// glyphs, `┌─┐`.
nonisolated public struct Rectangle: Shape {
    /// How far this rectangle is inset inside its frame, by
    /// ``inset(by:)``.
    var insetAmount: CGFloat = 0

    /// Creates a new rectangle shape.
    public init() {}

    /// The frame, inset by however much it has been.
    public func path(in rect: CGRect) -> Path {
        Path(rect.insetForShape(by: insetAmount))
    }
}

extension Rectangle {
    /// A rectangle has nothing to animate.
    public typealias AnimatableData = EmptyAnimatableData
}

extension Rectangle: InsettableShape {
    /// The inset shape: this shape, inset — SwiftUI's is opaque, and this is
    /// what is behind it.
    public typealias InsetShape = Rectangle

    /// Returns `self` inset by `amount`.
    public func inset(by amount: CGFloat) -> Rectangle {
        var inset = self
        inset.insetAmount += amount
        return inset
    }
}

extension Rectangle: BoxDrawnShape {
    func boxCorners(in rect: CGRect) -> RectangleCornerRadii? {
        insetAmount == 0 ? RectangleCornerRadii() : nil
    }
}
