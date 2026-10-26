//  🖥️ TUI — A Terminal UI framework for Swift
//  NavigationTransition.swift
//
//  `navigationTransition(_:)`, in the transitions a terminal's navigation
//  has: the automatic one, and a zoom from a matched transition source.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

/// A type that defines the transition to use when navigating to a view.
/// Mirrors SwiftUI's `NavigationTransition`.
///
/// ``automatic`` is the transition a ``NavigationStack`` makes: the screen is
/// replaced and the crumb trail updated, in the frame the path changes.
/// ``zoom(sourceID:in:)`` reveals the screen pushed from the view marked as
/// its source with ``View/matchedTransitionSource(id:in:)``, and folds it back
/// into that view when it is popped.
public protocol NavigationTransition {}

/// The default navigation transition. Mirrors SwiftUI's
/// `AutomaticNavigationTransition`.
public struct AutomaticNavigationTransition: NavigationTransition {
    /// A style that automatically chooses the appropriate transition for the
    /// current context: the one ``NavigationStack`` makes.
    public static var automatic: Self { Self() }
}

extension NavigationTransition where Self == AutomaticNavigationTransition {
    /// A style that automatically chooses the appropriate presentation
    /// transition for the current context.
    public static var automatic: AutomaticNavigationTransition { AutomaticNavigationTransition() }
}

/// A navigation transition that zooms the appearing view from a given source
/// view. Mirrors SwiftUI's `ZoomNavigationTransition` (iOS 18; SwiftUI marks it
/// unavailable on macOS, where nothing zooms).
///
/// Indicate the source view using the ``View/matchedTransitionSource(id:in:)``
/// modifier.
///
/// ## In a terminal
///
/// A cell cannot be scaled, so the zoom is a reveal (refusal review O4): the
/// pushed screen, laid out at its full size, is uncovered through a rectangle
/// that grows from the source view's frame to the whole stack, over the screen
/// it is replacing; popped, the rectangle shrinks back into the source over
/// the screen it returns to. The source's
/// ``MatchedTransitionSourceConfiguration/background(_:)`` fills the
/// rectangle behind it. It plays under the change's animation, or
/// ``Animation/default`` where the change has none — a push is animated in
/// SwiftUI whether or not the code that pushed asked for it — and not at all
/// where the transaction disables animations or motion is reduced. With no
/// source on screen to zoom from, the stack changes at once, as for
/// ``NavigationTransition/automatic``.
public struct ZoomNavigationTransition: NavigationTransition {
    /// The source's group: its namespace, and its id wrapped as a transition
    /// source's (``MatchedTransitionSourceID``).
    let source: MatchedGeometryKey
}

/// Not `Sendable`, as SwiftUI's is not (its conformance is explicitly
/// unavailable).
@available(*, unavailable)
extension ZoomNavigationTransition: Sendable {}

extension NavigationTransition where Self == ZoomNavigationTransition {
    /// A navigation transition that zooms the appearing view from a given
    /// source view.
    ///
    /// Indicate the source view using the
    /// ``View/matchedTransitionSource(id:in:)`` modifier.
    ///
    /// - Parameters:
    ///   - sourceID: The identifier you provide to a corresponding
    ///     `matchedTransitionSource` modifier.
    ///   - namespace: The namespace where you define the `id`. You can create
    ///     new namespaces by adding the ``Namespace`` attribute to a ``View``
    ///     type, then reading its value in the view's body method.
    /// - Returns: A zoom navigation transition.
    public static func zoom(sourceID: some Hashable, in namespace: Namespace.ID) -> ZoomNavigationTransition {
        ZoomNavigationTransition(source: MatchedTransitionSourceID.key(sourceID, in: namespace))
    }
}

extension View {
    /// Sets the navigation transition style for this view. Mirrors SwiftUI's
    /// `navigationTransition(_:)`.
    ///
    /// Written on the view a ``NavigationStack`` pushes — inside
    /// `navigationDestination(for:destination:)`, or a link's destination —
    /// it says how that screen comes and goes. ``NavigationTransition/automatic``
    /// is the transition the stack already makes;
    /// ``NavigationTransition/zoom(sourceID:in:)`` is a reveal from its
    /// source (``ZoomNavigationTransition``). Where the screen declares more
    /// than one, the outermost is its transition — the one written on the
    /// screen itself, over any a view inside it declares — and of two side by
    /// side, the first.
    ///
    /// - Parameter style: The transition.
    /// - Returns: A view that says how its screen comes and goes.
    public func navigationTransition(_ style: some NavigationTransition) -> some View {
        preference(key: NavigationZoomKey.self, value: (style as? ZoomNavigationTransition)?.source)
    }
}

/// The zoom a pushed screen declared (``View/navigationTransition(_:)``), read
/// by its ``NavigationStack`` as it reads the screen's title; `nil` for the
/// automatic transition.
struct NavigationZoomKey: PreferenceKey {
    static var defaultValue: MatchedGeometryKey? { nil }

    /// The first declaration is kept: the outermost, since a preference is
    /// set before its content draws, and of two side by side the first. The
    /// default keeps the last — the innermost — so a view inside a zooming
    /// screen that declared `.automatic` turned its zoom off.
    static func reduce(value: inout MatchedGeometryKey?, nextValue: () -> MatchedGeometryKey?) {}
}
