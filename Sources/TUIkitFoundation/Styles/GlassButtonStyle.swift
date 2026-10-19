//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GlassButtonStyle.swift
//
//  SwiftUI's glass button styles: the bordered button, its lines the glass's
//  highlighted rim, on glass.
//
//  Created by Wade Tregaskis
//  License: MIT

/// A button style that applies glass border artwork based on the button's
/// context — mirrors SwiftUI's `GlassButtonStyle`.
///
/// The bordered button of the appearance and border shape in force — its
/// caps, its box at the larger control sizes — on a glass in the button's
/// border shape (``View/glassEffect(_:in:)``): where the face is lines, the
/// lines are the glass's highlighted rim, and the label sits on the glass's
/// surface; where it is solid (`.block`), the face is the bordered button's
/// own. It focuses, hovers and presses as a bordered button does.
///
/// ```swift
/// Button("Button") {}
///     .buttonStyle(.glass)
///
/// Button("Button") {}
///     .buttonStyle(.glass(.clear))
/// ```
///
/// `Equatable`, unlike SwiftUI's: a style the render memo cannot compare turns
/// memoization off below it (see ``ButtonStyle``).
///
/// You can also use ``PrimitiveButtonStyle/glass`` to construct this style.
public struct GlassButtonStyle: PrimitiveButtonStyle, Equatable {
    /// The glass the button sits on.
    let glass: Glass

    /// Creates a glass button style.
    public init() {
        glass = .regular
    }

    /// Creates a glass button style on `glass` — ``Glass/clear`` for the clear
    /// variant, or a tinted glass.
    ///
    /// - Parameter glass: The glass the button sits on.
    public init(_ glass: Glass) {
        self.glass = glass
    }

    /// Creates a view that represents the body of a button: the button, drawn
    /// with the glass appearance, on its glass.
    ///
    /// - Parameter configuration: The properties of the button.
    public func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .environment(\.installedButtonAppearance, _AppearanceButtonStyle(appearance: .glass(glass)))
            .glassEffect(glass, in: .buttonBorder)
    }
}

/// A button style that applies prominent glass border artwork based on the
/// button's context — mirrors SwiftUI's `GlassProminentButtonStyle`.
///
/// The glass button on glass tinted the accent, its label bold in the
/// palette's foreground — the prominent button of the glass family, as
/// ``BorderedProminentButtonStyle`` is of the bordered one.
///
/// You can also use ``PrimitiveButtonStyle/glassProminent`` to construct this
/// style.
public struct GlassProminentButtonStyle: PrimitiveButtonStyle, Equatable {
    /// Creates a prominent glass button style.
    public init() {}

    /// The accent-tinted glass the button sits on.
    private var glass: Glass { .regular.tint(.palette.accent) }

    /// Creates a view that represents the body of a button: the button, drawn
    /// with the prominent glass appearance, on accent-tinted glass.
    ///
    /// - Parameter configuration: The properties of the button.
    public func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .environment(\.installedButtonAppearance, _AppearanceButtonStyle(appearance: .glassProminent(glass)))
            .glassEffect(glass, in: .buttonBorder)
    }
}

extension PrimitiveButtonStyle where Self == GlassButtonStyle {
    /// A button style that applies glass border artwork based on the button's
    /// context.
    ///
    /// To apply this style to a button, or to a view that contains buttons,
    /// use the `buttonStyle(_:)` modifier.
    public static var glass: GlassButtonStyle { GlassButtonStyle() }

    /// A button style that applies a configurable glass border artwork based
    /// on the button's context.
    ///
    /// ```swift
    /// Button("Button") {}
    ///     .buttonStyle(.glass(.clear))
    /// ```
    ///
    /// - Parameter glass: The glass the button sits on.
    /// - Returns: The style.
    public static func glass(_ glass: Glass) -> Self {
        GlassButtonStyle(glass)
    }
}

extension PrimitiveButtonStyle where Self == GlassProminentButtonStyle {
    /// A button style that applies prominent glass border artwork based on the
    /// button's context.
    ///
    /// To apply this style to a button, or to a view that contains buttons,
    /// use the `buttonStyle(_:)` modifier.
    public static var glassProminent: GlassProminentButtonStyle { GlassProminentButtonStyle() }
}

extension _ButtonAppearance {
    /// The glass button's appearance: the bordered one, its lines `glass`'s
    /// rim.
    static func glass(_ glass: Glass) -> Self {
        var appearance = Self.default
        appearance.glassRim = glass
        return appearance
    }

    /// The prominent glass button's appearance: a bold label in the palette's
    /// foreground — legible on the accent-tinted glass, where the accent itself
    /// would not be — its lines `glass`'s rim. Scoped as the bordered prominent
    /// button is (`.controlVariant(.button, "primary")`).
    static func glassProminent(_ glass: Glass) -> Self {
        var appearance = Self(
            foregroundColor: Color.palette.foreground, isBold: true, horizontalPadding: 1, isPlain: false,
            variant: "primary")
        appearance.glassRim = glass
        return appearance
    }
}
