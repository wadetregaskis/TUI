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
/// ``NavigationSplitView``'s own handles, ``title`` and ``search``. A
/// ``DefaultToolbarItem`` of a kind places that item in a bar.
public struct ToolbarDefaultItemKind {
    /// The item kinds TUIkit has.
    package enum Kind {
        case sidebarToggle
        case title
        case search
        case inspectorToggle
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

    /// The search field a `searchable` modifier draws at the top of the view
    /// it modifies: in a bar where a ``DefaultToolbarItem`` of this kind
    /// places it, and nowhere once `toolbar(removing:)` takes it away.
    ///
    /// SwiftUI declares this `static let`; see ``sidebarToggle``.
    public static var search: Self { Self(kind: .search) }

    /// An inspector's toggle: the ▶ on the divider between a view and its
    /// `inspector(isPresented:content:)`, and the button a
    /// ``DefaultToolbarItem`` of this kind puts in a bar — ▶ while the inspector
    /// shows, ◀ while it is hidden.
    ///
    /// A TUIkit addition: SwiftUI puts no button for an inspector in a toolbar
    /// (measured on macOS 15.8, 2026-10-14), and an app adds its own. So the
    /// window's bars show none unless a ``DefaultToolbarItem`` places one.
    public static var inspectorToggle: Self { Self(kind: .inspectorToggle) }
}

private struct ToolbarSearchRemovedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether a `toolbar(removing: .search)` on or above this view took the
    /// search field away, for a `searchable` modifier it holds. One drawn
    /// anywhere else in the window says so through the window's chrome
    /// (``WindowChromeState/searchFieldRemoved``).
    package var toolbarSearchRemoved: Bool {
        get { self[ToolbarSearchRemovedKey.self] }
        set { self[ToolbarSearchRemovedKey.self] = newValue }
    }
}

/// Not `Sendable`, exactly as SwiftUI declares it.
@available(*, unavailable)
extension ToolbarDefaultItemKind: Sendable {}
