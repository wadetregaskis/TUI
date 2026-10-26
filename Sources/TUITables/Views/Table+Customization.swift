//  🖥️ TUI — A Terminal UI framework for Swift
//  Table+Customization.swift
//
//  The `Table` initializers that bind the columns to a
//  `TableColumnCustomization`.
//
//  Created by Wade Tregaskis
//  License: MIT

// `SortComparator` is Foundation's.
import Foundation
import TUIFoundation

// MARK: - From a collection

extension Table {

    /// Creates a table that computes its rows based on a collection of
    /// identifiable data.
    ///
    /// Its columns are shown as `columnCustomization` says.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the table rows.
    ///   - columnCustomization: A binding to the state of the columns.
    ///   - columns: The columns to display in the table.
    public init<Data: RandomAccessCollection, Columns: TableColumnContent>(
        _ data: Data,
        columnCustomization: Binding<TableColumnCustomization<Value>>,
        @TableColumnBuilder<Value, Never> columns: () -> Columns
    ) where Data.Element == Value, Columns.TableRowValue == Value {
        self.init(
            rows: Array(data), columns: tableColumns(of: columns()), single: nil,
            multi: nil, sortModel: nil, customization: columnCustomization)
    }

    /// Creates a table that computes its rows based on a collection of
    /// identifiable data,
    /// and that supports selecting zero or one row.
    ///
    /// Its columns are shown as `columnCustomization` says.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the table rows.
    ///   - selection: A binding to the selected row's ID (`nil`: none).
    ///   - columnCustomization: A binding to the state of the columns.
    ///   - columns: The columns to display in the table.
    public init<Data: RandomAccessCollection, Columns: TableColumnContent>(
        _ data: Data, selection: Binding<Value.ID?>,
        columnCustomization: Binding<TableColumnCustomization<Value>>,
        @TableColumnBuilder<Value, Never> columns: () -> Columns
    ) where Data.Element == Value, Columns.TableRowValue == Value {
        self.init(
            rows: Array(data), columns: tableColumns(of: columns()), single: selection,
            multi: nil, sortModel: nil, customization: columnCustomization)
    }

    /// Creates a table that computes its rows based on a collection of
    /// identifiable data,
    /// and that supports selecting multiple rows.
    ///
    /// Its columns are shown as `columnCustomization` says.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the table rows.
    ///   - selection: A binding to the set of selected row IDs.
    ///   - columnCustomization: A binding to the state of the columns.
    ///   - columns: The columns to display in the table.
    public init<Data: RandomAccessCollection, Columns: TableColumnContent>(
        _ data: Data, selection: Binding<Set<Value.ID>>,
        columnCustomization: Binding<TableColumnCustomization<Value>>,
        @TableColumnBuilder<Value, Never> columns: () -> Columns
    ) where Data.Element == Value, Columns.TableRowValue == Value {
        self.init(
            rows: Array(data), columns: tableColumns(of: columns()), single: nil,
            multi: selection, sortModel: nil, customization: columnCustomization)
    }

    /// Creates a sortable table that computes its rows based on a collection of
    /// identifiable data.
    ///
    /// Its columns are shown as `columnCustomization` says.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the table rows.
    ///   - sortOrder: A binding to the ordered sorting of columns.
    ///   - columnCustomization: A binding to the state of the columns.
    ///   - columns: The columns to display in the table.
    public init<Data: RandomAccessCollection, Sort: SortComparator, Columns: TableColumnContent>(
        _ data: Data, sortOrder: Binding<[Sort]>,
        columnCustomization: Binding<TableColumnCustomization<Value>>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns
    ) where Data.Element == Value, Sort.Compared == Value, Columns.TableRowValue == Value {
        self.init(
            rows: Array(data), columns: tableColumns(of: columns()), single: nil,
            multi: nil, sortModel: _TableSortModel(sortOrder), customization: columnCustomization)
    }

    /// Creates a sortable table that computes its rows based on a collection of
    /// identifiable data,
    /// and that supports selecting zero or one row.
    ///
    /// Its columns are shown as `columnCustomization` says.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the table rows.
    ///   - selection: A binding to the selected row's ID (`nil`: none).
    ///   - sortOrder: A binding to the ordered sorting of columns.
    ///   - columnCustomization: A binding to the state of the columns.
    ///   - columns: The columns to display in the table.
    public init<Data: RandomAccessCollection, Sort: SortComparator, Columns: TableColumnContent>(
        _ data: Data, selection: Binding<Value.ID?>, sortOrder: Binding<[Sort]>,
        columnCustomization: Binding<TableColumnCustomization<Value>>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns
    ) where Data.Element == Value, Sort.Compared == Value, Columns.TableRowValue == Value {
        self.init(
            rows: Array(data), columns: tableColumns(of: columns()), single: selection,
            multi: nil, sortModel: _TableSortModel(sortOrder), customization: columnCustomization)
    }

    /// Creates a sortable table that computes its rows based on a collection of
    /// identifiable data,
    /// and that supports selecting multiple rows.
    ///
    /// Its columns are shown as `columnCustomization` says.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the table rows.
    ///   - selection: A binding to the set of selected row IDs.
    ///   - sortOrder: A binding to the ordered sorting of columns.
    ///   - columnCustomization: A binding to the state of the columns.
    ///   - columns: The columns to display in the table.
    public init<Data: RandomAccessCollection, Sort: SortComparator, Columns: TableColumnContent>(
        _ data: Data, selection: Binding<Set<Value.ID>>, sortOrder: Binding<[Sort]>,
        columnCustomization: Binding<TableColumnCustomization<Value>>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns
    ) where Data.Element == Value, Sort.Compared == Value, Columns.TableRowValue == Value {
        self.init(
            rows: Array(data), columns: tableColumns(of: columns()), single: nil,
            multi: selection, sortModel: _TableSortModel(sortOrder), customization: columnCustomization)
    }
}

// MARK: - From a row builder

extension Table {

    /// Creates a table with the given columns and rows.
    ///
    /// Its columns are shown as `columnCustomization` says.
    ///
    /// - Parameters:
    ///   - valueType: The type of value used to derive the table's contents.
    ///   - columnCustomization: A binding to the state of the columns.
    ///   - columns: The columns to display in the table.
    ///   - rows: The rows to display in the table.
    public init<Columns: TableColumnContent, Rows: TableRowContent>(
        of valueType: Value.Type,
        columnCustomization: Binding<TableColumnCustomization<Value>>,
        @TableColumnBuilder<Value, Never> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) where Columns.TableRowValue == Value, Rows.TableRowValue == Value {
        self.init(
            rowList: tableRows(of: rows()), columns: tableColumns(of: columns()),
            single: nil, multi: nil, sortModel: nil,
            customization: columnCustomization)
    }

    /// Creates a table with the given columns and rows,
    /// and that supports selecting zero or one row.
    ///
    /// Its columns are shown as `columnCustomization` says.
    ///
    /// - Parameters:
    ///   - valueType: The type of value used to derive the table's contents.
    ///   - selection: A binding to the selected row's ID (`nil`: none).
    ///   - columnCustomization: A binding to the state of the columns.
    ///   - columns: The columns to display in the table.
    ///   - rows: The rows to display in the table.
    public init<Columns: TableColumnContent, Rows: TableRowContent>(
        of valueType: Value.Type, selection: Binding<Value.ID?>,
        columnCustomization: Binding<TableColumnCustomization<Value>>,
        @TableColumnBuilder<Value, Never> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) where Columns.TableRowValue == Value, Rows.TableRowValue == Value {
        self.init(
            rowList: tableRows(of: rows()), columns: tableColumns(of: columns()),
            single: selection, multi: nil, sortModel: nil,
            customization: columnCustomization)
    }

    /// Creates a table with the given columns and rows,
    /// and that supports selecting multiple rows.
    ///
    /// Its columns are shown as `columnCustomization` says.
    ///
    /// - Parameters:
    ///   - valueType: The type of value used to derive the table's contents.
    ///   - selection: A binding to the set of selected row IDs.
    ///   - columnCustomization: A binding to the state of the columns.
    ///   - columns: The columns to display in the table.
    ///   - rows: The rows to display in the table.
    public init<Columns: TableColumnContent, Rows: TableRowContent>(
        of valueType: Value.Type, selection: Binding<Set<Value.ID>>,
        columnCustomization: Binding<TableColumnCustomization<Value>>,
        @TableColumnBuilder<Value, Never> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) where Columns.TableRowValue == Value, Rows.TableRowValue == Value {
        self.init(
            rowList: tableRows(of: rows()), columns: tableColumns(of: columns()),
            single: nil, multi: selection, sortModel: nil,
            customization: columnCustomization)
    }

    /// Creates a sortable table with the given columns and rows.
    ///
    /// Its columns are shown as `columnCustomization` says.
    ///
    /// - Parameters:
    ///   - valueType: The type of value used to derive the table's contents.
    ///   - sortOrder: A binding to the ordered sorting of columns.
    ///   - columnCustomization: A binding to the state of the columns.
    ///   - columns: The columns to display in the table.
    ///   - rows: The rows to display in the table.
    public init<Sort: SortComparator, Columns: TableColumnContent, Rows: TableRowContent>(
        of valueType: Value.Type = Value.self, sortOrder: Binding<[Sort]>,
        columnCustomization: Binding<TableColumnCustomization<Value>>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) where Sort.Compared == Value, Columns.TableRowValue == Value, Rows.TableRowValue == Value {
        self.init(
            rowList: tableRows(of: rows()), columns: tableColumns(of: columns()),
            single: nil, multi: nil, sortModel: _TableSortModel(sortOrder),
            customization: columnCustomization)
    }

    /// Creates a sortable table with the given columns and rows,
    /// and that supports selecting zero or one row.
    ///
    /// Its columns are shown as `columnCustomization` says.
    ///
    /// - Parameters:
    ///   - valueType: The type of value used to derive the table's contents.
    ///   - selection: A binding to the selected row's ID (`nil`: none).
    ///   - sortOrder: A binding to the ordered sorting of columns.
    ///   - columnCustomization: A binding to the state of the columns.
    ///   - columns: The columns to display in the table.
    ///   - rows: The rows to display in the table.
    public init<Sort: SortComparator, Columns: TableColumnContent, Rows: TableRowContent>(
        of valueType: Value.Type = Value.self, selection: Binding<Value.ID?>, sortOrder: Binding<[Sort]>,
        columnCustomization: Binding<TableColumnCustomization<Value>>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) where Sort.Compared == Value, Columns.TableRowValue == Value, Rows.TableRowValue == Value {
        self.init(
            rowList: tableRows(of: rows()), columns: tableColumns(of: columns()),
            single: selection, multi: nil, sortModel: _TableSortModel(sortOrder),
            customization: columnCustomization)
    }

    /// Creates a sortable table with the given columns and rows,
    /// and that supports selecting multiple rows.
    ///
    /// Its columns are shown as `columnCustomization` says.
    ///
    /// - Parameters:
    ///   - valueType: The type of value used to derive the table's contents.
    ///   - selection: A binding to the set of selected row IDs.
    ///   - sortOrder: A binding to the ordered sorting of columns.
    ///   - columnCustomization: A binding to the state of the columns.
    ///   - columns: The columns to display in the table.
    ///   - rows: The rows to display in the table.
    public init<Sort: SortComparator, Columns: TableColumnContent, Rows: TableRowContent>(
        of valueType: Value.Type = Value.self, selection: Binding<Set<Value.ID>>, sortOrder: Binding<[Sort]>,
        columnCustomization: Binding<TableColumnCustomization<Value>>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) where Sort.Compared == Value, Columns.TableRowValue == Value, Rows.TableRowValue == Value {
        self.init(
            rowList: tableRows(of: rows()), columns: tableColumns(of: columns()),
            single: nil, multi: selection, sortModel: _TableSortModel(sortOrder),
            customization: columnCustomization)
    }
}
