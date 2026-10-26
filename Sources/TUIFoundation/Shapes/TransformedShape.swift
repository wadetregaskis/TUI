//  🖥️ TUI — A Terminal UI framework for Swift
//  TransformedShape.swift
//
//  A shape mapped through an affine transform.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// A shape with an affine transform applied to it — mirrors SwiftUI's
/// `TransformedShape`.
///
/// The transform maps the path's coordinates — the shape's square units —
/// before it is drawn, so a shear or a rotation draws as exactly as a
/// translation does.
nonisolated public struct TransformedShape<Content: Shape>: Shape {
    /// The shape.
    public var shape: Content

    /// The transform applied to it.
    public var transform: CGAffineTransform

    /// A shape mapped through `transform`.
    ///
    /// - Parameters:
    ///   - shape: The shape.
    ///   - transform: The transform to apply to its path.
    public init(shape: Content, transform: CGAffineTransform) {
        self.shape = shape
        self.transform = transform
    }

    /// The shape's path, mapped.
    public func path(in rect: CGRect) -> Path {
        shape.path(in: rect).applying(transform)
    }

    /// The shape's own role.
    public static var role: ShapeRole { Content.role }
}

extension TransformedShape {
    /// The shape's own data; the transform does not animate.
    public typealias AnimatableData = Content.AnimatableData

    /// The shape's own data.
    @MainActor public var animatableData: AnimatableData {
        get { shape.animatableData }
        set { shape.animatableData = newValue }
    }
}
