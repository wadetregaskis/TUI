//  🖥️ TUI — A Terminal UI framework for Swift
//  UnevenRoundedRectangle.swift
//
//  A rectangle whose corners each have a radius of their own.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// A rectangular shape with rounded corners with different values, aligned
/// inside the frame of the view containing it — mirrors SwiftUI's
/// `UnevenRoundedRectangle`.
///
/// Drawn as lines, each corner is `╭` or `┌` by whether its own radius is
/// above zero, so the four radii are exactly what a box of glyphs can say.
nonisolated public struct UnevenRoundedRectangle: Shape {
    /// The radii of each corner of the rounded rectangle.
    public var cornerRadii: RectangleCornerRadii

    /// The style of corners drawn by the rounded rectangle.
    public var style: RoundedCornerStyle

    /// How far this rectangle is inset inside its frame, by ``inset(by:)``.
    var insetAmount: CGFloat = 0

    /// Creates a new rounded rectangle shape with uneven corners.
    ///
    /// - Parameters:
    ///   - cornerRadii: The radius of each corner.
    ///   - style: The corner style.
    public init(cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous) {
        self.cornerRadii = cornerRadii
        self.style = style
    }

    /// Creates a new rounded rectangle shape with uneven corners.
    ///
    /// - Parameters:
    ///   - topLeadingRadius: The radius of the top-leading corner.
    ///   - bottomLeadingRadius: The radius of the bottom-leading corner.
    ///   - bottomTrailingRadius: The radius of the bottom-trailing corner.
    ///   - topTrailingRadius: The radius of the top-trailing corner.
    ///   - style: The corner style.
    public init(
        topLeadingRadius: CGFloat = 0, bottomLeadingRadius: CGFloat = 0, bottomTrailingRadius: CGFloat = 0,
        topTrailingRadius: CGFloat = 0, style: RoundedCornerStyle = .continuous
    ) {
        self.init(
            cornerRadii: RectangleCornerRadii(
                topLeading: topLeadingRadius, bottomLeading: bottomLeadingRadius, bottomTrailing: bottomTrailingRadius,
                topTrailing: topTrailingRadius),
            style: style)
    }

    /// The rounded rectangle in the frame, inset by however much it has been,
    /// each corner shrunk by the same amount.
    public func path(in rect: CGRect) -> Path {
        let shrink = { (radius: CGFloat) in max(0, radius - insetAmount) }
        let radii = RectangleCornerRadii(
            topLeading: shrink(cornerRadii.topLeading), bottomLeading: shrink(cornerRadii.bottomLeading),
            bottomTrailing: shrink(cornerRadii.bottomTrailing), topTrailing: shrink(cornerRadii.topTrailing))
        return Path(roundedRect: rect.insetForShape(by: insetAmount), cornerRadii: radii, style: style)
    }
}

extension UnevenRoundedRectangle: Animatable {
    /// The four radii's.
    public typealias AnimatableData = RectangleCornerRadii.AnimatableData

    /// The four radii, animated together.
    @MainActor public var animatableData: RectangleCornerRadii.AnimatableData {
        get { cornerRadii.animatableData }
        set { cornerRadii.animatableData = newValue }
    }
}

extension UnevenRoundedRectangle: InsettableShape {
    /// The inset shape: this shape, inset — SwiftUI's is opaque, and this is
    /// what is behind it.
    public typealias InsetShape = UnevenRoundedRectangle

    /// Returns `self` inset by `amount`, each corner shrunk by the same.
    public func inset(by amount: CGFloat) -> UnevenRoundedRectangle {
        var inset = self
        inset.insetAmount += amount
        return inset
    }
}

extension UnevenRoundedRectangle: BoxDrawnShape {
    func boxCorners(in rect: CGRect) -> RectangleCornerRadii? {
        insetAmount == 0 ? cornerRadii : nil
    }
}
