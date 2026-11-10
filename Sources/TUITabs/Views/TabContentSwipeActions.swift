//  🖥️ TUI — A Terminal UI framework for Swift
//  TabContentSwipeActions.swift
//
//  `TabContent.swipeActions(edge:allowsFullSwipe:content:)`: a tab's row in
//  a `.sidebarAdaptable` sidebar reveals buttons at its edge, as a list row
//  with `View.swipeActions` does — which is what the sidebar's row is given.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation
import TUIView

// MARK: - What a tab carries

/// One edge's swipe actions on a tab, from
/// `TabContent.swipeActions(edge:allowsFullSwipe:content:)`.
struct _TabSwipeEdge {
    /// Whether a full swipe performs the first action.
    let allowsFullSwipe: Bool
    /// The actions, as `Button`s.
    let content: AnyView
}

/// The swipe actions a tab's sidebar row reveals: one set for each edge at
/// most, the one written nearest the tab, as a context menu is.
struct _TabSwipeActions {
    var leading: _TabSwipeEdge?
    var trailing: _TabSwipeEdge?

    /// Whether the tab has none on either edge.
    var isEmpty: Bool { leading == nil && trailing == nil }
}

// MARK: - The modifier

extension TabContent {
    /// Adds custom swipe actions to a tab's row in a sidebar.
    ///
    /// A `.sidebarAdaptable` tab view lists its tabs as the rows of a
    /// sidebar `List`, and each row reveals its tab's actions as a list row
    /// with ``View/swipeActions(edge:allowsFullSwipe:content:)`` does: a
    /// terminal reports no swipe, so ⇧→ reveals the selected row's leading
    /// actions and ⇧← its trailing ones (⌃L and ⌃T where a terminal drops
    /// Shift on the arrows), and where the terminal reports a trackpad's
    /// sideways swipe as the horizontal wheel, a burst of it over a row
    /// reveals them too. Revealed, ← and → move between the buttons, Return
    /// presses one and Escape slides them away; the same chord again is the
    /// full swipe, which presses the first, where `allowsFullSwipe` is true.
    ///
    /// A tab bar has no rows to swipe, so in a strip the actions are not
    /// shown, as in SwiftUI's.
    ///
    /// ```swift
    /// TabView {
    ///     Tab("Drafts", systemImage: "doc") { DraftsView() }
    ///         .swipeActions {
    ///             Button("Archive") { archiveDrafts() }
    ///         }
    /// }
    /// .tabViewStyle(.sidebarAdaptable)
    /// ```
    ///
    /// Each edge takes one set: written twice for one edge, the one nearer
    /// the tab is the one revealed. The buttons are drawn over the row, and a
    /// sidebar is as wide as its tabs' titles, so buttons wider than the row
    /// are drawn shortened.
    ///
    /// - Parameters:
    ///   - edge: The edge of the tab's row the actions are revealed at.
    ///   - allowsFullSwipe: Whether a full swipe performs the first action.
    ///   - content: The actions, as `Button`s.
    /// - Returns: A tab with swipe actions.
    public func swipeActions<T: View>(
        edge: HorizontalEdge = .trailing, allowsFullSwipe: Bool = true, @ViewBuilder content: () -> T
    ) -> some TabContent<TabValue> {
        let actions = _TabSwipeEdge(allowsFullSwipe: allowsFullSwipe, content: AnyView(content()))
        // The modifier nearest the tab has already spoken for its edge.
        return _TabTraitContent(content: self) { tab in
            switch edge {
            case .leading:
                if tab.swipeActions.leading == nil { tab.swipeActions.leading = actions }
            case .trailing:
                if tab.swipeActions.trailing == nil { tab.swipeActions.trailing = actions }
            }
        }
    }
}

// MARK: - The sidebar row

extension View {
    /// This sidebar row with a tab's swipe actions: the list row's own
    /// ``View/swipeActions(edge:allowsFullSwipe:content:)``, once for each
    /// edge that has a set, and the row itself where neither does.
    @ViewBuilder
    func tabSwipeActions(_ actions: _TabSwipeActions) -> some View {
        switch (actions.leading, actions.trailing) {
        case (nil, nil):
            self
        case let (leading?, nil):
            swipeActions(edge: .leading, allowsFullSwipe: leading.allowsFullSwipe) { leading.content }
        case let (nil, trailing?):
            swipeActions(edge: .trailing, allowsFullSwipe: trailing.allowsFullSwipe) { trailing.content }
        case let (leading?, trailing?):
            swipeActions(edge: .leading, allowsFullSwipe: leading.allowsFullSwipe) { leading.content }
                .swipeActions(edge: .trailing, allowsFullSwipe: trailing.allowsFullSwipe) { trailing.content }
        }
    }
}
