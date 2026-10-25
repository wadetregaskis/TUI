//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ShadowStyle.swift
//
//  SwiftUI's shadows, as a cell grid can have them: the cells a view paints,
//  offset and spread by whole cells, darkening what they fall on with a
//  translucent colour (refusal review O6, ruled 2026-10-12: option (b), cells
//  as-is).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

/// A style to use when rendering shadows — mirrors SwiftUI's `ShadowStyle`.
///
/// SwiftUI blurs, tints and offsets a view's per-pixel alpha. A cell has one
/// alpha that matters here, whether the view paints it at all, so a shadow is
/// drawn from the cells the view paints — a glyph, or a cell with a field of
/// its own — and darkens the cells it falls on by compositing the shadow's
/// colour over them at its alpha:
///
/// - **`radius` and the offsets are cells**, as `.padding(8)`'s eight is. The
///   offsets move the shadow `x` columns right and `y` rows down, and the
///   radius spreads it: the shadow's alpha falls off across that many cells
///   beyond its edge, by a step of `1 / (radius + 1)` a cell, so a radius of
///   `0` is a hard shadow the shape of the view and a radius of `3` fades out
///   over three cells. A ported `radius: 8` is eight cells — as wide, across,
///   as `.padding(8)` — which is much more than SwiftUI's eight points
///   (`Deliberate deviations from SwiftUI.md`, C10). A radius past 32 cells is
///   drawn as 32, since a shadow costs the square of its radius.
/// - **A drop shadow** is drawn behind the view, over what is behind it: where
///   the view paints a field of its own the shadow is hidden, and everywhere
///   else — past its edges, and under the cells it leaves clear — what is
///   behind is darkened, glyphs included, and the view's own glyphs are drawn
///   on that.
/// - **An inner shadow** is drawn over the view, inside its edges: the cells
///   it paints are darkened toward an edge, ink and field alike, more on the
///   side the offset points away from.
///
/// ```swift
/// Text("Saved")
///     .padding(1)
///     .background(.blue)
///     .shadow(radius: 1, x: 2, y: 1)
/// ```
///
/// `View.shadow(color:radius:x:y:)` draws a drop shadow, and
/// ``ShapeStyle/shadow(_:)-method`` — the one place SwiftUI takes a `ShadowStyle` — a
/// style drawn with either kind, cast by whatever draws with the style from
/// the cells it drew:
///
/// ```swift
/// Text("Pressed")
///     .padding(1)
///     .background(.blue.shadow(.inner(radius: 1, x: 1, y: 1)))
/// ```
public struct ShadowStyle: Equatable, Sendable {
    /// Which side of the view the shadow is drawn on.
    enum Kind: UInt8, Sendable {
        /// Behind the view, around it.
        case drop
        /// Over the view, inside its edges.
        case inner
    }

    // Stored words first, then the colour, then the kind: no padding between
    // them, so every byte the render memo's value hash reads is written.
    // Internal `var`s for the animator, which draws a frame at an animated
    // radius, offset and colour (`ShadowModifier`); nothing outside the module
    // can set them.

    /// How many cells the shadow's alpha falls off across, never negative.
    var radius: Int

    /// How many columns right of the view the shadow is drawn.
    var x: Int

    /// How many rows below the view the shadow is drawn.
    var y: Int

    /// What the shadow darkens with, its alpha the shadow's at its darkest.
    var color: Color

    /// Drop or inner.
    let kind: Kind

    private init(kind: Kind, color: Color, radius: Int, x: Int, y: Int) {
        self.radius = max(0, radius)
        self.x = x
        self.y = y
        self.color = color
        self.kind = kind
    }

    /// Creates a custom drop shadow style.
    ///
    /// Drop shadows draw behind the source content: the cells it paints,
    /// offset, spread by the radius and drawn in the colour over what is behind
    /// it.
    ///
    /// - Parameters:
    ///   - color: The shadow's color: black at a third by default, as in
    ///     SwiftUI.
    ///   - radius: The shadow's size: how many cells its alpha falls off across.
    ///   - x: A horizontal offset you use to position the shadow relative to
    ///     this view, in columns.
    ///   - y: A vertical offset you use to position the shadow relative to this
    ///     view, in rows.
    /// - Returns: A new shadow style.
    public static func drop(
        color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33), radius: Int, x: Int = 0, y: Int = 0
    ) -> Self {
        Self(kind: .drop, color: color, radius: radius, x: x, y: y)
    }

    /// Creates a custom inner shadow style.
    ///
    /// Inner shadows draw on top of the source content: the cells it paints are
    /// darkened toward the edges of what it paints, offset and spread by the
    /// radius.
    ///
    /// - Parameters:
    ///   - color: The shadow's color: black at a little over half by default,
    ///     as in SwiftUI.
    ///   - radius: The shadow's size: how many cells in from an edge its alpha
    ///     falls off across.
    ///   - x: A horizontal offset you use to position the shadow relative to
    ///     this view, in columns.
    ///   - y: A vertical offset you use to position the shadow relative to this
    ///     view, in rows.
    /// - Returns: A new shadow style.
    public static func inner(
        color: Color = Color(.sRGBLinear, white: 0, opacity: 0.55), radius: Int, x: Int = 0, y: Int = 0
    ) -> Self {
        Self(kind: .inner, color: color, radius: radius, x: x, y: y)
    }
}
