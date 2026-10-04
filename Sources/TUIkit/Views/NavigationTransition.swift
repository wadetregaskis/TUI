//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationTransition.swift
//
//  `navigationTransition(_:)`, in the one transition a terminal's navigation
//  has: the automatic one.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

/// A type that defines the transition to use when navigating to a view.
/// Mirrors SwiftUI's `NavigationTransition`.
///
/// ``automatic`` is the transition a ``NavigationStack`` makes: the screen is
/// replaced and the crumb trail updated, in the frame the path changes.
/// SwiftUI's `.zoom(sourceID:in:)`, and the `matchedTransitionSource` it pairs
/// with, interpolate a source view's frame into the destination's; whether a
/// terminal should have them is an open question (O4 in the refusal review),
/// so they are absent.
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

extension View {
    /// Sets the navigation transition style for this view. Mirrors SwiftUI's
    /// `navigationTransition(_:)`.
    ///
    /// The only style there is here, ``NavigationTransition/automatic``, is the
    /// transition a ``NavigationStack`` already makes, so the view is returned
    /// unchanged — a request honoured, not one dropped.
    ///
    /// - Parameter style: The transition.
    /// - Returns: This view, unchanged.
    public func navigationTransition(_ style: some NavigationTransition) -> some View {
        self
    }
}
