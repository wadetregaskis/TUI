//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Material.swift
//
//  SwiftUI's materials, as a terminal can have them: a translucent palette
//  surface, composited over whatever is behind it (refusal review O5, ruled
//  2026-10-12: option (b)).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

/// A background material type — mirrors SwiftUI's `Material`.
///
/// SwiftUI's materials blur what is behind them and tint it. A cell grid has
/// nothing to blur below a cell, so a material here is the other half alone: a
/// palette surface at a fraction of its opacity, composited cell by cell over
/// what it covers. What shows through is tinted toward the surface, and the
/// glyphs behind stay where they are — the translucency of a material, without
/// its frosting.
///
/// The five thicknesses are five opacities, ``ultraThin`` the most see-through
/// and ``ultraThick`` the least. ``bar`` is the surface of the palette's bars
/// (``Palette/statusBarBackground``) rather than of the page.
///
/// A material that does not appear active is opaque: SwiftUI's materials go
/// flat in an inactive window, and here that is the surface at full strength.
/// Whether one appears active is ``MaterialActiveAppearance``'s to say — by
/// default whether the scene does (``EnvironmentValues/appearsActive``).
///
/// ```swift
/// ZStack {
///     LogView()
///     Text("Paused").padding().background(.thinMaterial)
/// }
/// ```
///
/// `Equatable`, as SwiftUI's is not: an environment value or a style the
/// render memo cannot compare turns memoization off below it.
public struct Material: Sendable, Equatable, Hashable {
    /// How much of the surface it is: the opacity of its fill while it
    /// appears active.
    let opacity: Double

    /// Whether this is a bar's material rather than the page's.
    let isBar: Bool

    /// The appearance this material asked for, ``MaterialActiveAppearance/automatic``
    /// to take the environment's.
    let activeAppearance: MaterialActiveAppearance

    private init(opacity: Double, isBar: Bool = false, activeAppearance: MaterialActiveAppearance = .automatic) {
        self.opacity = opacity
        self.isBar = isBar
        self.activeAppearance = activeAppearance
    }

    /// A material that's somewhat translucent.
    public static let regular = Self(opacity: 0.65)

    /// A material that's more opaque than translucent.
    public static let thick = Self(opacity: 0.8)

    /// A material that's more translucent than opaque.
    public static let thin = Self(opacity: 0.5)

    /// A mostly translucent material.
    public static let ultraThin = Self(opacity: 0.35)

    /// A mostly opaque material.
    public static let ultraThick = Self(opacity: 0.92)

    /// A material matching the style of system toolbars — here the palette's
    /// bar surface, at a ``thick`` material's opacity.
    public static let bar = Self(opacity: 0.8, isBar: true)

    /// This material, appearing active or not as `appearance` says — mirrors
    /// SwiftUI's `Material.materialActiveAppearance(_:)`.
    public func materialActiveAppearance(_ appearance: MaterialActiveAppearance) -> Self {
        Self(opacity: opacity, isBar: isBar, activeAppearance: appearance)
    }
}

extension Material: ShapeStyle {
    public typealias Resolved = Never

    /// The surface, at this material's opacity while it appears active and
    /// opaque while it does not.
    ///
    /// The colour stays semantic, so the material follows a palette change as
    /// every palette colour does.
    public func paint(in environment: EnvironmentValues) -> Paint {
        .color(surface(isBar ? Color.palette.statusBarBackground : Color.palette.background, in: environment))
    }

    /// `surface` as this material paints it in `environment`: at the
    /// material's opacity while it appears active, and at full strength while
    /// it does not.
    ///
    /// - Parameters:
    ///   - surface: The colour the material is made of.
    ///   - environment: Where it is painted, for its active appearance.
    /// - Returns: The colour to paint.
    func surface(_ surface: Color, in environment: EnvironmentValues) -> Color {
        let appearance = activeAppearance == .automatic ? environment.materialActiveAppearance : activeAppearance
        return appearance.appearsActive(in: environment) ? surface.opacity(opacity) : surface
    }
}

extension ShapeStyle where Self == Material {
    /// A material that's somewhat translucent.
    public static var regularMaterial: Material { .regular }

    /// A material that's more opaque than translucent.
    public static var thickMaterial: Material { .thick }

    /// A material that's more translucent than opaque.
    public static var thinMaterial: Material { .thin }

    /// A mostly translucent material.
    public static var ultraThinMaterial: Material { .ultraThin }

    /// A mostly opaque material.
    public static var ultraThickMaterial: Material { .ultraThick }

    /// A material matching the style of system toolbars.
    public static var bar: Material { .bar }
}

// MARK: - Active Appearance

/// Whether a material appears active — mirrors SwiftUI's
/// `MaterialActiveAppearance`.
///
/// An active material is translucent; an inactive one is its surface at full
/// strength. ``automatic`` and ``matchWindow`` follow
/// ``EnvironmentValues/appearsActive``, which is the scene's — and a terminal
/// says whether its window is active only where it reports focus (DEC 1004),
/// so most of the time a material simply appears active.
public struct MaterialActiveAppearance: Sendable, Equatable, Hashable {
    private enum Kind: Hashable { case automatic, active, inactive, matchWindow }

    private let kind: Kind

    /// The appearance the context gives: the environment's, and at the root,
    /// the window's.
    public static let automatic = Self(kind: .automatic)

    /// Always active: translucent, whatever the window is doing.
    public static let active = Self(kind: .active)

    /// Always inactive: opaque.
    public static let inactive = Self(kind: .inactive)

    /// Active while the window is (``EnvironmentValues/appearsActive``).
    public static let matchWindow = Self(kind: .matchWindow)

    /// Whether a material with this appearance draws as active in `environment`.
    func appearsActive(in environment: EnvironmentValues) -> Bool {
        switch kind {
        case .active: true
        case .inactive: false
        case .automatic, .matchWindow: environment.appearsActive
        }
    }
}

private struct MaterialActiveAppearanceKey: EnvironmentKey {
    static let defaultValue = MaterialActiveAppearance.automatic
}

private struct BackgroundMaterialKey: EnvironmentKey {
    static let defaultValue: Material? = nil
}

extension EnvironmentValues {
    /// The active appearance materials in this subtree take — mirrors
    /// SwiftUI's property of the same name. ``MaterialActiveAppearance/automatic``
    /// by default, which follows ``appearsActive``.
    public var materialActiveAppearance: MaterialActiveAppearance {
        get { self[MaterialActiveAppearanceKey.self] }
        set { self[MaterialActiveAppearanceKey.self] = newValue }
    }

    /// The material views in this subtree sit on, where something says so —
    /// mirrors SwiftUI's property of the same name. `nil` by default.
    ///
    /// SwiftUI's own containers set it, for the vibrancy their content draws
    /// with; TUIkit's draw no vibrancy and set nothing, so it is the app's to
    /// set and read.
    public var backgroundMaterial: Material? {
        get { self[BackgroundMaterialKey.self] }
        set { self[BackgroundMaterialKey.self] = newValue }
    }
}

extension ShapeStyle {
    /// This style, with the materials in it appearing active or not as
    /// `appearance` says — mirrors SwiftUI's
    /// `ShapeStyle.materialActiveAppearance(_:)`.
    public func materialActiveAppearance(_ appearance: MaterialActiveAppearance) -> some ShapeStyle {
        _MaterialActiveAppearanceStyle(base: self, appearance: appearance)
    }
}

/// ``ShapeStyle/materialActiveAppearance(_:)``'s style: its base, painted in
/// an environment whose materials take `appearance`.
struct _MaterialActiveAppearanceStyle<Base: ShapeStyle>: ShapeStyle {
    let base: Base
    let appearance: MaterialActiveAppearance

    typealias Resolved = Never

    func paint(in environment: EnvironmentValues) -> Paint {
        var environment = environment
        environment.materialActiveAppearance = appearance
        return base.paint(in: environment)
    }
}

extension View {
    /// Sets the active appearance of the materials in this view — mirrors
    /// SwiftUI's `View.materialActiveAppearance(_:)`.
    public func materialActiveAppearance(_ appearance: MaterialActiveAppearance) -> some View {
        environment(\.materialActiveAppearance, appearance)
    }
}
