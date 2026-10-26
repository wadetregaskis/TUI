//  🖥️ TUI — A Terminal UI framework for Swift
//  InsettableShape.swift
//
//  A shape that can be inset, and so can be stroked inside its frame.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// A shape type that is able to inset itself to produce another shape —
/// mirrors SwiftUI's `InsettableShape`.
///
/// Insetting is path arithmetic: the shape drawn in its rectangle inset by
/// `amount` on every side, a corner radius shrinking with it. It is what
/// ``strokeBorder(_:lineWidth:antialiased:)`` is made of — the outline inset
/// by half the line's width, so the whole line lies inside the frame.
nonisolated public protocol InsettableShape: Shape {
    /// The type of the inset shape.
    associatedtype InsetShape: InsettableShape

    /// Returns `self` inset by `amount`.
    ///
    /// - Parameter amount: How far to inset, in the shape's unit (columns).
    /// - Returns: The inset shape.
    func inset(by amount: CGFloat) -> InsetShape
}

extension InsettableShape {
    /// Traces the outline of this shape inside its frame: the shape inset by
    /// half the line's width, stroked.
    ///
    /// - Parameters:
    ///   - content: The style to trace with — the foreground style unless
    ///     given.
    ///   - lineWidth: The line's width, in columns.
    ///   - antialiased: Whether the rasterized line's edges blend.
    /// - Returns: The shape's border.
    public func strokeBorder<S: ShapeStyle>(
        _ content: S = .foreground, lineWidth: CGFloat = 1, antialiased: Bool = true
    ) -> StrokeBorderShapeView<Self, S, EmptyView> {
        StrokeBorderShapeView(
            shape: self, style: content, strokeStyle: StrokeStyle(lineWidth: lineWidth), isAntialiased: antialiased,
            background: EmptyView())
    }

    /// Traces the outline of this shape inside its frame in `style`'s width,
    /// caps, joins and dashes.
    ///
    /// - Parameters:
    ///   - content: The style to trace with — the foreground style unless
    ///     given.
    ///   - style: The stroke's characteristics.
    ///   - antialiased: Whether the rasterized line's edges blend.
    /// - Returns: The shape's border.
    public func strokeBorder<S: ShapeStyle>(
        _ content: S = .foreground, style: StrokeStyle, antialiased: Bool = true
    ) -> StrokeBorderShapeView<Self, S, EmptyView> {
        StrokeBorderShapeView(shape: self, style: content, strokeStyle: style, isAntialiased: antialiased, background: EmptyView())
    }
}

extension CGRect {
    /// This rectangle inset by `amount` on every side, or an empty one at its
    /// centre when the inset passes the middle — never a null rectangle, whose
    /// infinite corners a path cannot be drawn from.
    func insetForShape(by amount: CGFloat) -> CGRect {
        guard amount != 0 else { return self }
        let dx = min(amount, width / 2)
        let dy = min(amount, height / 2)
        return CGRect(x: minX + dx, y: minY + dy, width: max(0, width - 2 * dx), height: max(0, height - 2 * dy))
    }
}
