//  🖥️ TUI — A Terminal UI framework for Swift
//  ContainerBackground.swift
//
//  `containerBackground(_:for:)` and `containerBackground(for:alignment:content:)`:
//  a background for the enclosing container rather than for the view — on
//  macOS, for the window, which is the one placement SwiftUI has there.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// The placement of a container background.
public struct ContainerBackgroundPlacement: Hashable, Sendable {
    /// Which container the background fills.
    private let container: Int

    /// A background placement inside a `Window` or ``WindowGroup``: the whole
    /// content area the scene lays its content out in. The window's bars
    /// keep their own surfaces.
    public static let window = Self(container: 0)
}

/// A container background a view published: the view, and where it goes in
/// the container.
package struct ContainerBackground {
    /// The background, type-erased.
    package let view: AnyView

    /// Where the background goes in the container, if it does not fill it.
    package let alignment: Alignment
}

/// The window background the content published. The last one set wins — the
/// default `reduce` — as SwiftUI leaves unspecified which of several does.
package struct ContainerBackgroundKey: PreferenceKey {
    package static var defaultValue: ContainerBackground? { nil }
}

extension View {
    /// Sets the container background of the enclosing container using a view.
    ///
    /// ```swift
    /// ContentView()
    ///     .containerBackground(for: .window) {
    ///         LinearGradient(colors: [.blue, .black], startPoint: .top, endPoint: .bottom)
    ///     }
    /// ```
    ///
    /// The background fills the window's content area — under the content,
    /// which stays centred in it — not just this view's frame.
    ///
    /// - Parameters:
    ///   - container: The container that gets the background.
    ///   - alignment: Where the background goes if it does not fill the
    ///     container. Default `.center`.
    ///   - content: The background.
    /// - Returns: A view that sets its container's background.
    public func containerBackground<V: View>(
        for container: ContainerBackgroundPlacement, alignment: Alignment = .center,
        @ViewBuilder content: () -> V
    ) -> some View {
        preference(
            key: ContainerBackgroundKey.self,
            value: ContainerBackground(view: AnyView(content()), alignment: alignment))
    }

    /// Sets the container background of the enclosing container using a
    /// style — a colour, or any gradient.
    ///
    /// - Parameters:
    ///   - style: The style to fill the container with.
    ///   - container: The container that gets the background.
    /// - Returns: A view that sets its container's background.
    public func containerBackground<S: ShapeStyle>(
        _ style: S, for container: ContainerBackgroundPlacement
    ) -> some View {
        // A style as a view: a fill block painted with it, as a gradient used
        // as a view is.
        containerBackground(for: container) { _StyleFillBlock().background(style) }
    }
}
