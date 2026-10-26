//  🖥️ TUI — A Terminal UI framework for Swift
//  ScaledShape.swift
//
//  A shape scaled about a point of its frame.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// A shape with a scale transform applied to it — mirrors SwiftUI's
/// `ScaledShape`.
///
/// Scaling a path is arithmetic before it is drawn, so any factor draws;
/// what is scaled past the frame is not drawn.
nonisolated public struct ScaledShape<Content: Shape>: Shape {
    /// The shape.
    public var shape: Content

    /// The factor across and down.
    public var scale: CGSize

    /// The point of the frame it is scaled about, in unit coordinates.
    public var anchor: UnitPoint

    /// A shape scaled by `scale` about `anchor`.
    ///
    /// - Parameters:
    ///   - shape: The shape.
    ///   - scale: The factor across and down.
    ///   - anchor: The point of the frame to scale it about.
    public init(shape: Content, scale: CGSize, anchor: UnitPoint = .center) {
        self.shape = shape
        self.scale = scale
        self.anchor = anchor
    }

    /// The shape's path, scaled.
    public func path(in rect: CGRect) -> Path {
        let pivot = CGPoint(x: rect.minX + rect.width * anchor.x, y: rect.minY + rect.height * anchor.y)
        let transform = CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
            .concatenating(CGAffineTransform(scaleX: scale.width, y: scale.height))
            .concatenating(CGAffineTransform(translationX: pivot.x, y: pivot.y))
        return shape.path(in: rect).applying(transform)
    }

    /// The shape's own role.
    public static var role: ShapeRole { Content.role }
}

extension ScaledShape {
    /// The shape's own data, then the scale and the anchor.
    public typealias AnimatableData = AnimatablePair<
        Content.AnimatableData, AnimatablePair<AnimatablePair<CGFloat, CGFloat>, UnitPoint.AnimatableData>
    >

    /// The shape, its scale and its anchor, animated together.
    @MainActor public var animatableData: AnimatableData {
        get {
            AnimatablePair(
                shape.animatableData, AnimatablePair(AnimatablePair(scale.width, scale.height), anchor.animatableData))
        }
        set {
            shape.animatableData = newValue.first
            scale = CGSize(width: newValue.second.first.first, height: newValue.second.first.second)
            anchor.animatableData = newValue.second.second
        }
    }
}
