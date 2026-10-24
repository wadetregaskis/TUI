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
/// - **Braille** — `.braille`, and `.braille(thickness:)` for bolder dots: a
///   dotted outline of the shape itself, at any size and any label's length —
///   on one row its ends (`⢎ OK ⡱` a capsule, `⣏ OK ⣹` a rectangle), on three
///   the whole outline, a capsule's ends round, a circle a dotted disc. The
///   dots breathe the focus with the label, as lines do.
/// - **Blank** — `.blank`: the label alone, breathing the focus.
///
/// TUIkit's own ``brackets(_:_:)`` draws a lines face between any two glyphs
/// of a cell each, and its own ``underline`` a lines face that is a line
/// under the label alone.
///
/// Read by the built-in styles with a face; a plain, borderless or link
/// button has none, and draws as it would.
///
/// It is a ``Shape`` as well, as SwiftUI's is: a capsule (and `.automatic`,
/// which defers to the shape ``View/buttonBorderShape(_:)`` sets, as
/// ``Shape/buttonBorder`` does), a rectangle rounded a column and a half, a
/// square one, or a circle — drawn as any shape of those kinds is.
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
        /// TUIkit's own: a line under the label.
        case underline
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
    /// ``roundedRectangle``. Drawn in lines under the default control style,
    /// whose other shapes are filled; under `.controlStyle(.block)`, Braille or
    /// blank it draws as a rounded rectangle of that family.
    ///
    /// Some pairs that read well in a lines face: `⌜ ⌟` corners and `▕ ▏`
    /// eighth blocks hugging the label; and `❨ ❩` and `⟨ ⟩`, one cell in every
    /// terminal measured and well laid out in each (*Terminal compatibility
    /// survey*, "Bracket pairs for a compact face"). Avoid `⦅ ⦆`, which
    /// overhangs its label in Warp, and `⸨ ⸩`, which Warp does not draw.
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

    /// A line under the label, and no caps — TUIkit's own, beside SwiftUI's
    /// shapes.
    ///
    /// The line spans the label alone, not its padding, and is drawn in the
    /// lines' colour where the terminal colours an underline (SGR 58), in the
    /// label's where it does not. It breathes the focus with the label. On
    /// three rows it is the rounded rectangle's box. Drawn in lines under the
    /// default control style, whose other shapes are filled; a face in
    /// `.controlStyle(.block)` or Braille draws it as a rounded rectangle,
    /// having no lines to underline with.
    public static let underline = Self(kind: .underline)

    /// Whether this shape is a lines face and nothing else — the brackets and
    /// the underline, which a default (``ControlStyle/automatic``) control
    /// therefore draws in lines rather than filling.
    var isDrawnInLinesOnly: Bool {
        switch kind {
        case .brackets, .underline: true
        default: false
        }
    }
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
