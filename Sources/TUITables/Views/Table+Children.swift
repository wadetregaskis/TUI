//  🖥️ TUI — A Terminal UI framework for Swift
//  Table+Children.swift
//
//  The `Table` initializers that build a hierarchical table from a collection
//  and a key path to each row's children.
//
//  Created by Wade Tregaskis
//  License: MIT

// `SortComparator` is Foundation's.
import Foundation
import TUIFoundation

extension Table {
    /// Creates a hierarchical table that computes its rows based on a
    /// collection of identifiable data and key path to the children of that
    /// data.
    ///
    /// ```swift
    /// Table(files, children: \.children) {
    ///     TableColumn("Name", value: \.name)
    ///     TableColumn("Size", value: \.size)
    /// }
    /// ```
    ///
    /// ```
    ///   Name              Size
    ///   ▼ Sources
    ///     ▶ TUI        —
    ///       README.md     4 KB
    /// ```
    ///
    /// The first column draws each row's place in the tree: indented a step
    /// per level, with a triangle on a row that has children. A row whose
    /// children are `nil` is a leaf; an empty collection is a branch with
    /// nothing in it. Every branch starts closed.
    ///
    /// A click on a triangle opens or closes its branch. Right opens the
    /// focused row and Left closes it — or, on a row with nothing to close,
    /// moves to the row it sits under; ⌥Right and ⌥Left carry that through
    /// every branch beneath it, as in an outline ``List``.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the table rows.
    ///   - children: A key path to a row's children, or `nil` for a leaf.
    ///   - columnCustomization: A binding to the state of the columns.
    ///   - columns: The columns to display in the table.
    public init<Data: RandomAccessCollection, Columns: TableColumnContent>(
        _ data: Data, children: KeyPath<Value, Data?>,
        columnCustomization: Binding<TableColumnCustomization<Value>>? = nil,
        @TableColumnBuilder<Value, Never> columns: () -> Columns
    ) where Data.Element == Value, Columns.TableRowValue == Value {
        self.init(
            outlineRoots: _TableOutlineRoots(data, children: children),
            columns: tableColumns(of: columns()), single: nil, multi: nil, sortModel: nil,
            customization: columnCustomization)
    }

    /// Creates a hierarchical table that computes its rows based on a
    /// collection of identifiable data and key path to the children of that
    /// data, and that supports selecting zero or one row.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the table rows.
    ///   - children: A key path to a row's children, or `nil` for a leaf.
    ///   - selection: A binding to the selected row's ID (`nil`: none).
    ///   - columnCustomization: A binding to the state of the columns.
    ///   - columns: The columns to display in the table.
    public init<Data: RandomAccessCollection, Columns: TableColumnContent>(
        _ data: Data, children: KeyPath<Data.Element, Data?>, selection: Binding<Value.ID?>,
        columnCustomization: Binding<TableColumnCustomization<Value>>? = nil,
        @TableColumnBuilder<Value, Never> columns: () -> Columns
    ) where Data.Element == Value, Columns.TableRowValue == Value {
        self.init(
            outlineRoots: _TableOutlineRoots(data, children: children),
            columns: tableColumns(of: columns()), single: selection, multi: nil, sortModel: nil,
            customization: columnCustomization)
    }

    /// Creates a hierarchical table that computes its rows based on a
    /// collection of identifiable data and key path to the children of that
    /// data, and that supports selecting multiple rows.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the table rows.
    ///   - children: A key path to a row's children, or `nil` for a leaf.
    ///   - selection: A binding to the set of selected row IDs.
    ///   - columnCustomization: A binding to the state of the columns.
    ///   - columns: The columns to display in the table.
    public init<Data: RandomAccessCollection, Columns: TableColumnContent>(
        _ data: Data, children: KeyPath<Data.Element, Data?>, selection: Binding<Set<Value.ID>>,
        columnCustomization: Binding<TableColumnCustomization<Value>>? = nil,
        @TableColumnBuilder<Value, Never> columns: () -> Columns
    ) where Data.Element == Value, Columns.TableRowValue == Value {
        self.init(
            outlineRoots: _TableOutlineRoots(data, children: children),
            columns: tableColumns(of: columns()), single: nil, multi: selection, sortModel: nil,
            customization: columnCustomization)
    }

    /// Creates a sortable, hierarchical table that computes its rows based on
    /// a collection of identifiable data and key path to the children of that
    /// data.
    ///
    /// The table publishes the order and never sorts: sorting the rows, and
    /// each row's children, is the app's.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the table rows.
    ///   - children: A key path to a row's children, or `nil` for a leaf.
    ///   - sortOrder: A binding to the ordered sorting of columns.
    ///   - columnCustomization: A binding to the state of the columns.
    ///   - columns: The columns to display in the table.
    public init<Data: RandomAccessCollection, Sort: SortComparator, Columns: TableColumnContent>(
        _ data: Data, children: KeyPath<Data.Element, Data?>, sortOrder: Binding<[Sort]>,
        columnCustomization: Binding<TableColumnCustomization<Value>>? = nil,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns
    ) where Data.Element == Value, Sort.Compared == Value, Columns.TableRowValue == Value {
        self.init(
            outlineRoots: _TableOutlineRoots(data, children: children),
            columns: tableColumns(of: columns()), single: nil, multi: nil,
            sortModel: _TableSortModel(sortOrder), customization: columnCustomization)
    }

    /// Creates a sortable, hierarchical table that computes its rows based on
    /// a collection of identifiable data and key path to the children of that
    /// data, and that supports selecting zero or one row.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the table rows.
    ///   - children: A key path to a row's children, or `nil` for a leaf.
    ///   - selection: A binding to the selected row's ID (`nil`: none).
    ///   - sortOrder: A binding to the ordered sorting of columns.
    ///   - columnCustomization: A binding to the state of the columns.
    ///   - columns: The columns to display in the table.
    public init<Data: RandomAccessCollection, Sort: SortComparator, Columns: TableColumnContent>(
        _ data: Data, children: KeyPath<Data.Element, Data?>, selection: Binding<Value.ID?>,
        sortOrder: Binding<[Sort]>,
        columnCustomization: Binding<TableColumnCustomization<Value>>? = nil,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns
    ) where Data.Element == Value, Sort.Compared == Value, Columns.TableRowValue == Value {
        self.init(
            outlineRoots: _TableOutlineRoots(data, children: children),
            columns: tableColumns(of: columns()), single: selection, multi: nil,
            sortModel: _TableSortModel(sortOrder), customization: columnCustomization)
    }

    /// Creates a sortable, hierarchical table that computes its rows based on
    /// a collection of identifiable data and key path to the children of that
    /// data, and that supports selecting multiple rows.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the table rows.
    ///   - children: A key path to a row's children, or `nil` for a leaf.
    ///   - selection: A binding to the set of selected row IDs.
    ///   - sortOrder: A binding to the ordered sorting of columns.
    ///   - columnCustomization: A binding to the state of the columns.
    ///   - columns: The columns to display in the table.
    public init<Data: RandomAccessCollection, Sort: SortComparator, Columns: TableColumnContent>(
        _ data: Data, children: KeyPath<Data.Element, Data?>, selection: Binding<Set<Value.ID>>,
        sortOrder: Binding<[Sort]>,
        columnCustomization: Binding<TableColumnCustomization<Value>>? = nil,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns
    ) where Data.Element == Value, Sort.Compared == Value, Columns.TableRowValue == Value {
        self.init(
            outlineRoots: _TableOutlineRoots(data, children: children),
            columns: tableColumns(of: columns()), single: nil, multi: selection,
            sortModel: _TableSortModel(sortOrder), customization: columnCustomization)
    }
}
