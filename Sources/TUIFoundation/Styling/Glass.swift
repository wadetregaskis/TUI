//  🖥️ TUI — A Terminal UI framework for Swift
//  Glass.swift
//
//  SwiftUI's glass, as a terminal can have it: a material's translucent
//  surface with a highlighted rim, and no blur (refusal review O5, ruled
//  2026-10-12: option (b) for Material and for Glass).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIStyling

/// A structure that defines the configuration of a physical glass material —
/// mirrors SwiftUI's `Glass`.
///
/// You provide instances of glass to the ``View/glassEffect(_:in:)`` view
/// modifier:
///
/// ```swift
/// Label("Flag", systemImage: "flag.fill")
///     .padding()
///     .glassEffect()
/// ```
///
/// SwiftUI's glass refracts and blurs what is behind it. A cell has nothing
/// below it to refract, so glass here is what a ``Material`` is — what it
/// covers frosted (its glyphs dropped, its colours averaged with their
/// neighbours', over a smaller box than a material's: `frost(in:)`) and a
/// palette surface at a fraction of its opacity composited over that, cell by
/// cell — with the edge that makes glass read as glass: a **rim**, the shape's outline drawn in a highlight, in the lines of
/// the ``Appearance`` in force (Deliberate deviations C11). ``regular`` is the
/// regular material's surface and ``clear`` the ultra-thin one's; a ``tint(_:)``
/// makes the surface that colour instead, and lifts the rim from it.
/// ``interactive(_:)`` glass answers the pointer: its rim lifts again while the
/// pointer is over it.
///
/// Glass that does not appear active stays frosted, as a material does, its
/// surface half way to opaque: SwiftUI's glass goes flat in an inactive
/// window, which read here as the glass having broken (``MaterialActiveAppearance``).
///
/// You can combine glass effects by using a ``GlassEffectContainer``, which
/// draws the glass of views near one another as one shape.
public struct Glass: Equatable, Sendable {
    /// The three variants of glass.
    enum Variant: UInt8, Equatable, Sendable {
        case regular
        case clear
        case identity
    }

    /// The colour the glass is tinted, or `nil` for the page's surface.
    let tintColor: Color?

    /// Which variant this is.
    let variant: Variant

    /// Whether the glass answers the pointer.
    let isInteractive: Bool

    private init(variant: Variant, tintColor: Color? = nil, isInteractive: Bool = false) {
        self.tintColor = tintColor
        self.variant = variant
        self.isInteractive = isInteractive
    }

    /// The regular variant of glass.
    ///
    /// SwiftUI's keeps the content on it legible by adjusting it to the
    /// luminosity of what is beneath. Here it is the regular material's
    /// surface, opaque enough that what shows through it does not compete with
    /// the content on it.
    public static var regular: Self { Self(variant: .regular) }

    /// The clear variant of glass.
    ///
    /// The ultra-thin material's surface: most of what is behind shows through,
    /// so, as in SwiftUI, content on it may need a dimming layer beneath the
    /// glass to stay legible:
    ///
    /// ```swift
    /// Label("Flag", systemImage: "flag.fill")
    ///     .padding()
    ///     .glassEffect(.clear)
    ///     .background(.black.opacity(0.3))
    /// ```
    public static var clear: Self { Self(variant: .clear) }

    /// The identity variant of glass. When applied, your content remains
    /// unaffected as if no glass effect was applied.
    public static var identity: Self { Self(variant: .identity) }

    /// Returns a copy of the glass with the provided tint color.
    ///
    /// The surface is the tint, at this glass's opacity, and the rim is the
    /// tint lifted. `nil` takes the tint away.
    ///
    /// - Parameter color: The tint, or `nil` for none.
    /// - Returns: The glass, tinted.
    public func tint(_ color: Color?) -> Self {
        Self(variant: variant, tintColor: color, isInteractive: isInteractive)
    }

    /// Returns a copy of the glass configured to be interactive.
    ///
    /// Interactive glass answers the pointer: while it is over the glass, the
    /// rim lifts a step further. It is a look, not a control — the glass takes
    /// no click and no focus, so nothing is reachable only with a mouse.
    ///
    /// - Parameter isEnabled: Whether the glass is interactive.
    /// - Returns: The glass, interactive or not.
    public func interactive(_ isEnabled: Bool = true) -> Self {
        Self(variant: variant, tintColor: tintColor, isInteractive: isEnabled)
    }
}

// MARK: - Drawing

extension Glass {
    /// Whether this glass draws nothing: ``identity``.
    var isIdentity: Bool { variant == .identity }

    /// The material whose opacity this glass's surface takes.
    private var material: Material { variant == .clear ? .ultraThin : .regular }

    /// How this glass frosts what is behind it in `environment`: by default the
    /// box of a material one step thinner than the one whose surface it takes —
    /// ``Material/thin``'s for ``regular`` and ``Material/ultraThin``'s, there
    /// being none thinner, for ``clear`` — because SwiftUI's glass lenses what
    /// is behind it more than it blurs it, and keeps it plainer than a material
    /// as see-through does. ``EnvironmentValues/materialFrost`` sets it as it
    /// does a material's.
    func frost(in environment: EnvironmentValues) -> OpacityRegion.Frost {
        let thinner: Material = variant == .clear ? .ultraThin : .thin
        return environment.materialFrost.resolved(thickness: thinner.frost)
    }

    /// The surface: the tint or the page's background, at the material's
    /// opacity while it appears active and half way from that to opaque while
    /// not. Semantic where the colour is, so it follows the palette.
    func surface(in environment: EnvironmentValues) -> Color {
        material.surface(tintColor ?? Color.palette.background, in: environment)
    }

    /// The surface as it lands on what the glass is drawn over, opaque — what
    /// ink on tinted glass lands on, for a control inside that floors its
    /// contrast (``EnvironmentValues/enclosingSurface``). `nil` for untinted
    /// glass, which is the page's own colour and leaves the surface as it was.
    func tintedSurface(in environment: EnvironmentValues) -> Color? {
        guard tintColor != nil else { return nil }
        let palette = environment.palette
        return surface(in: environment).resolve(with: palette).spendingAlpha(over: environment.enclosingSurface)
    }

    /// The rim's ink: the border's ink lifted once — a highlighted border — or,
    /// tinted, the tint lifted; lifted once more while `hovered`.
    ///
    /// The lift is ``Palette/hoveredForeground(_:)``, the step a hovered line
    /// takes, so it shows on every palette and at every colour depth.
    @MainActor
    func rimInk(hovered: Bool, in environment: EnvironmentValues) -> Color {
        let palette = environment.palette
        let surface = environment.enclosingSurface
        let highlight: Color
        if let tintColor {
            highlight = palette.hoveredForeground(tintColor.resolve(with: palette).spendingAlpha(over: surface))
        } else {
            highlight = _ButtonStyleBody.outlineInk(palette: palette, surface: surface, hovered: true, disabled: false)
        }
        return hovered ? palette.hoveredForeground(highlight) : highlight
    }
}
