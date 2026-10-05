//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContainerBackground.swift
//
//  `containerBackground(_:for:)` and `containerBackground(for:alignment:content:)`:
//  a background for the enclosing container rather than for the view — on
//  macOS, for the window, which is the one placement SwiftUI has there.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

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
struct ContainerBackground {
    /// The background, type-erased.
    let view: AnyView

    /// Where the background goes in the container, if it does not fill it.
    let alignment: Alignment
}

/// The window background the content published. The last one set wins — the
/// default `reduce` — as SwiftUI leaves unspecified which of several does.
struct ContainerBackgroundKey: PreferenceKey {
    static let defaultValue: ContainerBackground? = nil
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

/// `content`, a buffer rendered for the scene's content area, centred in it
/// over `background`, which fills the area or is placed in it by its
/// alignment.
///
/// The background renders at an identity of its own under the scene's, so its
/// `@State` is its own. Every cell the content names no field for shows the
/// background's — `.background(alignment:content:)`'s rule, one container out.
@MainActor
func windowContent(
    _ content: FrameBuffer, over background: ContainerBackground, context: RenderContext
) -> FrameBuffer {
    let width = max(0, context.availableWidth)
    let height = max(0, context.availableHeight)
    let backgroundBuffer = TUIkit.renderToBuffer(
        background.view,
        context: context.withChildIdentity(type: ContainerBackgroundPlacement.self, index: 1))

    let palette = context.environment.palette
    var result = FrameBuffer(emptyWithWidth: width, height: height)
    result.compositeCarryingClaimsOverNothing(
        with: backgroundBuffer,
        at: (
            x: background.alignment.horizontal.childOffset(childWidth: backgroundBuffer.width, in: width),
            y: background.alignment.vertical.childOffset(childHeight: backgroundBuffer.height, in: height)),
        palette: palette)
    // Centred as `WindowGroup` centres its content with no background.
    let showingThrough = result.runsShowingThrough(
        content, at: (x: max(0, (width - content.width) / 2), y: max(0, (height - content.height) / 2)))
    if !showingThrough.isEmpty {
        context.requestWake(
            token: "container-background-run-\(context.identity.path)",
            forNextStepOf: showingThrough.map { ($0.clock, $0.frameTicks) })
    }
    result.compositeCarryingClaimsOverNothing(
        with: content, at: (x: max(0, (width - content.width) / 2), y: max(0, (height - content.height) / 2)),
        palette: palette)
    return result.clamped(toWidth: width, height: height)
}
