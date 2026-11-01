//  🖥️ TUI — A Terminal UI framework for Swift
//  SemanticShapeStyles.swift
//
//  SwiftUI's shape styles that name a role rather than a colour — `.primary`
//  through `.quinary`, `.foreground`, `.tint`, `.fill`, `.separator`,
//  `.placeholder`, `.link`, `.selection`, `.windowBackground` — resolved
//  against the environment where they are drawn, and the named colours spelled
//  as shape styles.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIStyling

// MARK: - Named colours

// SwiftUI declares these on `ShapeStyle where Self == Color`, which is what
// lets `.foregroundStyle(.red)` find `.red` on the generic overload. `Color`'s
// own statics stay; a member of the concrete type wins over the protocol's, so
// `Color.red` is unaffected.
//
// swiftlint:disable framework_colour_literal
// Forwarders to the colours an APP names, not ink the framework draws with.
extension ShapeStyle where Self == Color {
    /// A context-dependent red colour.
    public static var red: Color { Color.red }
    /// A context-dependent orange colour.
    public static var orange: Color { Color.orange }
    /// A context-dependent yellow colour.
    public static var yellow: Color { Color.yellow }
    /// A context-dependent green colour.
    public static var green: Color { Color.green }
    /// A context-dependent mint colour.
    public static var mint: Color { Color.mint }
    /// A context-dependent teal colour.
    public static var teal: Color { Color.teal }
    /// A context-dependent cyan colour.
    public static var cyan: Color { Color.cyan }
    /// A context-dependent blue colour.
    public static var blue: Color { Color.blue }
    /// A context-dependent indigo colour.
    public static var indigo: Color { Color.indigo }
    /// A context-dependent purple colour.
    public static var purple: Color { Color.purple }
    /// A context-dependent pink colour.
    public static var pink: Color { Color.pink }
    /// A context-dependent brown colour.
    public static var brown: Color { Color.brown }
    /// A white colour.
    public static var white: Color { Color.white }
    /// A context-dependent gray colour.
    public static var gray: Color { Color.gray }
    /// A black colour.
    public static var black: Color { Color.black }
    /// A clear colour.
    public static var clear: Color { Color.clear }
}
// swiftlint:enable framework_colour_literal

// MARK: - Hierarchical levels

private struct SecondaryForegroundStyleKey: EnvironmentKey {
    static let defaultValue: Paint? = nil
}

private struct TertiaryForegroundStyleKey: EnvironmentKey {
    static let defaultValue: Paint? = nil
}

extension EnvironmentValues {
    /// The secondary level ``View/foregroundStyle(_:_:)`` named, or `nil` to
    /// derive it from the primary.
    var secondaryForegroundStyle: Paint? {
        get { self[SecondaryForegroundStyleKey.self] }
        set { self[SecondaryForegroundStyleKey.self] = newValue }
    }

    /// The tertiary level ``View/foregroundStyle(_:_:_:)`` named, or `nil` to
    /// derive it.
    var tertiaryForegroundStyle: Paint? {
        get { self[TertiaryForegroundStyleKey.self] }
        set { self[TertiaryForegroundStyleKey.self] = newValue }
    }
}

/// A shape style that maps to one of the numbered content styles: the levels
/// of the current foreground style.
///
/// With no foreground style set, the levels are the palette's own tiers —
/// `foreground`, `foregroundSecondary`, `foregroundTertiary`,
/// `foregroundQuaternary`, and that at half strength — chosen per palette to
/// stay legible. Under a ``View/foregroundStyle(_:)-(S)``, the levels are that style
/// at falling opacity, as macOS's label colours are (1, 0.5, 0.26, 0.1, 0.05),
/// composited at the cell; ``View/foregroundStyle(_:_:)`` and
/// ``View/foregroundStyle(_:_:_:)`` name the second and third levels outright.
public struct HierarchicalShapeStyle: ShapeStyle, Equatable {
    /// Which level: 0 primary through 4 quinary.
    let level: Int

    public typealias Resolved = Never

    public func paint(in environment: EnvironmentValues) -> Paint {
        // Over a raised background — a list's focused, selected row — the
        // levels are the palette's own tiers, the inks the row's fill is chosen
        // to carry, whatever style the content inherited (`BackgroundProminence`).
        if environment.backgroundProminence == .increased {
            return Self.paletteTier(level, of: environment.palette)
        }
        // A named level answers for itself and fades for the levels past it.
        if level >= 2, let tertiary = environment.tertiaryForegroundStyle {
            return level == 2 ? tertiary : tertiary.faded(Self.opacities[level - 2])
        }
        if level >= 1, let secondary = environment.secondaryForegroundStyle {
            return level == 1 ? secondary : secondary.faded(Self.opacities[level - 1])
        }
        guard let primary = environment.foregroundStyle else {
            return Self.paletteTier(level, of: environment.palette)
        }
        return level == 0 ? primary : primary.faded(Self.opacities[level])
    }

    /// The palette's own text tier for `level`: what the levels are with no
    /// foreground style set, and over a raised background whatever is set.
    private static func paletteTier(_ level: Int, of palette: any Palette) -> Paint {
        switch level {
        case 0: .color(palette.foreground)
        case 1: .color(palette.foregroundSecondary)
        case 2: .color(palette.foregroundTertiary)
        case 3: .color(palette.foregroundQuaternary)
        default: .color(palette.foregroundQuaternary.opacity(0.5))
        }
    }

    /// Each level's strength against the one named at the top: macOS's label
    /// colours, whose alphas are these.
    static let opacities: [Double] = [1, 0.5, 0.26, 0.1, 0.05]
}

// SwiftUI declares the five on the type as well as on `ShapeStyle`: these are
// what `HierarchicalShapeStyle.secondary` names, and the ones below are what a
// leading dot finds where a generic style is expected.
extension HierarchicalShapeStyle {
    /// A shape style that maps to the first level of the current content style.
    public static let primary = HierarchicalShapeStyle(level: 0)
    /// A shape style that maps to the second level of the current content style.
    public static let secondary = HierarchicalShapeStyle(level: 1)
    /// A shape style that maps to the third level of the current content style.
    public static let tertiary = HierarchicalShapeStyle(level: 2)
    /// A shape style that maps to the fourth level of the current content style.
    public static let quaternary = HierarchicalShapeStyle(level: 3)
    /// A shape style that maps to the fifth level of the current content style.
    public static let quinary = HierarchicalShapeStyle(level: 4)
}

extension ShapeStyle where Self == HierarchicalShapeStyle {
    /// A shape style that maps to the first level of the current content style.
    public static var primary: HierarchicalShapeStyle { HierarchicalShapeStyle(level: 0) }
    /// A shape style that maps to the second level of the current content style.
    public static var secondary: HierarchicalShapeStyle { HierarchicalShapeStyle(level: 1) }
    /// A shape style that maps to the third level of the current content style.
    public static var tertiary: HierarchicalShapeStyle { HierarchicalShapeStyle(level: 2) }
    /// A shape style that maps to the fourth level of the current content style.
    public static var quaternary: HierarchicalShapeStyle { HierarchicalShapeStyle(level: 3) }
    /// A shape style that maps to the fifth level of the current content style.
    public static var quinary: HierarchicalShapeStyle { HierarchicalShapeStyle(level: 4) }
}

/// A style that is another style at one of the content levels: `.red.secondary`
/// is red at the strength `.secondary` is against `.primary`.
public struct HierarchicalShapeStyleModifier<Base: ShapeStyle>: ShapeStyle {
    let base: Base
    let level: Int

    public typealias Resolved = Never

    public func paint(in environment: EnvironmentValues) -> Paint {
        base.paint(in: environment).faded(HierarchicalShapeStyle.opacities[level])
    }
}

extension HierarchicalShapeStyleModifier: Equatable where Base: Equatable {}

extension ShapeStyle {
    /// Returns the second level of this shape style.
    public var secondary: some ShapeStyle { HierarchicalShapeStyleModifier(base: self, level: 1) }
    /// Returns the third level of this shape style.
    public var tertiary: some ShapeStyle { HierarchicalShapeStyleModifier(base: self, level: 2) }
    /// Returns the fourth level of this shape style.
    public var quaternary: some ShapeStyle { HierarchicalShapeStyleModifier(base: self, level: 3) }
    /// Returns the fifth level of this shape style.
    public var quinary: some ShapeStyle { HierarchicalShapeStyleModifier(base: self, level: 4) }
}

extension View {
    /// Sets the primary and secondary levels of the foreground style in the
    /// child view.
    ///
    /// `.secondary` below resolves to `secondary`; `.tertiary` and below are
    /// it at falling opacity.
    ///
    /// - Parameters:
    ///   - primary: The primary style to use within the view.
    ///   - secondary: The secondary style to use within the view.
    /// - Returns: A view that uses the given styles.
    nonisolated public func foregroundStyle<S1: ShapeStyle, S2: ShapeStyle>(_ primary: S1, _ secondary: S2) -> some View {
        _StyleEnvironmentView(
            content: _StyleEnvironmentView(
                content: self, style: secondary, slot: \.secondaryForegroundStyle, fades: true),
            style: primary, slot: \.foregroundStyle, fades: true, clearsLevels: true)
    }

    /// Sets the primary, secondary, and tertiary levels of the foreground style
    /// in the child view.
    ///
    /// - Parameters:
    ///   - primary: The primary style to use within the view.
    ///   - secondary: The secondary style to use within the view.
    ///   - tertiary: The tertiary style to use within the view.
    /// - Returns: A view that uses the given styles.
    nonisolated public func foregroundStyle<S1: ShapeStyle, S2: ShapeStyle, S3: ShapeStyle>(
        _ primary: S1, _ secondary: S2, _ tertiary: S3
    ) -> some View {
        _StyleEnvironmentView(
            content: _StyleEnvironmentView(
                content: _StyleEnvironmentView(
                    content: self, style: tertiary, slot: \.tertiaryForegroundStyle, fades: true),
                style: secondary, slot: \.secondaryForegroundStyle, fades: true),
            style: primary, slot: \.foregroundStyle, fades: true, clearsLevels: true)
    }
}

// MARK: - Roles

/// The foreground style in the current context: what text and symbols are
/// drawn in — the style a ``View/foregroundStyle(_:)-(S)`` set, or the palette's
/// foreground.
public struct ForegroundStyle: ShapeStyle, Equatable {
    /// Creates a foreground style instance.
    public init() {}

    public typealias Resolved = Never

    public func paint(in environment: EnvironmentValues) -> Paint {
        environment.foregroundStyle ?? .color(environment.palette.foreground)
    }
}

/// A style that reflects the current tint: the ``View/tint(_:)-(S?)`` in force
/// as it was stated — a gradient as its ramp — or the palette's accent.
public struct TintShapeStyle: ShapeStyle, Equatable {
    /// Creates a tint shape style.
    public init() {}

    public typealias Resolved = Never

    public func paint(in environment: EnvironmentValues) -> Paint {
        environment.tintPaint ?? (environment.tint ?? Color.palette.accent).paint(in: environment)
    }
}

/// An overlay fill style for filling shapes: the palette's field surface, the
/// quiet fill a text field sits on.
public struct FillShapeStyle: ShapeStyle, Equatable {
    /// Creates a fill shape style.
    public init() {}

    public typealias Resolved = Never

    public func paint(in environment: EnvironmentValues) -> Paint {
        .color(environment.palette.fieldBackground)
    }
}

/// A style appropriate for foreground separator or border lines: the palette's
/// border colour.
public struct SeparatorShapeStyle: ShapeStyle, Equatable {
    /// Creates a separator shape style.
    public init() {}

    public typealias Resolved = Never

    public func paint(in environment: EnvironmentValues) -> Paint {
        .color(environment.palette.border)
    }
}

/// A style appropriate for placeholder text: the palette's tertiary
/// foreground, as a field's prompt is drawn.
public struct PlaceholderTextShapeStyle: ShapeStyle, Equatable {
    /// Creates a placeholder text shape style.
    public init() {}

    public typealias Resolved = Never

    public func paint(in environment: EnvironmentValues) -> Paint {
        .color(environment.palette.foregroundTertiary)
    }
}

/// A style appropriate for links: the accent, as a ``Link`` is drawn.
public struct LinkShapeStyle: ShapeStyle, Equatable {
    /// Creates a link shape style.
    public init() {}

    public typealias Resolved = Never

    public func paint(in environment: EnvironmentValues) -> Paint {
        .color(environment.palette.accent)
    }
}

/// A style used to visually indicate selection following platform conventional
/// colours and behaviours: the tint in force, or the accent — what a selected
/// row is drawn in.
///
/// As a background — ``View/background(_:)-(S)``, ``View/background(_:in:fillStyle:)``,
/// erased in an ``AnyShapeStyle`` or not — it raises
/// ``EnvironmentValues/backgroundProminence`` for the content drawn over it,
/// so the content styles there resolve to the palette's text tiers, the inks
/// the fill is chosen to carry, as they do on a list's selected row.
public struct SelectionShapeStyle: ShapeStyle, Equatable {
    /// Creates a selection shape style.
    public init() {}

    public typealias Resolved = Never

    public func paint(in environment: EnvironmentValues) -> Paint {
        (environment.tint ?? Color.palette.accent).paint(in: environment)
    }
}

/// The selection's fill is the vivid one content has to keep its contrast on.
extension SelectionShapeStyle: BackgroundProminenceRaising {
    package var raisesBackgroundProminence: Bool { true }
}

/// A style appropriate for the window's background: the palette's page
/// colour.
public struct WindowBackgroundShapeStyle: ShapeStyle, Equatable {
    /// Creates a window background shape style.
    public init() {}

    public typealias Resolved = Never

    public func paint(in environment: EnvironmentValues) -> Paint {
        .color(environment.palette.background)
    }
}

extension ShapeStyle where Self == ForegroundStyle {
    /// The foreground style in the current context.
    public static var foreground: ForegroundStyle { ForegroundStyle() }
}

extension ShapeStyle where Self == TintShapeStyle {
    /// A style that reflects the current tint colour.
    public static var tint: TintShapeStyle { TintShapeStyle() }
}

extension ShapeStyle where Self == FillShapeStyle {
    /// An overlay fill style for filling shapes.
    public static var fill: FillShapeStyle { FillShapeStyle() }
}

extension ShapeStyle where Self == SeparatorShapeStyle {
    /// A style appropriate for foreground separator or border lines.
    public static var separator: SeparatorShapeStyle { SeparatorShapeStyle() }
}

extension ShapeStyle where Self == PlaceholderTextShapeStyle {
    /// A style appropriate for placeholder text.
    public static var placeholder: PlaceholderTextShapeStyle { PlaceholderTextShapeStyle() }
}

extension ShapeStyle where Self == LinkShapeStyle {
    /// A style appropriate for links.
    public static var link: LinkShapeStyle { LinkShapeStyle() }
}

extension ShapeStyle where Self == SelectionShapeStyle {
    /// A style used to visually indicate selection.
    public static var selection: SelectionShapeStyle { SelectionShapeStyle() }
}

extension ShapeStyle where Self == WindowBackgroundShapeStyle {
    /// A style appropriate for the window's background.
    public static var windowBackground: WindowBackgroundShapeStyle { WindowBackgroundShapeStyle() }
}
