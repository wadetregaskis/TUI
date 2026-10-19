//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ShapeStyle+Shadow.swift
//
//  `ShapeStyle.shadow(_:)`: a style drawn with a drop or an inner shadow, cast
//  by whatever draws with it from the cells it drew.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension ShapeStyle {
    /// Applies the specified shadow effect to the shape style.
    ///
    /// Mirrors SwiftUI's `ShapeStyle.shadow(_:)`. Whatever draws with the
    /// style draws it as it would, and casts the shadow from the cells it drew
    /// with it: a shape's fill or stroke, a `.background(_:)`'s fill, the
    /// letters of a `Text` under a `.foregroundStyle(_:)`, a template image's
    /// picture.
    ///
    /// ```swift
    /// Rectangle().fill(.red.shadow(.drop(radius: 1, x: 1, y: 1)))
    ///
    /// Text("Pressed")
    ///     .padding(1)
    ///     .background(.blue.shadow(.inner(radius: 1, x: 1, y: 1)))
    /// ```
    ///
    /// A drop shadow is drawn beneath what the style paints and an inner one
    /// over it — over a background's fill and under the content in front of
    /// it, as SwiftUI draws them. Several shadows, `.red.shadow(a).shadow(b)`,
    /// are each cast from what the style paints, not from one another, and a
    /// style at half strength casts its shadows at half, whichever side of the
    /// shadow the fade is written (`.red.opacity(0.5).shadow(s)` or
    /// `.red.shadow(s).opacity(0.5)`): both measured on macOS 15.8
    /// (`Tools/SwiftUIProbes/Shadowed shape styles/`). The shadow is in cells,
    /// as every ``ShadowStyle`` is (`Deliberate deviations from SwiftUI.md`,
    /// C10).
    ///
    /// - Parameter style: The shadow style to apply.
    /// - Returns: A new shape style that uses the specified shadow style.
    public func shadow(_ style: ShadowStyle) -> some ShapeStyle {
        _ShadowShapeStyle(base: self, shadow: style)
    }
}

extension ShapeStyle where Self == AnyShapeStyle {
    /// Returns a shape style that applies the specified shadow style to the
    /// current style.
    ///
    /// Mirrors SwiftUI's static `ShapeStyle.shadow(_:)`. In most contexts the
    /// current style is the foreground; where a background style is being set
    /// (``View/backgroundStyle(_:)-(S)``) it is the background style in force
    /// there — both measured on macOS 15.8
    /// (`Tools/SwiftUIProbes/Shadowed shape styles/shadowstyle.swift`, Q1, Q2).
    ///
    /// ```swift
    /// Circle().fill(.shadow(.inner(radius: 1, y: 1)))
    /// ```
    ///
    /// - Parameter style: The shadow style to apply.
    /// - Returns: A new shape style based on the current style that uses the
    ///   specified shadow style.
    public static func shadow(_ style: ShadowStyle) -> some ShapeStyle {
        _ShadowShapeStyle(base: _ImplicitShapeStyle(), shadow: style)
    }
}

/// ``ShapeStyle/shadow(_:)``'s style: its base's paint, with the shadow.
struct _ShadowShapeStyle<Base: ShapeStyle>: ShapeStyle {
    let base: Base
    let shadow: ShadowStyle

    typealias Resolved = Never

    func paint(in environment: EnvironmentValues) -> Paint {
        .shadowed(base.paint(in: environment), shadow)
    }
}

/// The current style, where a style names none of its own — the static
/// ``ShapeStyle/shadow(_:)``'s base: the foreground style, except while a
/// background style is being set, where it is the background style above.
struct _ImplicitShapeStyle: ShapeStyle {
    typealias Resolved = Never

    func paint(in environment: EnvironmentValues) -> Paint {
        environment.implicitStyleIsBackground
            ? BackgroundStyle().paint(in: environment) : ForegroundStyle().paint(in: environment)
    }
}

private struct ImplicitStyleIsBackgroundKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the current style (``ShapeStyle/shadow(_:)``'s static form) is
    /// the background style: true only while ``View/backgroundStyle(_:)-(S)``
    /// resolves the style it publishes.
    var implicitStyleIsBackground: Bool {
        get { self[ImplicitStyleIsBackgroundKey.self] }
        set { self[ImplicitStyleIsBackgroundKey.self] = newValue }
    }
}
