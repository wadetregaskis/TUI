//  🖥️ TUI — A Terminal UI framework for Swift
//  SelectionFollowsCursor.swift
//
//  Whether a key that moves a list's, table's or picker's cursor selects what
//  it lands on, as macOS does, rather than moving a cursor apart from the
//  selection (the default, deviation V2). The owner's APPFB-1, 2026-11-14.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// MARK: - Environment key

/// `\.selectionFollowsCursor`'s key.
private struct SelectionFollowsCursorKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether a key that moves the cursor of a control with a selection
    /// selects what the cursor lands on — see
    /// ``View/selectionFollowsCursor(_:)``. `false` by default: the keys move
    /// a cursor, and Space or Return selects.
    public var selectionFollowsCursor: Bool {
        get { self[SelectionFollowsCursorKey.self] }
        set { self[SelectionFollowsCursorKey.self] = newValue }
    }
}

// MARK: - Modifier

extension View {
    /// Makes a key that moves the cursor of a list, table or picker in this
    /// subtree select what the cursor lands on, as macOS does.
    ///
    /// By default TUI's lists, tables, radio groups and segmented pickers keep
    /// a keyboard cursor apart from their selection: the arrows move the
    /// cursor, and Space or Return selects (or toggles) the row or option
    /// under it, so a list can be browsed without changing what is selected.
    /// Where the selection should simply follow the keys — a master list whose
    /// selected row's details show beside it, as on macOS — set this:
    ///
    /// ```swift
    /// List(processes, selection: $selected) { Text($0.name) }
    ///     .selectionFollowsCursor()
    /// ```
    ///
    /// Every key that moves the cursor then selects the row it lands on: the
    /// arrows, Home and End, the paging keys, type select, and a tree's Left
    /// onto a branch's parent. With a multiple selection, such a key selects
    /// that row alone, as a plain arrow does on macOS; Shift with an arrow
    /// still extends the selection from its anchor, and Space and Ctrl-A still
    /// build one. Space toggles the cursor's row either way. A click and the
    /// pointer are unchanged.
    ///
    /// The nearest setting wins, so `.selectionFollowsCursor(false)` keeps one
    /// list's cursor apart inside a subtree that follows.
    ///
    /// TUI-specific: on macOS the keyboard cursor is the selection, and
    /// SwiftUI has nothing to set.
    ///
    /// - Parameter follows: Whether the selection follows the cursor.
    /// - Returns: A view whose lists, tables and pickers select as their
    ///   cursor moves, or keep it apart.
    nonisolated public func selectionFollowsCursor(_ follows: Bool = true) -> some View {
        environment(\.selectionFollowsCursor, follows)
    }
}
