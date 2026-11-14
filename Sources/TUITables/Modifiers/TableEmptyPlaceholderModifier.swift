//  🖥️ TUI — A Terminal UI framework for Swift
//  TableEmptyPlaceholderModifier.swift
//
//  `tableEmptyPlaceholder(_:)` — what the tables in a subtree draw when they
//  have no rows.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation

// MARK: - Environment

/// EnvironmentKey for the empty tables' placeholder in force for a subtree.
private struct TableEmptyPlaceholderKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// What the tables in this subtree draw when they have no rows, or `nil`
    /// for the localized "No items".
    var tableEmptyPlaceholder: String? {
        get { self[TableEmptyPlaceholderKey.self] }
        set { self[TableEmptyPlaceholderKey.self] = newValue }
    }
}

// MARK: - Modifier

extension View {
    /// Sets the localized text the tables in this view draw when they have no
    /// rows.
    ///
    /// TUI-specific. A modifier, so it can come anywhere in a chain and reach
    /// every ``Table`` below it; the nearest one wins. The default is the
    /// localized "No items", drawn in the secondary ink where a row's first
    /// cell would start.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// ```swift
    /// Table(processes) { TableColumn("Name", value: \.name) }
    ///     .tableStyle(.bordered)
    ///     .tableEmptyPlaceholder("No process matches the filter")
    /// ```
    ///
    /// - Parameter placeholderKey: The key for the text to show when empty.
    /// - Returns: A view whose empty tables show the placeholder.
    nonisolated public func tableEmptyPlaceholder(_ placeholderKey: LocalizedStringKey) -> some View {
        environment(\.tableEmptyPlaceholder, placeholderKey.localized)
    }

    /// Sets the text the tables in this view draw when they have no rows,
    /// displayed as written.
    ///
    /// Generic over `StringProtocol` rather than taking a concrete `String`,
    /// which is what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey``.
    ///
    /// Text too long for the table's width wraps onto the rows below, as many as
    /// the table has, the last ending in an ellipsis if even those are too few.
    ///
    /// - Parameter placeholder: The text to show when a table is empty.
    /// - Returns: A view whose empty tables show the placeholder.
    @_disfavoredOverload
    nonisolated public func tableEmptyPlaceholder<S: StringProtocol>(_ placeholder: S) -> some View {
        environment(\.tableEmptyPlaceholder, String(placeholder))
    }
}
