//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationSplitViewColumn.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitFoundation

// MARK: - NavigationSplitViewVisibility

/// The visibility of the leading columns in a navigation split view.
///
/// Use a value of this type to control the visibility of the columns of a
/// ``NavigationSplitView``. Create a ``State`` property with a value of this
/// type, and pass a ``Binding`` to that state to the appropriate initializer.
///
/// ## Example
///
/// ```swift
/// @State private var visibility = NavigationSplitViewVisibility.all
///
/// NavigationSplitView(columnVisibility: $visibility) {
///     List(items, selection: $selected) { ... }
/// } detail: {
///     DetailView(item: selected)
/// }
/// ```
///
/// ## Visibility Options
///
/// - ``automatic``: Use the default visibility for the current context.
/// - ``all``: Show all columns.
/// - ``doubleColumn``: Show content and detail (hide sidebar in 3-column).
/// - ``detailOnly``: Show only the detail column.
public struct NavigationSplitViewVisibility: Equatable, Hashable, Sendable, Codable {
    /// The raw value representing the visibility state.
    private let rawValue: Int

    /// Use the default leading column visibility for the current context.
    ///
    /// In TUIkit, this resolves to ``all`` since terminal width is typically
    /// sufficient to display all columns.
    public static var automatic: Self {
        Self(rawValue: 0)
    }

    /// Show all columns of a navigation split view.
    ///
    /// For a two-column split view, this shows sidebar and detail.
    /// For a three-column split view, this shows sidebar, content, and detail.
    public static var all: Self {
        Self(rawValue: 1)
    }

    /// Show the content column and detail area of a three-column navigation
    /// split view, or the sidebar column and detail area of a two-column
    /// navigation split view.
    ///
    /// For a two-column navigation split view, `doubleColumn` is equivalent
    /// to ``all``.
    public static var doubleColumn: Self {
        Self(rawValue: 2)
    }

    /// Hide the leading columns, showing only the detail area.
    ///
    /// For a two-column split view, this hides the sidebar.
    /// For a three-column split view, this hides both sidebar and content.
    public static var detailOnly: Self {
        Self(rawValue: 3)
    }
}

// MARK: - NavigationSplitViewColumn

/// A column in a navigation split view.
///
/// Use this type to identify which column should be displayed when the
/// navigation split view collapses or to programmatically control column
/// focus.
///
/// ## Example
///
/// ```swift
/// @State private var preferredColumn = NavigationSplitViewColumn.sidebar
///
/// NavigationSplitView(preferredCompactColumn: $preferredColumn) {
///     SidebarView()
/// } detail: {
///     DetailView()
/// }
/// ```
public struct NavigationSplitViewColumn: Equatable, Hashable, Sendable {
    /// The raw value identifying the column.
    private let rawValue: Int

    /// The sidebar column (leftmost).
    ///
    /// This is the first column in both two-column and three-column layouts.
    public static var sidebar: Self {
        Self(rawValue: 0)
    }

    /// The content column (middle).
    ///
    /// This column only exists in three-column layouts. In a two-column
    /// layout, use ``sidebar`` or ``detail``.
    public static var content: Self {
        Self(rawValue: 1)
    }

    /// The detail column (rightmost).
    ///
    /// This is the last column in both two-column and three-column layouts.
    public static var detail: Self {
        Self(rawValue: 2)
    }
}
