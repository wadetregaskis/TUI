//  🖥️ TUI — A Terminal UI framework for Swift
//  NavigationBarItems.swift
//
//  The toolbar items a navigation stack's bar hosts: those the screen it
//  shows places in the top bar, drawn in the stack's own bar rather than the
//  window's.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The Items

/// The top-bar items the screen a navigation stack shows declared this walk,
/// which the stack's bar draws instead of the window's top bar (the A28 design
/// study, §9: "a pushed screen's top items go in the stack's own bar").
///
/// One per stack, kept by its coordinator for the stack's life, so the
/// environment value that carries it is the same object every frame. The
/// stack empties it before the screen draws (``begin()``); the screen's
/// `.toolbar`s declare into it (TUIChrome), and say how a run of items is
/// drawn (``drawsItems``), since the toolbar's views are TUIChrome's, which
/// the stack's module cannot see; the bar then draws them.
@MainActor
package final class NavigationBarItems {
    /// The items declared this walk, in declaration order.
    package private(set) var entries: [WindowChromeState.ToolbarEntry] = []

    /// Their identities, so an item a walk renders twice is declared once.
    private var identities: Set<ViewIdentity> = []

    /// Draws a run of the items, side by side: given by what declared them.
    package var drawsItems: (@MainActor ([WindowChromeState.ToolbarEntry]) -> AnyView)?

    package init() {}

    /// Forgets the last walk's items. Called by the stack before its screen
    /// draws.
    package func begin() {
        entries.removeAll(keepingCapacity: true)
        identities.removeAll(keepingCapacity: true)
    }

    /// Records an item the screen declared — once per identity.
    package func declare(_ entry: WindowChromeState.ToolbarEntry) {
        guard identities.insert(entry.identity).inserted else { return }
        entries.append(entry)
    }
}

// MARK: - Environment

/// Environment key for the navigation stack bar hosting a screen's items.
private struct NavigationBarItemsKey: EnvironmentKey {
    // Computed: a stored class reference is not `Sendable`, and this is `nil`.
    static var defaultValue: NavigationBarItems? { nil }
}

extension EnvironmentValues {
    /// The navigation stack bar that hosts this screen's top-bar items, or
    /// `nil` outside a screen pushed onto a stack — where they go to the
    /// window's top bar.
    package var navigationBarItems: NavigationBarItems? {
        get { self[NavigationBarItemsKey.self] }
        set { self[NavigationBarItemsKey.self] = newValue }
    }
}
