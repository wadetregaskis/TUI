//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Ellipse.swift
//
//  An ellipse filling its frame.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// An ellipse aligned inside the frame of the view containing it — mirrors
/// SwiftUI's `Ellipse`.
///
/// Drawn by the rasterizer, its rim blended into what is behind.
nonisolated public struct Ellipse: Shape {
    /// How far this ellipse is inset inside its frame, by ``inset(by:)``.
    var insetAmount: CGFloat = 0

    /// Creates a new ellipse shape.
    public init() {}

    /// The ellipse filling the frame, inset by however much it has been.
    public func path(in rect: CGRect) -> Path {
        Path(ellipseIn: rect.insetForShape(by: insetAmount))
    }
}

extension Ellipse {
    /// A ellipse has nothing to animate.
    public typealias AnimatableData = EmptyAnimatableData
}

extension Ellipse: InsettableShape {
    /// The inset shape: this shape, inset — SwiftUI's is opaque, and this is
    /// what is behind it.
    public typealias InsetShape = Ellipse

    /// Returns `self` inset by `amount`.
    public func inset(by amount: CGFloat) -> Ellipse {
        var inset = self
        inset.insetAmount += amount
        return inset
    }
}
