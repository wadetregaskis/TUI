//  🖥️ TUI — A Terminal UI framework for Swift
//  SearchToolbarBehavior.swift
//
//  How a search field in a toolbar behaves, and how a toolbar behaves while
//  search is presented: `searchToolbarBehavior(_:)` and
//  `searchPresentationToolbarBehavior(_:)`.
//
//  Both return the view unchanged, and neither is a stub. The search field is
//  drawn at the top of the searchable subtree rather than in a toolbar, so
//  the one toolbar behaviour macOS offers — `.automatic` — is the behaviour it
//  has; and presenting search hides nothing around it, so asking it not to is
//  asking for what already holds. (See `MediumGuaranteedModifiers.swift` for
//  the line between a guarantee kept and a request dropped.)
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

// MARK: - SearchToolbarBehavior

/// The behavior of a search field in a toolbar. Mirrors SwiftUI's
/// `SearchToolbarBehavior`, which on macOS has one value.
public struct SearchToolbarBehavior: Hashable, Sendable {
    private init() {}

    /// The automatic behavior.
    public static var automatic: Self { Self() }
}

// MARK: - SearchPresentationToolbarBehavior

/// A type that defines how the toolbar behaves when presenting search.
/// Mirrors SwiftUI's `SearchPresentationToolbarBehavior`.
public struct SearchPresentationToolbarBehavior: Hashable, Sendable {
    private enum Kind: Hashable, Sendable {
        case automatic, avoidHidingContent
    }

    private let kind: Kind

    /// The automatic behavior.
    public static var automatic: Self { Self(kind: .automatic) }

    /// The avoid hiding content behavior: the content around the search field
    /// stays on screen while search is presented.
    public static var avoidHidingContent: Self { Self(kind: .avoidHidingContent) }
}

// MARK: - Modifiers

extension View {
    /// Configures the behavior for search in the toolbar. Mirrors SwiftUI's
    /// `searchToolbarBehavior(_:)`.
    ///
    /// The only behavior there is, ``SearchToolbarBehavior/automatic``, is the
    /// one a searchable's field has: it is drawn where it always is, at the top
    /// of the searchable subtree.
    ///
    /// - Parameter behavior: The behavior.
    /// - Returns: This view, unchanged.
    nonisolated public func searchToolbarBehavior(_ behavior: SearchToolbarBehavior) -> some View {
        self
    }

    /// Configures the search toolbar presentation behavior for any searchable
    /// modifiers within this view. Mirrors SwiftUI's
    /// `searchPresentationToolbarBehavior(_:)`.
    ///
    /// On iOS a toolbar may hide parts of its content while search is
    /// presented, and ``SearchPresentationToolbarBehavior/avoidHidingContent``
    /// asks it not to. Here presenting search — the field taking the focus —
    /// hides nothing: a navigation bar's title and the content around the
    /// field stay where they are. So both behaviors are what already happens.
    ///
    /// - Parameter behavior: The behavior.
    /// - Returns: This view, unchanged.
    nonisolated public func searchPresentationToolbarBehavior(
        _ behavior: SearchPresentationToolbarBehavior
    ) -> some View {
        self
    }
}
