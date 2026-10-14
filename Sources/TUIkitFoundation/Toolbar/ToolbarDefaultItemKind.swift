//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarDefaultItemKind.swift
//
//  The kinds of item the framework provides by default, which
//  `toolbar(removing:)` takes away. Here, below the modules that act on them —
//  the split view's toggle and the title in TUIkitNavigation, the toolbar's
//  items in TUIkitChrome — so each can name them.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Toolbar Default Item Kind

/// A kind of control the framework provides by default, which
/// ``View/toolbar(removing:)`` can take away.
///
/// Mirrors SwiftUI's `ToolbarDefaultItemKind`: ``sidebarToggle``, the
/// ``NavigationSplitView``'s own handles, and ``title``.
public struct ToolbarDefaultItemKind {
    /// The item kinds TUIkit has.
    package enum Kind {
        case sidebarToggle
        case title
    }

    package let kind: Kind

    /// A ``NavigationSplitView``'s sidebar toggle: the ◀ on its leftmost divider
    /// and the ▶ edge column shown while a leading column is hidden.
    ///
    /// SwiftUI declares this `static let`. A computed property reads the same at
    /// every call site, and a `static let` of this type would be global state
    /// Swift 6 rejects, since the type is deliberately not `Sendable` (as in
    /// SwiftUI).
    public static var sidebarToggle: Self { Self(kind: .sidebarToggle) }

    /// The title: the top bar's title slot, where the window's
    /// `.navigationTitle` and `.navigationSubtitle` are shown, and the title a
    /// ``NavigationStack``'s bar shows over a pushed screen, with its subtitle
    /// and the trail of titles behind it. The stack's Back button stays, as a
    /// macOS window keeps its back button when the title item goes.
    ///
    /// SwiftUI declares this `static let`; see ``sidebarToggle``.
    public static var title: Self { Self(kind: .title) }
}

/// Not `Sendable`, exactly as SwiftUI declares it.
@available(*, unavailable)
extension ToolbarDefaultItemKind: Sendable {}
