//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnyShape.swift
//
//  A type-erased shape.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// A type-erased shape value — mirrors SwiftUI's `AnyShape`.
///
/// It draws as the shape it holds would: a rectangle-family shape in box
/// glyphs, any other rasterized, and one that stands for another — the
/// `.buttonBorder` in force, a container's shape — as the one it stands for.
nonisolated public struct AnyShape: Shape {
    /// The shape this stands for.
    let base: any Shape

    /// Create an any shape instance from a shape.
    ///
    /// - Parameter shape: The shape to erase.
    public init<S: Shape>(_ shape: S) {
        base = shape
    }

    /// The erased shape's path.
    public func path(in rect: CGRect) -> Path {
        base.path(in: rect)
    }

    /// The erased shape's size.
    public func sizeThatFits(_ proposal: ProposedSize) -> ViewSize {
        base.sizeThatFits(proposal)
    }
}

extension AnyShape {
    /// The erased shape's animation is not reachable through the erasure.
    public typealias AnimatableData = EmptyAnimatableData
}

extension AnyShape: BoxDrawnShape {
    func boxCorners(in rect: CGRect) -> RectangleCornerRadii? {
        (base as? any BoxDrawnShape)?.boxCorners(in: rect)
    }
}

extension AnyShape: EnvironmentResolvedShape {
    /// The shape it holds, as that shape is drawn: the one it stands for
    /// where it stands for another — `AnyShape(.buttonBorder)` is the button
    /// border shape in force — and a stroke as a shape still a stroke.
    func resolvedShape(in context: RenderContext, columns: Int, rows: Int) -> any Shape {
        (base as? any EnvironmentResolvedShape)?.resolvedShape(in: context, columns: columns, rows: rows) ?? base
    }
}
