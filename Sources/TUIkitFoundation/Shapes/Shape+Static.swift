//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Shape+Static.swift
//
//  The built-in shapes by their leading-dot names: `.rect`, `.circle`,
//  `.capsule`, `.ellipse`, `.containerRelative` and the rounded rectangles.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

extension Shape where Self == Rectangle {
    /// A rectangular shape aligned inside the frame of the view containing it.
    public static var rect: Rectangle { Rectangle() }
}

extension Shape where Self == RoundedRectangle {
    /// A rectangular shape with rounded corners, aligned inside the frame of
    /// the view containing it.
    ///
    /// - Parameters:
    ///   - cornerSize: The size of the corners.
    ///   - style: The corner style.
    public static func rect(cornerSize: CGSize, style: RoundedCornerStyle = .continuous) -> Self {
        RoundedRectangle(cornerSize: cornerSize, style: style)
    }

    /// A rectangular shape with rounded corners, aligned inside the frame of
    /// the view containing it.
    ///
    /// - Parameters:
    ///   - cornerRadius: The radius of the corners.
    ///   - style: The corner style.
    public static func rect(cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) -> Self {
        RoundedRectangle(cornerRadius: cornerRadius, style: style)
    }
}

extension Shape where Self == UnevenRoundedRectangle {
    /// A rectangular shape with rounded corners with different values,
    /// aligned inside the frame of the view containing it.
    ///
    /// - Parameters:
    ///   - cornerRadii: The radius of each corner.
    ///   - style: The corner style.
    public static func rect(cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous) -> Self {
        UnevenRoundedRectangle(cornerRadii: cornerRadii, style: style)
    }

    /// A rectangular shape with rounded corners with different values,
    /// aligned inside the frame of the view containing it.
    ///
    /// - Parameters:
    ///   - topLeadingRadius: The radius of the top-leading corner.
    ///   - bottomLeadingRadius: The radius of the bottom-leading corner.
    ///   - bottomTrailingRadius: The radius of the bottom-trailing corner.
    ///   - topTrailingRadius: The radius of the top-trailing corner.
    ///   - style: The corner style.
    public static func rect(
        topLeadingRadius: CGFloat = 0, bottomLeadingRadius: CGFloat = 0, bottomTrailingRadius: CGFloat = 0,
        topTrailingRadius: CGFloat = 0, style: RoundedCornerStyle = .continuous
    ) -> Self {
        UnevenRoundedRectangle(
            topLeadingRadius: topLeadingRadius, bottomLeadingRadius: bottomLeadingRadius,
            bottomTrailingRadius: bottomTrailingRadius, topTrailingRadius: topTrailingRadius, style: style)
    }
}

extension Shape where Self == Capsule {
    /// A capsule shape aligned inside the frame of the view containing it.
    public static var capsule: Capsule { Capsule() }

    /// A capsule shape aligned inside the frame of the view containing it.
    ///
    /// - Parameter style: The corner style.
    public static func capsule(style: RoundedCornerStyle) -> Self {
        Capsule(style: style)
    }
}

extension Shape where Self == Circle {
    /// A circle centered on the frame of the view containing it.
    public static var circle: Circle { Circle() }
}

extension Shape where Self == Ellipse {
    /// An ellipse aligned inside the frame of the view containing it.
    public static var ellipse: Ellipse { Ellipse() }
}

extension Shape where Self == ContainerRelativeShape {
    /// A shape that is replaced by an inset version of the current container
    /// shape. If no container shape was defined, is replaced by a rectangle.
    public static var containerRelative: ContainerRelativeShape { ContainerRelativeShape() }
}
