//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuStyle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - MenuStyleConfiguration

/// The label and content of a ``Menu``, handed to a ``MenuStyle`` so it can
/// produce the menu's appearance — mirrors SwiftUI's `MenuStyleConfiguration`.
///
/// You don't create this type yourself; TUIkit builds one for each `Menu`.
public struct MenuStyleConfiguration {
    /// A type-erased view of the menu's label — its title, or whatever the
    /// caller built with the `label:` closure.
    public struct Label: View {
        let content: AnyView

        public var body: some View { content }
    }

    /// A type-erased view of the menu's items: the `Button`s and `Divider`s
    /// from the `content:` closure.
    public struct Content: View {
        let content: AnyView

        /// The items as separate children of whatever stack a style puts this
        /// in — see the ``ChildViewProvider`` conformance below. Captured in
        /// ``Menu`` where the items' concrete type is still known.
        let children: @MainActor (RenderContext) -> [ChildView]

        public var body: some View { content }
    }

    /// The menu's label.
    public let label: Label

    /// The menu's items.
    public let content: Content

    /// What a primary interaction with the menu does — `Menu`'s
    /// `primaryAction:` — or `nil` when the menu has none and every
    /// interaction opens it. Not public, as SwiftUI's configuration has no such
    /// member; the default style reads it, and `Menu(configuration)` carries
    /// it on.
    var primaryAction: (() -> Void)?
}

/// The items flatten into whatever stack a style places them in — SwiftUI
/// semantics, and the same flattening a conditional's branch gets: a `ForEach`
/// of `Button`s must contribute its rows to the menu's column, not arrive as
/// one opaque block. (A bare `ForEach` has no standalone rendering, so without
/// this the rows silently vanish — which is exactly what happened.)
///
/// The children are resolved through a closure captured in ``Menu``, where the
/// items' concrete type is still known: by the time they are here they have
/// been erased, and `AnyView` is not itself a child-view provider.
extension MenuStyleConfiguration.Content: ChildViewProvider {
    public func childViews(context: RenderContext) -> [ChildView] {
        children(context)
    }
}

// MARK: - MenuStyle

/// A type that applies a standard appearance to all menus within a view
/// hierarchy — mirrors SwiftUI's `MenuStyle`.
///
/// Set it with ``View/menuStyle(_:)``:
///
/// ```swift
/// Menu("Actions") {
///     Button("Rename") { rename() }
///     Button("Delete", role: .destructive) { delete() }
/// }
/// .menuStyle(.inline)
/// ```
///
/// ## Built-in styles
///
/// - ``DefaultMenuStyle`` (``automatic``) — a collapsed label that opens a
///   floating menu, the way a pop-up button behaves everywhere else.
/// - ``InlineMenuStyle`` (``inline``) — the items expanded in place under a
///   heading, always visible.
///
/// ## Styles and the render cache
///
/// ``View/menuStyle(_:)`` puts the style into the environment, and the render
/// cache keeps memoized subtrees honest by comparing each injected value with
/// the one applied there last frame. A value it cannot compare may have changed
/// under a buffer it is about to serve with nothing able to notice, so every
/// memo below one declines to cache at all.
///
/// Both built-in styles are therefore `Equatable`, as is the row styling a menu
/// injects around its items. Without that, nothing under a styled menu could be
/// memoized — which is every row of an inline menu, the shape a terminal app's
/// landing screen is usually made of. A custom style need not conform: one that
/// does not simply turns memoization off below itself, which costs render time
/// rather than correctness.
///
/// - Note: SwiftUI's `DefaultMenuStyle` declares no such conformance, and this
///   is one of the places a terminal renderer has to differ. SwiftUI diffs the
///   view graph the compiler builds for it and never has to ask whether an
///   environment value changed; TUIkit re-runs `body` and compares values, so
///   here the question must be answerable.
public protocol MenuStyle: Sendable {
    /// A view that represents the body of a menu.
    associatedtype Body: View

    /// Creates a view that represents the body of a menu.
    ///
    /// - Parameter configuration: The label and items of the menu being styled.
    /// - Returns: A view describing the menu's appearance.
    @MainActor @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    /// The label and content of a menu.
    typealias Configuration = MenuStyleConfiguration
}
