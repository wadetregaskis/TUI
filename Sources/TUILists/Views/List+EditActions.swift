//  🖥️ TUI — A Terminal UI framework for Swift
//  List+EditActions.swift
//
//  SwiftUI's `List(_:editActions:rowContent:)` family: a list over a binding to
//  a collection, which moves and deletes the collection's elements itself.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// Each overload is the matching data-driven initializer with an editable
// `ForEach` inside — `ForEach(_:editActions:content:)`, whose loop reorders and
// removes through the binding — so the rows, the windowing and the editing
// gestures are exactly what that `ForEach` gets inside any `List`. The
// collection must be `Int`-indexed and able to shrink, the constraint
// `ForEach(_:editActions:content:)` carries (see there for why).

extension List where Footer == EmptyView, SelectionValue == Int {
    /// Creates a list over a binding to a collection of identifiable elements,
    /// performing the named edits on the collection, without selection.
    ///
    /// ```swift
    /// List($items, editActions: .all) { $item in
    ///     TextField("Name", text: $item.name)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - data: The collection to show and edit, one row per element.
    ///   - editActions: The edits the list performs on `data`: moving rows,
    ///     deleting them, or both.
    ///   - rowContent: Builds the row for each element, from a binding to it.
    public init<Data, RowContent: View>(
        _ data: Binding<Data>,
        editActions: EditActions<Data>,
        @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent
    )
    where
        Content == ForEach<IndexedIdentifierCollection<Data, Data.Element.ID>, Data.Element.ID, RowContent>,
        Data: MutableCollection, Data: RandomAccessCollection, Data: RangeReplaceableCollection,
        Data.Index == Int, Data.Element: Identifiable
    {
        self.init { ForEach(data, editActions: editActions, content: rowContent) }
    }

    /// Creates a list over a binding to a collection whose elements are
    /// identified by a key path, performing the named edits on the collection,
    /// without selection.
    ///
    /// - Parameters:
    ///   - data: The collection to show and edit, one row per element.
    ///   - id: The key path to each element's stable identity.
    ///   - editActions: The edits the list performs on `data`.
    ///   - rowContent: Builds the row for each element, from a binding to it.
    public init<Data, ID: Hashable, RowContent: View>(
        _ data: Binding<Data>,
        id: KeyPath<Data.Element, ID>,
        editActions: EditActions<Data>,
        @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent
    )
    where
        Content == ForEach<IndexedIdentifierCollection<Data, ID>, ID, RowContent>,
        Data: MutableCollection, Data: RandomAccessCollection, Data: RangeReplaceableCollection,
        Data.Index == Int
    {
        self.init { ForEach(data, id: id, editActions: editActions, content: rowContent) }
    }
}

extension List where Footer == EmptyView {
    /// Creates a list over a binding to a collection of identifiable elements,
    /// performing the named edits on the collection, with single selection.
    ///
    /// - Parameters:
    ///   - data: The collection to show and edit, one row per element.
    ///   - editActions: The edits the list performs on `data`.
    ///   - selection: A binding to the selected element's id (`nil` = none),
    ///     or `nil` for a list that selects nothing.
    ///   - rowContent: Builds the row for each element, from a binding to it.
    public init<Data, RowContent: View>(
        _ data: Binding<Data>,
        editActions: EditActions<Data>,
        selection: Binding<SelectionValue?>?,
        @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent
    )
    where
        Content == ForEach<IndexedIdentifierCollection<Data, Data.Element.ID>, Data.Element.ID, RowContent>,
        Data: MutableCollection, Data: RandomAccessCollection, Data: RangeReplaceableCollection,
        Data.Index == Int, Data.Element: Identifiable, SelectionValue == Data.Element.ID
    {
        self.init(selection: selection) { ForEach(data, editActions: editActions, content: rowContent) }
    }

    /// Creates a list over a binding to a collection of identifiable elements,
    /// performing the named edits on the collection, with multi-selection.
    ///
    /// - Parameters:
    ///   - data: The collection to show and edit, one row per element.
    ///   - editActions: The edits the list performs on `data`.
    ///   - selection: A binding to the set of selected element ids, or `nil`
    ///     for a list that selects nothing.
    ///   - rowContent: Builds the row for each element, from a binding to it.
    public init<Data, RowContent: View>(
        _ data: Binding<Data>,
        editActions: EditActions<Data>,
        selection: Binding<Set<SelectionValue>>?,
        @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent
    )
    where
        Content == ForEach<IndexedIdentifierCollection<Data, Data.Element.ID>, Data.Element.ID, RowContent>,
        Data: MutableCollection, Data: RandomAccessCollection, Data: RangeReplaceableCollection,
        Data.Index == Int, Data.Element: Identifiable, SelectionValue == Data.Element.ID
    {
        self.init(selection: selection) { ForEach(data, editActions: editActions, content: rowContent) }
    }

    /// Creates a list over a binding to a collection whose elements are
    /// identified by a key path, performing the named edits on the collection,
    /// with single selection.
    ///
    /// The id key path's value type is the selection type, so `selection`
    /// binds to the same id the rows are keyed by.
    ///
    /// - Parameters:
    ///   - data: The collection to show and edit, one row per element.
    ///   - id: The key path to each element's stable identity.
    ///   - editActions: The edits the list performs on `data`.
    ///   - selection: A binding to the selected id (`nil` = none), or `nil`
    ///     for a list that selects nothing.
    ///   - rowContent: Builds the row for each element, from a binding to it.
    public init<Data, RowContent: View>(
        _ data: Binding<Data>,
        id: KeyPath<Data.Element, SelectionValue>,
        editActions: EditActions<Data>,
        selection: Binding<SelectionValue?>?,
        @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent
    )
    where
        Content == ForEach<IndexedIdentifierCollection<Data, SelectionValue>, SelectionValue, RowContent>,
        Data: MutableCollection, Data: RandomAccessCollection, Data: RangeReplaceableCollection,
        Data.Index == Int
    {
        self.init(selection: selection) {
            ForEach(data, id: id, editActions: editActions, content: rowContent)
        }
    }

    /// Creates a list over a binding to a collection whose elements are
    /// identified by a key path, performing the named edits on the collection,
    /// with multi-selection.
    ///
    /// - Parameters:
    ///   - data: The collection to show and edit, one row per element.
    ///   - id: The key path to each element's stable identity.
    ///   - editActions: The edits the list performs on `data`.
    ///   - selection: A binding to the set of selected ids, or `nil` for a
    ///     list that selects nothing.
    ///   - rowContent: Builds the row for each element, from a binding to it.
    public init<Data, RowContent: View>(
        _ data: Binding<Data>,
        id: KeyPath<Data.Element, SelectionValue>,
        editActions: EditActions<Data>,
        selection: Binding<Set<SelectionValue>>?,
        @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent
    )
    where
        Content == ForEach<IndexedIdentifierCollection<Data, SelectionValue>, SelectionValue, RowContent>,
        Data: MutableCollection, Data: RandomAccessCollection, Data: RangeReplaceableCollection,
        Data.Index == Int
    {
        self.init(selection: selection) {
            ForEach(data, id: id, editActions: editActions, content: rowContent)
        }
    }
}
