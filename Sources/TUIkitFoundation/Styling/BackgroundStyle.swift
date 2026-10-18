//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BackgroundStyle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

// MARK: - BackgroundStyle

/// The style a view's background takes when nothing else names one —
/// SwiftUI's `BackgroundStyle`, and what `.background()` and
/// `.foregroundStyle(.background)` resolve to.
///
/// It reads ``EnvironmentValues/backgroundStyle``, so an app can restyle every
/// background beneath a subtree at once:
///
/// ```swift
/// Panel { … }
///     .backgroundStyle(.rgb(20, 24, 34))   // names it
/// Text("Total").padding().background()     // paints it
/// ```
///
/// With nothing named it is the palette's own ``Palette/background`` — which
/// is a terminal's equivalent of SwiftUI's system background material, and the
/// closest thing a cell grid has to one. A ``Material`` is the same surface,
/// translucent, for a view that should let what is behind it show through.
public struct BackgroundStyle: ShapeStyle, Equatable, Sendable {
    /// Creates the background style.
    public init() {}

    public typealias Resolved = Never

    public func paint(in environment: EnvironmentValues) -> Paint {
        environment.backgroundStyle ?? .color(environment.palette.background)
    }
}

extension ShapeStyle where Self == BackgroundStyle {
    /// `.background` — the surface style, wherever a style is taken:
    /// `.foregroundStyle(.background)` draws ink in it, `.background(.background)`
    /// fills with it, and ``View/background()`` is the shorthand for the second.
    public static var background: Self { .init() }
}
