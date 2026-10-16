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
/// A terminal draws a border in cells, so a shape is which member of a
/// family a bordered button's face is — the family being the ``Appearance``
/// in force, so that every shape on a page looks of a piece. A capsule's
/// ends are curved, a rounded rectangle's sides straight with small corners,
/// and a circle is a capsule about as wide as it is tall:
///
/// - **Lines** — `.rounded`, the default, and `.line`, `.heavy`,
///   `.doubleLine`: no field under the label. A capsule is `( OK )`, and on
///   three rows (``ControlSize/large``, ``ControlSize/extraLarge``) `( OK )`
///   in a box of the appearance's lines; a rounded rectangle `│ OK │`, in the
///   same box; radius zero `[ OK ]`, in a box with square corners; a circle
///   `(★)`. The lines show at rest, lift under the pointer, and breathe the
///   focus with the label.
/// - **Solid** — `.block`: filled faces. A capsule ends in the half-block caps
///   `▐ OK ▌`; a rectangle in square ends of the face; a circle `▐★▌`. On
///   three rows each is its shape drawn in quadrants — a capsule's corners
///   curve in two steps (`▗▟`), a rounded rectangle's in one (`▟`), radius
///   zero's not at all — or, on a terminal that draws block elements short of
///   the line (Apple Terminal), in whole cells.
/// - **Blank** — `.blank`: the label alone, breathing the focus.
///
/// TUIkit's own ``brackets(_:_:)`` draws a lines face between any two glyphs
/// of a cell each.
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
