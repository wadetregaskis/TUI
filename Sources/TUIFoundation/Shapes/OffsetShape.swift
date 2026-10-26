//  🖥️ TUI — A Terminal UI framework for Swift
//  OffsetShape.swift
//
//  A shape moved within its frame.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// A shape with a translation offset transform applied to it — mirrors
/// SwiftUI's `OffsetShape`.
///
/// The offset is in the shape's unit, columns across and on the same scale
/// down, and moves the path, not the view: what is moved past the frame is not
/// drawn.
nonisolated public struct OffsetShape<Content: Shape>: Shape {
    /// The shape.
    public var shape: Content

    /// How far it is moved.
    public var offset: CGSize

    /// A shape moved by `offset`.
    ///
    /// - Parameters:
    ///   - shape: The shape.
    ///   - offset: How far to move it.
    public init(shape: Content, offset: CGSize) {
        self.shape = shape
        self.offset = offset
    }

    /// The shape's path, moved.
    public func path(in rect: CGRect) -> Path {
        shape.path(in: rect).offsetBy(dx: offset.width, dy: offset.height)
    }

    /// The shape's own role.
    public static var role: ShapeRole { Content.role }
}

extension OffsetShape {
    /// The shape's own data, then the offset's width and height.
    public typealias AnimatableData = AnimatablePair<Content.AnimatableData, AnimatablePair<CGFloat, CGFloat>>

    /// The shape and its offset, animated together.
    @MainActor public var animatableData: AnimatableData {
        get { AnimatablePair(shape.animatableData, AnimatablePair(offset.width, offset.height)) }
        set {
            shape.animatableData = newValue.first
            offset = CGSize(width: newValue.second.first, height: newValue.second.second)
        }
    }
}

extension OffsetShape: InsettableShape where Content: InsettableShape {
    /// The shape inset, then moved as this one is.
    public typealias InsetShape = OffsetShape<Content.InsetShape>

    /// The shape inset by `amount`, moved as this one is.
    public func inset(by amount: CGFloat) -> OffsetShape<Content.InsetShape> {
        OffsetShape<Content.InsetShape>(shape: shape.inset(by: amount), offset: offset)
    }
}
