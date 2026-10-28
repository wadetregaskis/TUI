//  🖥️ TUI — A Terminal UI framework for Swift
//  SearchActivating.swift
//
//  What a view inside a `.searchable` can ask of its search without depending
//  on TUISearch: whether it is active, and to activate it. The tab view's
//  `tabViewSearchActivation(.searchTabSelection)` is the asker (TUITabs and
//  TUISearch do not depend on each other).
//
//  Created by Wade Tregaskis
//  License: MIT

/// The search of the nearest enclosing `.searchable`, as its content sees it:
/// the object `dismissSearch` ends, in the `.searchDismissal` slot.
@MainActor
package protocol SearchActivating: AnyObject {
    /// Whether the search field holds the focus (`\.isSearching`).
    var isSearching: Bool { get }

    /// Moves the focus to the search field, as setting a searchable's
    /// `isPresented` to `true` does.
    func activateSearch()
}

extension EnvironmentValues {
    /// The search of the nearest enclosing `.searchable`, or `nil` outside one.
    package var searchActivation: (any SearchActivating)? {
        self[featureObject: .searchDismissal] as? any SearchActivating
    }
}
