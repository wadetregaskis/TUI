//  🖥️ TUI — A Terminal UI framework for Swift
//  List+RequiredSelection.swift
//
//  SwiftUI's `List(selection: Binding<SelectionValue>)` family: single
//  selection that cannot be emptied.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// Each overload is the matching optional-selection initializer, handed
// `Binding<SelectionValue?>(selection)`: the projection that reads the value as
// always present and drops a `nil` written to it. The list's own rule —
// activating the selected row again clears the selection — therefore writes
// nothing, and the row stays selected, as SwiftUI's "selecting a single row
// that cannot be deselected" says.
//
// Every one is `@_disfavoredOverload`, as SwiftUI declares all ten of its own.
// That is what keeps `$selection` for an optional on the optional form (with
// `SelectionValue` the wrapped type, not the optional) and `$selection` for a
// `Set` on the multi-selection form; measured against SwiftUI's own
// overloads (Xcode 26.3, macOS 26.2 SDK). SwiftUI's two forms over a binding
// to a tree (`List($items, children: …)`) are in `List+BindingTree.swift`,
// with their optional and multi-selection twins.

extension List where Footer == EmptyView {
    /// Creates a list with single selection that cannot be emptied.
    ///
    /// - Parameters:
    ///   - selection: A binding to the selected row's id. Activating the
    ///     selected row again leaves it selected.
    ///   - content: A ViewBuilder that defines the list content.
    @_disfavoredOverload
    public init(selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.init(selection: Binding<SelectionValue?>(selection), content: content)
    }

    /// Creates a list from an `Identifiable` collection with single selection
    /// that cannot be emptied.
    ///
    /// - Parameters:
    ///   - data: The collection to show, one row per element.
    ///   - selection: A binding to the selected element's id.
    ///   - rowContent: Builds the row view for each element.
    @_disfavoredOverload
    public init<Data: RandomAccessCollection, RowContent: View>(
        _ data: Data,
        selection: Binding<SelectionValue>,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, Data.Element.ID, RowContent>,
            Data.Element: Identifiable, SelectionValue == Data.Element.ID {
        self.init(data, selection: Binding<SelectionValue?>(selection), rowContent: rowContent)
    }

    /// Creates a list keyed by an explicit id with single selection that
    /// cannot be emptied.
    ///
    /// - Parameters:
    ///   - data: The collection to show, one row per element.
    ///   - id: A key path to each element's stable identity.
    ///   - selection: A binding to the selected id.
    ///   - rowContent: Builds the row view for each element.
    @_disfavoredOverload
    public init<Data: RandomAccessCollection, RowContent: View>(
        _ data: Data,
        id: KeyPath<Data.Element, SelectionValue>,
        selection: Binding<SelectionValue>,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, SelectionValue, RowContent> {
        self.init(data, id: id, selection: Binding<SelectionValue?>(selection), rowContent: rowContent)
    }

    /// Creates a list of a tree with single selection that cannot be emptied.
    ///
    /// - Parameters:
    ///   - data: The elements at the top of the tree.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    ///   - selection: A binding to the selected node's id.
    ///   - rowContent: Builds the row view for each node.
    @_disfavoredOverload
    public init<Data: RandomAccessCollection, RowContent: View>(
        _ data: Data,
        children: KeyPath<Data.Element, Data?>,
        selection: Binding<SelectionValue>,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == OutlineGroup<Data, Data.Element.ID, RowContent>,
            Data.Element: Identifiable, SelectionValue == Data.Element.ID {
        self.init(data, children: children, selection: Binding<SelectionValue?>(selection), rowContent: rowContent)
    }

    /// Creates a list of a tree keyed by an explicit id, with single selection
    /// that cannot be emptied.
    ///
    /// - Parameters:
    ///   - data: The elements at the top of the tree.
    ///   - id: A key path to each element's stable identity.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    ///   - selection: A binding to the selected node's id.
    ///   - rowContent: Builds the row view for each node.
    @_disfavoredOverload
    public init<Data: RandomAccessCollection, RowContent: View>(
        _ data: Data,
        id: KeyPath<Data.Element, SelectionValue>,
        children: KeyPath<Data.Element, Data?>,
        selection: Binding<SelectionValue>,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == OutlineGroup<Data, SelectionValue, RowContent> {
        self.init(
            data, id: id, children: children, selection: Binding<SelectionValue?>(selection), rowContent: rowContent)
    }

    /// Creates a list over a binding to a collection of identifiable elements,
    /// performing the named edits on the collection, with single selection
    /// that cannot be emptied.
    ///
    /// - Parameters:
    ///   - data: The collection to show and edit, one row per element.
    ///   - editActions: The edits the list performs on `data`.
    ///   - selection: A binding to the selected element's id.
    ///   - rowContent: Builds the row for each element, from a binding to it.
    @_disfavoredOverload
    public init<Data, RowContent: View>(
        _ data: Binding<Data>,
        editActions: EditActions<Data>,
        selection: Binding<SelectionValue>,
        @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent
    )
    where
        Content == ForEach<IndexedIdentifierCollection<Data, Data.Element.ID>, Data.Element.ID, RowContent>,
        Data: MutableCollection, Data: RandomAccessCollection, Data: RangeReplaceableCollection,
        Data.Index == Int, Data.Element: Identifiable, SelectionValue == Data.Element.ID
    {
        self.init(data, editActions: editActions, selection: Binding<SelectionValue?>(selection), rowContent: rowContent)
    }

    /// Creates a list over a binding to a collection whose elements are
    /// identified by a key path, performing the named edits on the collection,
    /// with single selection that cannot be emptied.
    ///
    /// - Parameters:
    ///   - data: The collection to show and edit, one row per element.
    ///   - id: The key path to each element's stable identity.
    ///   - editActions: The edits the list performs on `data`.
    ///   - selection: A binding to the selected id.
    ///   - rowContent: Builds the row for each element, from a binding to it.
    @_disfavoredOverload
    public init<Data, RowContent: View>(
        _ data: Binding<Data>,
        id: KeyPath<Data.Element, SelectionValue>,
        editActions: EditActions<Data>,
        selection: Binding<SelectionValue>,
        @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent
    )
    where
        Content == ForEach<IndexedIdentifierCollection<Data, SelectionValue>, SelectionValue, RowContent>,
        Data: MutableCollection, Data: RandomAccessCollection, Data: RangeReplaceableCollection,
        Data.Index == Int
    {
        self.init(
            data, id: id, editActions: editActions, selection: Binding<SelectionValue?>(selection),
            rowContent: rowContent)
    }
}

extension List where Footer == EmptyView, SelectionValue == Int {
    /// Creates a list over a range of integers with single selection that
    /// cannot be emptied.
    ///
    /// - Parameters:
    ///   - data: The integers to show, one row each.
    ///   - selection: A binding to the selected integer.
    ///   - rowContent: Builds the row view for each integer.
    @_disfavoredOverload
    public init<RowContent: View>(
        _ data: Range<Int>, selection: Binding<Int>, @ViewBuilder rowContent: @escaping (Int) -> RowContent
    ) where Content == ForEach<Range<Int>, Int, RowContent> {
        self.init(data, selection: Binding<Int?>(selection), rowContent: rowContent)
    }
}
