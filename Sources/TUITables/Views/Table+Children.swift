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
    /// ## The app's own expansion (TUI only)
    ///
    /// SwiftUI's `Table(_:children:)` takes no expansion: its branches start
    /// closed and only the user opens them. TUI's every hierarchical table
    /// initializer also takes an `expansion:` binding, defaulted to `nil`, so a
    /// SwiftUI call site compiles and behaves as it does in SwiftUI. Handed
    /// one, the table opens exactly the branches whose IDs are in the set, and
    /// the user's opening and closing — Right, Left, ⌥Right, ⌥Left, Space, a
    /// click on a triangle — writes it:
    ///
    /// ```swift
    /// @State private var open: Set<File.ID> = [root.id]   // starts open
    ///
    /// Table(files, children: \.children, expansion: $open, selection: $selected) {
    ///     TableColumn("Name", value: \.name)
    /// }
    ///
    /// // Find: open a match's ancestors from code, then select it.
    /// open.formUnion(ancestors(of: match))
    /// selected = match.id
    /// ```
    ///
    /// It exists because a tree that starts open, or that code opens, could
    /// otherwise only be drawn as row content (`DisclosureTableRow` bound to
    /// an expansion the app keeps), whose rows are built again on every frame;
    /// a `Table(_:children:)` keeps its outline between frames and builds the
    /// rows it draws, with an expansion of the table's or of the app's alike.
    /// A SwiftUI port drops the argument and goes back to row content.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the table rows.
    ///   - children: A key path to a row's children, or `nil` for a leaf.
    ///   - expansion: A binding to the set of open branches' IDs, for the
    ///     app to keep and to open and close branches from code; `nil` for
    ///     the table to keep it, as SwiftUI's does. TUI only (see "The app's own
    ///     expansion" on `Table(_:children:expansion:columnCustomization:columns:)`).
    ///   - columnCustomization: A binding to the state of the columns.
    ///   - columns: The columns to display in the table.
    public init<Data: RandomAccessCollection, Columns: TableColumnContent>(
        _ data: Data, children: KeyPath<Value, Data?>,
        expansion: Binding<Set<Value.ID>>? = nil,
        columnCustomization: Binding<TableColumnCustomization<Value>>? = nil,
        @TableColumnBuilder<Value, Never> columns: () -> Columns
    ) where Data.Element == Value, Columns.TableRowValue == Value {
        self.init(
            outlineRoots: _TableOutlineRoots(data, children: children, expansion: expansion),
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
    ///   - expansion: A binding to the set of open branches' IDs, for the
    ///     app to keep and to open and close branches from code; `nil` for
    ///     the table to keep it, as SwiftUI's does. TUI only (see "The app's own
    ///     expansion" on `Table(_:children:expansion:columnCustomization:columns:)`).
    ///   - selection: A binding to the selected row's ID (`nil`: none).
    ///   - columnCustomization: A binding to the state of the columns.
    ///   - columns: The columns to display in the table.
    public init<Data: RandomAccessCollection, Columns: TableColumnContent>(
        _ data: Data, children: KeyPath<Data.Element, Data?>,
        expansion: Binding<Set<Value.ID>>? = nil, selection: Binding<Value.ID?>,
        columnCustomization: Binding<TableColumnCustomization<Value>>? = nil,
        @TableColumnBuilder<Value, Never> columns: () -> Columns
    ) where Data.Element == Value, Columns.TableRowValue == Value {
        self.init(
            outlineRoots: _TableOutlineRoots(data, children: children, expansion: expansion),
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
    ///   - expansion: A binding to the set of open branches' IDs, for the
    ///     app to keep and to open and close branches from code; `nil` for
    ///     the table to keep it, as SwiftUI's does. TUI only (see "The app's own
    ///     expansion" on `Table(_:children:expansion:columnCustomization:columns:)`).
    ///   - selection: A binding to the set of selected row IDs.
    ///   - columnCustomization: A binding to the state of the columns.
    ///   - columns: The columns to display in the table.
    public init<Data: RandomAccessCollection, Columns: TableColumnContent>(
        _ data: Data, children: KeyPath<Data.Element, Data?>,
        expansion: Binding<Set<Value.ID>>? = nil, selection: Binding<Set<Value.ID>>,
        columnCustomization: Binding<TableColumnCustomization<Value>>? = nil,
        @TableColumnBuilder<Value, Never> columns: () -> Columns
    ) where Data.Element == Value, Columns.TableRowValue == Value {
        self.init(
            outlineRoots: _TableOutlineRoots(data, children: children, expansion: expansion),
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
    ///   - expansion: A binding to the set of open branches' IDs, for the
    ///     app to keep and to open and close branches from code; `nil` for
    ///     the table to keep it, as SwiftUI's does. TUI only (see "The app's own
    ///     expansion" on `Table(_:children:expansion:columnCustomization:columns:)`).
    ///   - sortOrder: A binding to the ordered sorting of columns.
    ///   - columnCustomization: A binding to the state of the columns.
    ///   - columns: The columns to display in the table.
    public init<Data: RandomAccessCollection, Sort: SortComparator, Columns: TableColumnContent>(
        _ data: Data, children: KeyPath<Data.Element, Data?>,
        expansion: Binding<Set<Value.ID>>? = nil, sortOrder: Binding<[Sort]>,
        columnCustomization: Binding<TableColumnCustomization<Value>>? = nil,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns
    ) where Data.Element == Value, Sort.Compared == Value, Columns.TableRowValue == Value {
        self.init(
            outlineRoots: _TableOutlineRoots(data, children: children, expansion: expansion),
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
    ///   - expansion: A binding to the set of open branches' IDs, for the
    ///     app to keep and to open and close branches from code; `nil` for
    ///     the table to keep it, as SwiftUI's does. TUI only (see "The app's own
    ///     expansion" on `Table(_:children:expansion:columnCustomization:columns:)`).
    ///   - selection: A binding to the selected row's ID (`nil`: none).
    ///   - sortOrder: A binding to the ordered sorting of columns.
    ///   - columnCustomization: A binding to the state of the columns.
    ///   - columns: The columns to display in the table.
    public init<Data: RandomAccessCollection, Sort: SortComparator, Columns: TableColumnContent>(
        _ data: Data, children: KeyPath<Data.Element, Data?>,
        expansion: Binding<Set<Value.ID>>? = nil, selection: Binding<Value.ID?>,
        sortOrder: Binding<[Sort]>,
        columnCustomization: Binding<TableColumnCustomization<Value>>? = nil,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns
    ) where Data.Element == Value, Sort.Compared == Value, Columns.TableRowValue == Value {
        self.init(
            outlineRoots: _TableOutlineRoots(data, children: children, expansion: expansion),
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
    ///   - expansion: A binding to the set of open branches' IDs, for the
    ///     app to keep and to open and close branches from code; `nil` for
    ///     the table to keep it, as SwiftUI's does. TUI only (see "The app's own
    ///     expansion" on `Table(_:children:expansion:columnCustomization:columns:)`).
    ///   - selection: A binding to the set of selected row IDs.
    ///   - sortOrder: A binding to the ordered sorting of columns.
    ///   - columnCustomization: A binding to the state of the columns.
    ///   - columns: The columns to display in the table.
    public init<Data: RandomAccessCollection, Sort: SortComparator, Columns: TableColumnContent>(
        _ data: Data, children: KeyPath<Data.Element, Data?>,
        expansion: Binding<Set<Value.ID>>? = nil, selection: Binding<Set<Value.ID>>,
        sortOrder: Binding<[Sort]>,
        columnCustomization: Binding<TableColumnCustomization<Value>>? = nil,
        @TableColumnBuilder<Value, Sort> columns: () -> Columns
    ) where Data.Element == Value, Sort.Compared == Value, Columns.TableRowValue == Value {
        self.init(
            outlineRoots: _TableOutlineRoots(data, children: children, expansion: expansion),
            columns: tableColumns(of: columns()), single: nil, multi: selection,
            sortModel: _TableSortModel(sortOrder), customization: columnCustomization)
    }
}
