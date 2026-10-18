//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RotatedShape.swift
//
//  A shape turned about a point of its frame.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// A shape with a rotation transform applied to it — mirrors SwiftUI's
/// `RotatedShape`.
///
/// A path is coordinates, so turning one is arithmetic before it is drawn: the
/// rotated shape is rasterized like any other, at any angle. Positive angles
/// turn clockwise on screen.
nonisolated public struct RotatedShape<Content: Shape>: Shape {
    /// The shape.
    public var shape: Content

    /// How far it is turned.
    public var angle: Angle

    /// The point of the frame it is turned about, in unit coordinates.
    public var anchor: UnitPoint

    /// A shape turned by `angle` about `anchor`.
    ///
    /// - Parameters:
    ///   - shape: The shape.
    ///   - angle: How far to turn it.
    ///   - anchor: The point of the frame to turn it about.
    public init(shape: Content, angle: Angle, anchor: UnitPoint = .center) {
        self.shape = shape
        self.angle = angle
        self.anchor = anchor
    }

    /// The shape's path, turned.
    public func path(in rect: CGRect) -> Path {
        let pivot = CGPoint(x: rect.minX + rect.width * anchor.x, y: rect.minY + rect.height * anchor.y)
        let transform = CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
            .concatenating(CGAffineTransform(rotationAngle: angle.radians))
            .concatenating(CGAffineTransform(translationX: pivot.x, y: pivot.y))
        return shape.path(in: rect).applying(transform)
    }

    /// The shape's own role.
    public static var role: ShapeRole { Content.role }
}

extension RotatedShape {
    /// The shape's own data, then the angle and the anchor.
    public typealias AnimatableData = AnimatablePair<
        Content.AnimatableData, AnimatablePair<Angle.AnimatableData, UnitPoint.AnimatableData>
    >

    /// The shape, its angle and its anchor, animated together.
    @MainActor public var animatableData: AnimatableData {
        get { AnimatablePair(shape.animatableData, AnimatablePair(angle.animatableData, anchor.animatableData)) }
        set {
            shape.animatableData = newValue.first
            angle.animatableData = newValue.second.first
            anchor.animatableData = newValue.second.second
        }
    }
}

extension RotatedShape: InsettableShape where Content: InsettableShape {
    /// The shape inset, then turned as this one is.
    public typealias InsetShape = RotatedShape<Content.InsetShape>

    /// The shape inset by `amount`, turned as this one is.
    public func inset(by amount: CGFloat) -> RotatedShape<Content.InsetShape> {
        RotatedShape<Content.InsetShape>(shape: shape.inset(by: amount), angle: angle, anchor: anchor)
    }
}
