//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Table+Rows.swift
//
//  The `Table` initializers that take their rows from a row builder rather
//  than a collection.
//
//  Created by Wade Tregaskis
//  License: MIT

// `SortComparator` is Foundation's.
import Foundation

// MARK: - Initializers with rows

extension Table {
    /// Creates a table with the given columns and rows that generates its
    /// contents using values of the given type.
    ///
    /// ```swift
    /// Table(of: Person.self) {
    ///     TableColumn("Name", value: \.name)
    /// } rows: {
    ///     TableRow(Person(name: "Juan"))
    ///     ForEach(people) { TableRow($0) }
    /// }
    /// ```
    ///
    /// The rows are flattened when the table is built, in the order the
    /// `rows` closure gives them.
    ///
    /// - Parameters:
    ///   - valueType: The type of value used to derive the table's contents.
    ///   - columns: The columns to display in the table.
    ///   - rows: The rows to display in the table.
    public init<Columns: TableColumnContent, Rows: TableRowContent>(
        of valueType: Value.Type,
        @TableColumnBuilder<Value, Never> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) where Columns.TableRowValue == Value, Rows.TableRowValue == Value {
        self.init(
            rowList: tableRows(of: rows()), columns: tableColumns(of: columns()),
            single: nil, multi: nil, sortModel: nil)
    }

    /// Creates a table with the given columns and rows that supports
    /// selecting zero or one row.
    ///
    /// - Parameters:
    ///   - valueType: The type of value used to derive the table's contents.
    ///   - selection: A binding to the selected row's ID (`nil`: none).
    ///   - columns: The columns to display in the table.
    ///   - rows: The rows to display in the table.
    public init<Columns: TableColumnContent, Rows: TableRowContent>(
        of valueType: Value.Type, selection: Binding<Value.ID?>,
        @TableColumnBuilder<Value, Never> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) where Columns.TableRowValue == Value, Rows.TableRowValue == Value {
        self.init(
            rowList: tableRows(of: rows()), columns: tableColumns(of: columns()),
            single: selection, multi: nil, sortModel: nil)
    }

    /// Creates a table with the given columns and rows that supports
    /// selecting multiple rows.
    ///
    /// - Parameters:
    ///   - valueType: The type of value used to derive the table's contents.
    ///   - selection: A binding to the set of selected row IDs.
    ///   - columns: The columns to display in the table.
    ///   - rows: The rows to display in the table.
    public init<Columns: TableColumnContent, Rows: TableRowContent>(
        of valueType: Value.Type, selection: Binding<Set<Value.ID>>,
        @TableColumnBuilder<Value, Never> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) where Columns.TableRowValue == Value, Rows.TableRowValue == Value {
        self.init(
            rowList: tableRows(of: rows()), columns: tableColumns(of: columns()),
            single: nil, multi: selection, sortModel: nil)
    }

    /// Creates a sortable table with the given columns and rows.
    ///
    /// - Parameters:
    ///   - valueType: The type of value used to derive the table's contents.
    ///   - sortOrder: A binding to the ordered sorting of columns.
    ///   - columns: The columns to display in the table.
    ///   - rows: The rows to display in the table.
    public init<Sort: SortComparator, Columns: TableColumnContent, Rows: TableRowContent>(
        of valueType: Value.Type, sortOrder: Binding<[Sort]>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) where Sort.Compared == Value, Columns.TableRowValue == Value, Rows.TableRowValue == Value {
        self.init(
            rowList: tableRows(of: rows()), columns: tableColumns(of: columns()),
            single: nil, multi: nil, sortModel: _TableSortModel(sortOrder))
    }

    /// Creates a sortable table with the given columns and rows that supports
    /// selecting zero or one row.
    ///
    /// - Parameters:
    ///   - valueType: The type of value used to derive the table's contents.
    ///   - selection: A binding to the selected row's ID (`nil`: none).
    ///   - sortOrder: A binding to the ordered sorting of columns.
    ///   - columns: The columns to display in the table.
    ///   - rows: The rows to display in the table.
    public init<Sort: SortComparator, Columns: TableColumnContent, Rows: TableRowContent>(
        of valueType: Value.Type, selection: Binding<Value.ID?>, sortOrder: Binding<[Sort]>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) where Sort.Compared == Value, Columns.TableRowValue == Value, Rows.TableRowValue == Value {
        self.init(
            rowList: tableRows(of: rows()), columns: tableColumns(of: columns()),
            single: selection, multi: nil, sortModel: _TableSortModel(sortOrder))
    }

    /// Creates a sortable table with the given columns and rows that supports
    /// selecting multiple rows.
    ///
    /// - Parameters:
    ///   - valueType: The type of value used to derive the table's contents.
    ///   - selection: A binding to the set of selected row IDs.
    ///   - sortOrder: A binding to the ordered sorting of columns.
    ///   - columns: The columns to display in the table.
    ///   - rows: The rows to display in the table.
    public init<Sort: SortComparator, Columns: TableColumnContent, Rows: TableRowContent>(
        of valueType: Value.Type, selection: Binding<Set<Value.ID>>, sortOrder: Binding<[Sort]>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) where Sort.Compared == Value, Columns.TableRowValue == Value, Rows.TableRowValue == Value {
        self.init(
            rowList: tableRows(of: rows()), columns: tableColumns(of: columns()),
            single: nil, multi: selection, sortModel: _TableSortModel(sortOrder))
    }

    /// Creates a sortable table with the given columns and rows, its value
    /// type inferred from them.
    ///
    /// - Parameters:
    ///   - sortOrder: A binding to the ordered sorting of columns.
    ///   - columns: The columns to display in the table.
    ///   - rows: The rows to display in the table.
    public init<Sort: SortComparator, Columns: TableColumnContent, Rows: TableRowContent>(
        sortOrder: Binding<[Sort]>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) where Sort.Compared == Value, Columns.TableRowValue == Value, Rows.TableRowValue == Value {
        self.init(of: Value.self, sortOrder: sortOrder, columns: columns, rows: rows)
    }

    /// Creates a sortable table with the given columns and rows that supports
    /// selecting zero or one row, its value type inferred from them.
    ///
    /// - Parameters:
    ///   - selection: A binding to the selected row's ID (`nil`: none).
    ///   - sortOrder: A binding to the ordered sorting of columns.
    ///   - columns: The columns to display in the table.
    ///   - rows: The rows to display in the table.
    public init<Sort: SortComparator, Columns: TableColumnContent, Rows: TableRowContent>(
        selection: Binding<Value.ID?>, sortOrder: Binding<[Sort]>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) where Sort.Compared == Value, Columns.TableRowValue == Value, Rows.TableRowValue == Value {
        self.init(
            of: Value.self, selection: selection, sortOrder: sortOrder, columns: columns, rows: rows)
    }

    /// Creates a sortable table with the given columns and rows that supports
    /// selecting multiple rows, its value type inferred from them.
    ///
    /// - Parameters:
    ///   - selection: A binding to the set of selected row IDs.
    ///   - sortOrder: A binding to the ordered sorting of columns.
    ///   - columns: The columns to display in the table.
    ///   - rows: The rows to display in the table.
    public init<Sort: SortComparator, Columns: TableColumnContent, Rows: TableRowContent>(
        selection: Binding<Set<Value.ID>>, sortOrder: Binding<[Sort]>,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns,
        @TableRowBuilder<Value> rows: () -> Rows
    ) where Sort.Compared == Value, Columns.TableRowValue == Value, Rows.TableRowValue == Value {
        self.init(
            of: Value.self, selection: selection, sortOrder: sortOrder, columns: columns, rows: rows)
    }
}
