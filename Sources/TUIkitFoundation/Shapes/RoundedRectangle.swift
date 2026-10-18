//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RoundedRectangle.swift
//
//  A rectangle with rounded corners, all alike.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// A rectangular shape with rounded corners, aligned inside the frame of the
/// view containing it — mirrors SwiftUI's `RoundedRectangle`.
///
/// The corner size is in the shape's unit — columns across, and on the same
/// scale down — so `cornerRadius: 2` rounds two columns and one row. Drawn as
/// lines a corner of any radius above zero is `╭`; filled, its corner is cut in
/// quadrants from the true curve, by at least one.
nonisolated public struct RoundedRectangle: Shape {
    /// The width and height of the rounded rectangle's corners.
    public var cornerSize: CGSize

    /// The style of corners drawn by the rounded rectangle.
    public var style: RoundedCornerStyle

    /// How far this rectangle is inset inside its frame, by ``inset(by:)``.
    var insetAmount: CGFloat = 0

    /// Creates a new rounded rectangle shape.
    ///
    /// - Parameters:
    ///   - cornerSize: The width and height of the corners.
    ///   - style: The corner style.
    public init(cornerSize: CGSize, style: RoundedCornerStyle = .continuous) {
        self.cornerSize = cornerSize
        self.style = style
    }

    /// Creates a new rounded rectangle shape.
    ///
    /// - Parameters:
    ///   - cornerRadius: The radius of every corner.
    ///   - style: The corner style.
    public init(cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) {
        self.init(cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: style)
    }

    /// The rounded rectangle in the frame, inset by however much it has been,
    /// its corners shrunk by the same amount.
    public func path(in rect: CGRect) -> Path {
        let size = CGSize(width: max(0, cornerSize.width - insetAmount), height: max(0, cornerSize.height - insetAmount))
        return Path(roundedRect: rect.insetForShape(by: insetAmount), cornerSize: size, style: style)
    }
}

extension RoundedRectangle: Animatable {
    /// The corner size's width and height.
    public typealias AnimatableData = AnimatablePair<CGFloat, CGFloat>

    /// The corner size, animated.
    public var animatableData: AnimatableData {
        get { AnimatablePair(cornerSize.width, cornerSize.height) }
        set { cornerSize = CGSize(width: newValue.first, height: newValue.second) }
    }
}

extension RoundedRectangle: InsettableShape {
    /// The inset shape: this shape, inset — SwiftUI's is opaque, and this is
    /// what is behind it.
    public typealias InsetShape = RoundedRectangle

    /// Returns `self` inset by `amount`, its corners shrunk by the same.
    public func inset(by amount: CGFloat) -> RoundedRectangle {
        var inset = self
        inset.insetAmount += amount
        return inset
    }
}

extension RoundedRectangle: BoxDrawnShape {
    func boxCorners(in rect: CGRect) -> RectangleCornerRadii? {
        guard insetAmount == 0 else { return nil }
        let radius = min(cornerSize.width, cornerSize.height)
        return RectangleCornerRadii(topLeading: radius, bottomLeading: radius, bottomTrailing: radius, topTrailing: radius)
    }
}
