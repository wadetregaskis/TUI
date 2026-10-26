//  🖥️ TUI — A Terminal UI framework for Swift
//  Circle.swift
//
//  A circle centred in its frame.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// A circle centered on the frame of the view containing it — mirrors
/// SwiftUI's `Circle`.
///
/// Its diameter is the frame's shorter side in square units, so in a frame
/// twice as wide as it is tall — 10 × 5 cells at the usual aspect — it fills
/// the frame and is round on screen. It is drawn by the rasterizer, its rim
/// blended into what is behind.
nonisolated public struct Circle: Shape {
    /// How far this circle is inset inside its frame, by ``inset(by:)``.
    var insetAmount: CGFloat = 0

    /// Creates a new circle shape.
    public init() {}

    /// Fills whatever it is offered, from nothing — SwiftUI's circle answers
    /// the proposal itself, with an unstated side small.
    public func sizeThatFits(_ proposal: ProposedSize) -> ViewSize {
        ViewSize(width: 0, height: 0, isWidthFlexible: true, isHeightFlexible: true)
    }

    /// The circle centred in the frame, inset by however much it has been.
    public func path(in rect: CGRect) -> Path {
        let frame = rect.insetForShape(by: insetAmount)
        let diameter = min(frame.width, frame.height)
        return Path(
            ellipseIn: CGRect(
                x: frame.midX - diameter / 2, y: frame.midY - diameter / 2, width: diameter, height: diameter))
    }
}

extension Circle {
    /// A circle has nothing to animate.
    public typealias AnimatableData = EmptyAnimatableData
}

extension Circle: InsettableShape {
    /// The inset shape: this shape, inset — SwiftUI's is opaque, and this is
    /// what is behind it.
    public typealias InsetShape = Circle

    /// Returns `self` inset by `amount`.
    public func inset(by amount: CGFloat) -> Circle {
        var inset = self
        inset.insetAmount += amount
        return inset
    }
}
