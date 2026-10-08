//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuStyle+Variants.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension MenuStyle {
    /// Renders this style's body for `configuration` into a frame buffer.
    ///
    /// Call sites hold the style as `any MenuStyle`; this opens the existential
    /// so ``makeBody(configuration:)`` can return its concrete ``Body``, which
    /// the renderer then resolves. (Same shape as `ButtonStyle.makeBuffer`.)
    @MainActor
    func makeBuffer(configuration: Configuration, context: RenderContext) -> FrameBuffer {
        renderToBuffer(makeBody(configuration: configuration), context: context)
    }

    /// Whether this style's body can answer its own size without being drawn.
    ///
    /// The same metatype check `ButtonStyle` makes, for the same reason: a
    /// `Layoutable` body has a `sizeThatFits`, so measuring it paints nothing,
    /// while a body without one would be rendered a level further down anyway.
    var bodyCanMeasureItself: Bool { Body.self is any Layoutable.Type }

    /// The size ``makeBuffer(configuration:context:)`` would come back as,
    /// without building it.
    ///
    /// Here rather than at the call site so `Body` stays concrete: erasing it to
    /// `AnyView` to measure would change the answer, because a flexible child
    /// measures to the full available width through `AnyView`.
    @MainActor
    func makeSize(
        configuration: Configuration, proposal: ProposedSize, context: RenderContext
    ) -> ViewSize {
        measureChild(makeBody(configuration: configuration), proposal: proposal, context: context)
    }
}

// MARK: - Built-in styles

/// The default menu style: a collapsed label that opens the items as a floating
/// menu, dismissed by Escape, by choosing an item, or by clicking outside.
///
/// Access this style with the ``MenuStyle/automatic`` static property.
public struct DefaultMenuStyle: MenuStyle, Equatable {
    /// Creates a default menu style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _MenuPopupCore(
            label: configuration.label, content: configuration.content,
            primaryAction: configuration.primaryAction)
    }
}

/// A menu style that displays a button that toggles the display of the menu's
/// contents when pressed.
///
/// What the default style draws here, as on macOS: a button with an arrow
/// showing it presents a menu, where pressing and dragging into the contents
/// chooses the item released on. The trigger is a ``Button``, so the button
/// style in force draws it.
///
/// Access this style with the ``MenuStyle/button`` static property.
public struct ButtonMenuStyle: MenuStyle, Equatable {
    /// Creates a button menu style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        DefaultMenuStyle().makeBody(configuration: configuration)
    }
}

/// A menu style that shows the items expanded in place, under the label as a
/// heading — nothing to open, everything visible.
///
/// Access this style with the ``MenuStyle/inline`` static property.
///
/// - Note: TUI-specific addition; SwiftUI has no inline menu style. A terminal
///   app's landing screen often *is* a menu, and it would be perverse to make
///   the user open the only thing on the page. Rendering it inline keeps that
///   screen a `Menu` — one API, one look, one set of keyboard shortcuts —
///   rather than a hand-built column of buttons.
public struct InlineMenuStyle: MenuStyle, Equatable {
    /// Creates an inline menu style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _InlineMenuCore(label: configuration.label, content: configuration.content)
    }
}

extension MenuStyle where Self == DefaultMenuStyle {
    /// The default menu style — a collapsed label that opens a floating menu.
    public static var automatic: DefaultMenuStyle { DefaultMenuStyle() }
}

extension MenuStyle where Self == ButtonMenuStyle {
    /// A menu style that displays a button that toggles the display of the
    /// menu's contents when pressed.
    public static var button: ButtonMenuStyle { ButtonMenuStyle() }
}

extension MenuStyle where Self == InlineMenuStyle {
    /// A menu style that shows its items expanded in place.
    public static var inline: InlineMenuStyle { InlineMenuStyle() }
}

// MARK: - Environment

private struct MenuStyleKey: EnvironmentKey {
    static let defaultValue = StyleChain<any MenuStyle>(DefaultMenuStyle())
}

extension EnvironmentValues {
    /// The menu style for this environment — see ``MenuStyle``. Set via
    /// ``View/menuStyle(_:)``. Default: ``DefaultMenuStyle``.
    ///
    /// Setting it puts a style in force over the one before, which a custom
    /// style's ``Menu/init(_:)`` then draws with.
    ///
    /// The render cache compares this value between frames to decide whether
    /// what it memoized below is still good, so a style that is not `Equatable`
    /// turns memoization off in its subtree — see ``MenuStyle``.
    public var menuStyle: any MenuStyle {
        get { self[MenuStyleKey.self].style }
        set { self[MenuStyleKey.self] = self[MenuStyleKey.self].pushing(newValue) }
    }

    /// The style in force and the ones outside it — what ``Menu/init(_:)``
    /// inside a custom style's body draws with. See ``StyleChain``.
    var menuStyleChain: StyleChain<any MenuStyle> {
        get { self[MenuStyleKey.self] }
        set { self[MenuStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for menus within this view.
    ///
    /// ```swift
    /// Menu("Demos") { … }
    ///     .menuStyle(.inline)
    /// ```
    ///
    /// - Parameter style: The menu style to apply.
    /// - Returns: A view whose menus use the specified style.
    public func menuStyle<S: MenuStyle>(_ style: S) -> some View {
        environment(\.menuStyle, style)
    }
}
