//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableColumnSpec.swift
//
//  What `_TableCore` draws a column from, and how it reads the sort order —
//  both with the public types' generic parameters erased.
//
//  Created by Wade Tregaskis
//  License: MIT

// `SortComparator` / `SortOrder` / `KeyPathComparator` are Foundation's.
import Foundation

// MARK: - Column spec

/// One column of a table as the renderer sees it: everything the column's
/// declaration said, with the declaration's own generic parameters erased.
///
/// The renderer is generic over the ROW type only. What a column shows, how it
/// sorts and what it is called are all reduced to values and closures over that
/// row type here, so the renderer never needs to know which public spelling
/// built the column.
struct _TableColumnSpec<Value> {
    /// The column header title.
    var title: String

    /// The horizontal alignment of the column's header and cells.
    var alignment: HorizontalAlignment

    /// The width mode for this column.
    var width: ColumnWidth

    /// How a cell value is shortened when it is wider than the column.
    var truncationMode: TruncationMode

    /// The maximum number of lines a cell in this column may occupy, never
    /// below 1.
    var lineLimit: Int

    /// Extracts the display value from a data item.
    let valueExtractor: (Value) -> String

    /// Whether ``valueExtractor`` NAMES a property rather than computing one.
    /// See ``TableColumn/namesAProperty`` — this is the same flag, carried
    /// through, and the row memo's whole soundness argument rests on it.
    let namesAProperty: Bool

    /// The column's comparator, with its type erased, or `nil` when the column
    /// cannot sort. Only a ``_TableSortModel`` — which knows the table's
    /// comparator type — can read it.
    let sortComparator: Any?

    /// Extracts the display value from an item.
    func value(for item: Value) -> String {
        valueExtractor(item)
    }
}

// MARK: - Sort model

/// A table's sort-order binding, with its comparator type erased.
///
/// The renderer asks two questions of the sort order and makes one change to
/// it: is the order's primary comparator this column's, and in which direction;
/// and "apply a click on this column's header". Both are answered by closures
/// built where the comparator type is still known, so the renderer is not
/// generic over it.
struct _TableSortModel<Value> {
    /// The primary comparator's direction, when the primary comparator is the
    /// one a column with this (erased) comparator sorts by; `nil` otherwise.
    let primaryOrder: (Any) -> SortOrder?

    /// Applies a click on the header of a column with this (erased)
    /// comparator: flips the primary sort when it is already this column's,
    /// and otherwise makes this column the primary sort, ascending, keeping
    /// the displaced comparators behind it as tie-breaks.
    let toggle: (Any) -> Void

    /// Wraps `binding`.
    ///
    /// Two comparators name the same column when both are
    /// `KeyPathComparator`s over the same key path, whatever their direction
    /// and inner comparator: the order an app seeds its binding with need not
    /// spell the column's comparator exactly for the header to recognise it.
    /// Any other comparator type is compared whole, with its direction
    /// normalised.
    init<Sort: SortComparator>(_ binding: Binding<[Sort]>) where Sort.Compared == Value {
        primaryOrder = { erased in
            guard let column = erased as? Sort,
                let primary = binding.wrappedValue.first,
                Self.sameColumn(primary, column)
            else { return nil }
            return primary.order
        }
        toggle = { erased in
            guard let column = erased as? Sort else { return }
            var order = binding.wrappedValue
            if let first = order.first, Self.sameColumn(first, column) {
                order[0].order = first.order == .forward ? .reverse : .forward
            } else {
                var promoted = column
                promoted.order = .forward
                order.removeAll { Self.sameColumn($0, column) }
                order.insert(promoted, at: 0)
            }
            binding.wrappedValue = order
        }
    }

    /// Whether `lhs` and `rhs` order the rows by the same column.
    private static func sameColumn<Sort: SortComparator>(_ lhs: Sort, _ rhs: Sort) -> Bool
    where Sort.Compared == Value {
        if let lhs = lhs as? KeyPathComparator<Value>, let rhs = rhs as? KeyPathComparator<Value> {
            return lhs.keyPath == rhs.keyPath
        }
        var lhs = lhs
        var rhs = rhs
        lhs.order = .forward
        rhs.order = .forward
        return lhs == rhs
    }
}
