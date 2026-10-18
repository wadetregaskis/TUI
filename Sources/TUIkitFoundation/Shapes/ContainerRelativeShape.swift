//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContainerRelativeShape.swift
//
//  The shape of the container a view is in.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// A shape that is replaced by an inset version of the current container
/// shape; if no container shape was defined, it is a rectangle — mirrors
/// SwiftUI's `ContainerRelativeShape`.
///
/// Drawn as lines its corners are the container's: `╭` where the container's
/// are rounded, `┌` where they are not.
nonisolated public struct ContainerRelativeShape: Shape {
    /// How far this shape is inset inside its frame, by ``inset(by:)``.
    var insetAmount: CGFloat = 0

    /// Creates a new container relative shape.
    public init() {}

    /// With no container shape to stand for, the frame: a rectangle.
    public func path(in rect: CGRect) -> Path {
        Path(rect.insetForShape(by: insetAmount))
    }
}

extension ContainerRelativeShape {
    /// A container shape has nothing to animate.
    public typealias AnimatableData = EmptyAnimatableData
}

extension ContainerRelativeShape: InsettableShape {
    /// The inset shape: this shape, inset — SwiftUI's is opaque, and this is
    /// what is behind it.
    public typealias InsetShape = ContainerRelativeShape

    /// Returns `self` inset by `amount`.
    public func inset(by amount: CGFloat) -> ContainerRelativeShape {
        var inset = self
        inset.insetAmount += amount
        return inset
    }
}

extension ContainerRelativeShape: BoxDrawnShape {
    func boxCorners(in rect: CGRect) -> RectangleCornerRadii? {
        insetAmount == 0 ? RectangleCornerRadii() : nil
    }
}
