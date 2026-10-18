//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Capsule.swift
//
//  A rectangle whose shorter sides are half circles.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// A capsule shape aligned inside the frame of the view containing it —
/// mirrors SwiftUI's `Capsule`.
///
/// A rounded rectangle whose corner radius is half its shorter side. Drawn as
/// lines it is `╭─╮` / `╰─╯`, or `( … )` one row tall; filled one row tall it
/// is the half-block caps `▐ … ▌`, TUIkit's capsule since its first text field.
nonisolated public struct Capsule: Shape {
    /// The style of corners drawn by the capsule.
    public var style: RoundedCornerStyle

    /// How far this capsule is inset inside its frame, by ``inset(by:)``.
    var insetAmount: CGFloat = 0

    /// Creates a new capsule shape.
    ///
    /// - Parameter style: The corner style.
    public init(style: RoundedCornerStyle = .continuous) {
        self.style = style
    }

    /// The capsule in the frame, inset by however much it has been.
    public func path(in rect: CGRect) -> Path {
        let frame = rect.insetForShape(by: insetAmount)
        return Path(roundedRect: frame, cornerRadius: min(frame.width, frame.height) / 2, style: style)
    }
}

extension Capsule {
    /// A capsule has nothing to animate.
    public typealias AnimatableData = EmptyAnimatableData
}

extension Capsule: InsettableShape {
    /// The inset shape: this shape, inset — SwiftUI's is opaque, and this is
    /// what is behind it.
    public typealias InsetShape = Capsule

    /// Returns `self` inset by `amount`.
    public func inset(by amount: CGFloat) -> Capsule {
        var inset = self
        inset.insetAmount += amount
        return inset
    }
}

extension Capsule: BoxDrawnShape {
    func boxCorners(in rect: CGRect) -> RectangleCornerRadii? {
        guard insetAmount == 0 else { return nil }
        let radius = min(rect.width, rect.height) / 2
        return RectangleCornerRadii(topLeading: radius, bottomLeading: radius, bottomTrailing: radius, topTrailing: radius)
    }
}
