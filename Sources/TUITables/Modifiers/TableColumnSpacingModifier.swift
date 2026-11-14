//  🖥️ TUI — A Terminal UI framework for Swift
//  TableColumnSpacingModifier.swift
//
//  `tableColumnSpacing(_:)` — the cells between adjacent columns of the
//  tables in a subtree.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation

// MARK: - Environment

/// EnvironmentKey for the column spacing in force for a subtree.
private struct TableColumnSpacingKey: EnvironmentKey {
    static let defaultValue = 2
}

extension EnvironmentValues {
    /// The cells between adjacent columns of the tables in this subtree:
    /// 2 by default, never negative.
    var tableColumnSpacing: Int {
        get { self[TableColumnSpacingKey.self] }
        set { self[TableColumnSpacingKey.self] = newValue }
    }
}

// MARK: - Modifier

extension View {
    /// Sets the number of cells between adjacent columns of the tables in
    /// this view (default 2).
    ///
    /// TUI-specific. A modifier, so it can come anywhere in a chain and reach
    /// every ``Table`` below it; the nearest one wins. Columns are separated
    /// by spaces, not rules, so this is the whole of the gap. A negative
    /// spacing is treated as zero.
    ///
    /// ```swift
    /// Table(processes) { … }
    ///     .tableStyle(.bordered)
    ///     .tableColumnSpacing(1)
    /// ```
    ///
    /// - Parameter spacing: The gap between columns, in cells.
    /// - Returns: A view whose tables space their columns by `spacing`.
    nonisolated public func tableColumnSpacing(_ spacing: Int) -> some View {
        // Clamped: spacing reaches `String(repeating:count:)` in three places
        // in the table, which traps on a negative count. Clamped once here, at
        // the boundary, so every use downstream is safe by construction.
        environment(\.tableColumnSpacing, max(0, spacing.heldToStatedLength))
    }
}
