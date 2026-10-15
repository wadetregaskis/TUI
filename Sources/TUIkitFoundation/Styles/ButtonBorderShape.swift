//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ButtonBorderShape.swift
//
//  SwiftUI's button border shapes, read as the glyphs a bordered button's face
//  ends in.
//
//  Created by Wade Tregaskis
//  License: MIT

/// A shape used to draw a button's border — mirrors SwiftUI's
/// `ButtonBorderShape`.
///
/// A terminal draws a border in cells, so a shape is how a bordered button's
/// face is drawn. A capsule is a filled face ending in the half-block caps
/// `▐ … ▌`, which round its ends; three rows tall (``ControlSize/large`` and
/// ``ControlSize/extraLarge``) its rows are rounded off by quadrant corners.
/// A rounded rectangle is drawn in lines, with no field under the label:
/// parentheses, `( … )`, on one row, and a box with rounded corners,
/// `╭──╮` / `│ … │` / `╰──╯`, on three; the lines show at rest, brighten under
/// the pointer, and breathe the focus with the label. A circle is a capsule
/// with no padding, for a button whose label is one glyph.
///
/// Read by the built-in styles with a face; a plain, borderless or link
/// button has none, and draws as it would.
///
/// ```swift
/// Button("Sign In") {}
///     .buttonStyle(.borderedProminent)
///     .buttonBorderShape(.roundedRectangle)
/// ```
public struct ButtonBorderShape: Equatable, Sendable {
    /// What the shape draws.
    enum Kind: Equatable, Sendable {
        case automatic, capsule, roundedRectangle, circle
    }

    let kind: Kind

    /// A shape that defers to the system to determine an appropriate shape for
    /// the given context and platform: a capsule, as TUIkit's buttons have
    /// always been.
    public static let automatic = Self(kind: .automatic)

    /// A capsule shape: the face ends in half-block caps.
    public static let capsule = Self(kind: .capsule)

    /// A rectangle shape with rounded corners: the face ends in thin
    /// one-eighth-block edges.
    public static let roundedRectangle = Self(kind: .roundedRectangle)

    /// A rectangle shape with rounded corners with the specified radius.
    ///
    /// A radius in points has no reading in cells, so this is
    /// ``roundedRectangle``.
    ///
    /// - Parameter radius: The radius of the corners. Not read.
    /// - Returns: A rounded rectangle shape.
    public static func roundedRectangle(radius: Double) -> Self { roundedRectangle }

    /// A circular shape: a capsule with no padding, for a label of one glyph.
    public static let circle = Self(kind: .circle)
}

private struct ButtonBorderShapeKey: EnvironmentKey {
    static let defaultValue = ButtonBorderShape.automatic
}

extension EnvironmentValues {
    /// The border shape of the buttons below — set with
    /// ``View/buttonBorderShape(_:)``. SwiftUI keeps this internal; a style
    /// of an app's own reads it here.
    public var buttonBorderShape: ButtonBorderShape {
        get { self[ButtonBorderShapeKey.self] }
        set { self[ButtonBorderShapeKey.self] = newValue }
    }
}

extension View {
    /// Sets the border shape for buttons in this view — mirrors SwiftUI's
    /// `buttonBorderShape(_:)`.
    ///
    /// - Parameter shape: The shape bordered buttons in this view take.
    /// - Returns: A view whose bordered buttons take `shape`.
    public func buttonBorderShape(_ shape: ButtonBorderShape) -> some View {
        environment(\.buttonBorderShape, shape)
    }
}
