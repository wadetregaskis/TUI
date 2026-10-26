//  🖥️ TUI — A Terminal UI framework for Swift
//  TableRowHeights.swift
//
//  How a table's rows get their heights: one line unless a column says more
//  (the default), or grown to what their view cells draw, as SwiftUI's table
//  grows them on macOS.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - TableRowHeights

/// How a ``Table``'s rows are given their heights.
///
/// TUI-specific: SwiftUI's table on macOS always grows a row to its tallest
/// cell (`NSTableView.usesAutomaticRowHeights` — measured: a cell holding a
/// `VStack` of two `Text`s makes a 40-point row where one-line rows are 24).
/// A TUI table keeps each cell to one line unless its column's
/// `lineLimit(_:)` allows more, because growing rows means measuring them: a
/// table whose rows may differ in height lays every row out to learn its
/// height, where a table of one-line rows knows its size without building a
/// row. ``automatic`` opts in to SwiftUI's behaviour, and pays that.
///
/// ```swift
/// Table(people) {
///     TableColumn("Name", value: \.name)
///     TableColumn("Contact") { person in
///         VStack(alignment: .leading) {
///             Text(person.email)
///             Text(person.phone)
///         }
///     }
/// }
/// .tableRowHeights(.automatic)
/// ```
public enum TableRowHeights: Sendable, Hashable {
    /// Every cell is one line unless its column's `lineLimit(_:)` allows more.
    /// The default.
    case lineLimited

    /// A column built from a content closure that states no `lineLimit(_:)`
    /// grows each row to its cell's natural height: a view's, measured at the
    /// column's width, and a `Text`'s wrapped at it. A key-path column, and
    /// any column with a stated limit, keeps its lines.
    case automatic

    /// As ``automatic``, but a column whose content is a `Text` keeps to one
    /// line: only other views — stacks of several lines and the like, the
    /// cells that are actually taller — grow their rows. A table of `Text`
    /// columns then costs what it does under ``lineLimited``.
    case automaticExceptText
}

private struct TableRowHeightsKey: EnvironmentKey {
    static let defaultValue = TableRowHeights.lineLimited
}

extension EnvironmentValues {
    /// How the tables in this subtree give their rows heights — see
    /// ``TableRowHeights``.
    public var tableRowHeights: TableRowHeights {
        get { self[TableRowHeightsKey.self] }
        set { self[TableRowHeightsKey.self] = newValue }
    }
}

extension View {
    /// Sets how the tables in this subtree give their rows heights.
    ///
    /// TUI-specific — see ``TableRowHeights`` for what each choice does and
    /// costs.
    ///
    /// - Parameter heights: How rows are given their heights.
    /// - Returns: A view whose tables size their rows so.
    public func tableRowHeights(_ heights: TableRowHeights) -> some View {
        environment(\.tableRowHeights, heights)
    }
}

// MARK: - The cell's side

/// The line limit a cell that grows to its content is given: its natural
/// height is what it draws, not this, which only has to be more than any row
/// should be. A view cell offered at least this many lines is measured first
/// and drawn at the height it measured (`_TableCellSource.content`), which is
/// how a greedy view — one that fills what it is offered — keeps to its own
/// height rather than this one.
enum _TableCellSizing {
    static let naturalLines = 1_000
}
