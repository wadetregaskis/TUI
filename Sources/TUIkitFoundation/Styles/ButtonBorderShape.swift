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
/// the pointer, and breathe the focus with the label. A rounded rectangle of
/// radius zero is square: `[ … ]`, and `┌──┐` / `│ … │` / `└──┘`. TUIkit's own
/// ``brackets(_:_:)`` draws the same face between any two glyphs of a cell
/// each. A circle is a capsule with no padding, for a button whose label is
/// one glyph.
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
        case automatic, capsule, roundedRectangle, square, circle
        /// TUIkit's own: lines between these two glyphs.
        case brackets(open: Character, close: Character)
    }

    let kind: Kind

    /// A shape that defers to the system to determine an appropriate shape for
    /// the given context and platform: a capsule, as TUIkit's buttons have
    /// always been.
    public static let automatic = Self(kind: .automatic)

    /// A capsule shape: the face ends in half-block caps.
    public static let capsule = Self(kind: .capsule)

    /// A rectangle shape with rounded corners: the face is drawn in lines,
    /// parentheses on one row and a box with rounded corners on three.
    public static let roundedRectangle = Self(kind: .roundedRectangle)

    /// A rectangle shape with rounded corners with the specified radius.
    ///
    /// A cell has no fraction of a corner to round, so the radius says only
    /// whether the corners are round: any radius above zero is
    /// ``roundedRectangle``, and zero is a square one — square brackets on
    /// one row, `[ … ]`, and a box with square corners on three.
    ///
    /// - Parameter radius: The radius of the corners; zero for square ones.
    /// - Returns: A rounded rectangle shape, or a square one.
    public static func roundedRectangle(radius: Double) -> Self {
        radius > 0 ? roundedRectangle : Self(kind: .square)
    }

    /// A shape drawn in lines between two glyphs of your choosing — TUIkit's
    /// own, beside SwiftUI's shapes: `.brackets("<", ">")` draws `< OK >`, or
    /// `⟨ OK ⟩`, or any pair, as a rounded rectangle draws `( OK )`, and on three
    /// rows the rounded rectangle's box.
    ///
    /// Each glyph must take one cell; a pair that does not draws as
    /// ``roundedRectangle``.
    ///
    /// - Parameters:
    ///   - open: The glyph before the label.
    ///   - close: The glyph after the label.
    /// - Returns: A shape drawn in lines between those glyphs.
    public static func brackets(_ open: Character, _ close: Character) -> Self {
        Self(kind: .brackets(open: open, close: close))
    }

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
