//  🖥️ TUI — A Terminal UI framework for Swift
//  TableColumnHeadersModifier.swift
//
//  `tableColumnHeaders(_:)` — whether the tables in a subtree draw their
//  column headers.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation

// MARK: - Environment

/// EnvironmentKey for the column headers' visibility in force for a subtree.
private struct TableColumnHeadersVisibilityKey: EnvironmentKey {
    static let defaultValue: Visibility = .automatic
}

extension EnvironmentValues {
    /// Whether the tables in this subtree draw their column headers: only
    /// `.hidden` takes the header line away.
    var tableColumnHeadersVisibility: Visibility {
        get { self[TableColumnHeadersVisibilityKey.self] }
        set { self[TableColumnHeadersVisibilityKey.self] = newValue }
    }
}

// MARK: - Modifier

extension View {
    /// Controls the visibility of a ``Table``'s column header views.
    ///
    /// By default, `Table` shows the column header for each column; hiding
    /// them gives the rows the header's line. With the headers hidden, a
    /// sortable table still sorts from the keyboard (Ctrl-S, Ctrl-D), and its
    /// columns are sized as before.
    ///
    /// ```swift
    /// Table(people) {
    ///     TableColumn("Name", value: \.name)
    /// }
    /// .tableColumnHeaders(.hidden)
    /// ```
    ///
    /// - Parameter visibility: A value of `visible` shows the headers, a value
    ///   of `hidden` hides them, and `automatic` defers to the table, which
    ///   shows them.
    /// - Returns: A view whose tables draw their headers as `visibility` says.
    nonisolated public func tableColumnHeaders(_ visibility: Visibility) -> some View {
        environment(\.tableColumnHeadersVisibility, visibility)
    }
}
