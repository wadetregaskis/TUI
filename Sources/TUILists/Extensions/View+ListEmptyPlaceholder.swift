//  🖥️ TUI — A Terminal UI framework for Swift
//  View+ListEmptyPlaceholder.swift
//
//  `listEmptyPlaceholder(_:)` — what the lists in a subtree draw when they
//  have no rows.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - Environment

/// EnvironmentKey for the empty lists' placeholder in force for a subtree.
private struct ListEmptyPlaceholderKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// What the lists in this subtree draw when they have no rows, or `nil`
    /// for the localized "No items".
    var listEmptyPlaceholder: String? {
        get { self[ListEmptyPlaceholderKey.self] }
        set { self[ListEmptyPlaceholderKey.self] = newValue }
    }
}

// MARK: - Modifier

extension View {
    /// Sets the localized text the lists in this view draw when they have no
    /// rows.
    ///
    /// TUI-specific. A modifier, so it can come anywhere in a chain and reach
    /// every ``List`` below it; the nearest one wins. The default is the
    /// localized "No items", drawn in the secondary ink where a row's text
    /// would start.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// ```swift
    /// List(tasks) { Text($0.title) }
    ///     .listStyle(.plain)
    ///     .listEmptyPlaceholder("Nothing to do")
    /// ```
    ///
    /// - Parameter placeholderKey: The key for the text to show when empty.
    /// - Returns: A view whose empty lists show the placeholder.
    nonisolated public func listEmptyPlaceholder(_ placeholderKey: LocalizedStringKey) -> some View {
        environment(\.listEmptyPlaceholder, placeholderKey.localized)
    }

    /// Sets the text the lists in this view draw when they have no rows,
    /// displayed as written.
    ///
    /// Generic over `StringProtocol` rather than taking a concrete `String`,
    /// which is what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey``.
    ///
    /// Text too long for the list's width wraps onto the rows below, as many as
    /// the list has, the last ending in an ellipsis if even those are too few.
    ///
    /// - Parameter placeholder: The text to show when a list is empty.
    /// - Returns: A view whose empty lists show the placeholder.
    @_disfavoredOverload
    nonisolated public func listEmptyPlaceholder<S: StringProtocol>(_ placeholder: S) -> some View {
        environment(\.listEmptyPlaceholder, String(placeholder))
    }
}
