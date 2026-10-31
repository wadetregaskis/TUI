//  🖥️ TUI — A Terminal UI framework for Swift
//  List+BindingTree.swift
//
//  SwiftUI's `List(_:children:)` family over a binding to a tree: each row
//  handed a binding to its node, through an `OutlineGroup` of bindings.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// The binding twins of the hierarchical initializers in `List.swift`, one for
// each of them and of the two in `List+RequiredSelection.swift`, as SwiftUI
// declares eight. Each builds the `OutlineGroup` binding form, so a row's
// `Binding` writes into the node it draws, wherever in the tree it is.

extension List where Footer == EmptyView, SelectionValue == Int {
    /// Creates a list of a tree held in a binding, without selection.
    ///
    /// - Parameters:
    ///   - data: A binding to the elements at the top of the tree.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    ///   - rowContent: Builds the row view for each node, from a binding to it.
    public init<Data, RowContent: View>(
        _ data: Binding<Data>,
        children: WritableKeyPath<Data.Element, Data?>,
        @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent
    )
    where
        Content == OutlineGroup<Binding<Data>, Data.Element.ID, RowContent>, Data: MutableCollection,
        Data: RandomAccessCollection, Data.Element: Identifiable
    {
        self.init { OutlineGroup(data, children: children, content: rowContent) }
    }

    /// Creates a list of a tree held in a binding, keyed by an explicit id,
    /// without selection.
    ///
    /// - Parameters:
    ///   - data: A binding to the elements at the top of the tree.
    ///   - id: A key path to each element's stable identity.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    ///   - rowContent: Builds the row view for each node, from a binding to it.
    public init<Data, ID: Hashable, RowContent: View>(
        _ data: Binding<Data>,
        id: KeyPath<Data.Element, ID>,
        children: WritableKeyPath<Data.Element, Data?>,
        @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent
    )
    where
        Content == OutlineGroup<Binding<Data>, ID, RowContent>, Data: MutableCollection,
        Data: RandomAccessCollection
    {
        self.init { OutlineGroup(data, id: id, children: children, content: rowContent) }
    }
}

extension List where Footer == EmptyView {
    /// Creates a list of a tree held in a binding, with single selection.
    ///
    /// - Parameters:
    ///   - data: A binding to the elements at the top of the tree.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    ///   - selection: A binding to the selected row's value (`nil` = none).
    ///   - rowContent: Builds the row view for each node, from a binding to it.
    public init<Data, RowContent: View>(
        _ data: Binding<Data>,
        children: WritableKeyPath<Data.Element, Data?>,
        selection: Binding<SelectionValue?>?,
        @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent
    )
    where
        Content == OutlineGroup<Binding<Data>, Data.Element.ID, RowContent>, Data: MutableCollection,
        Data: RandomAccessCollection, Data.Element: Identifiable
    {
        self.init(selection: selection) { OutlineGroup(data, children: children, content: rowContent) }
    }

    /// Creates a list of a tree held in a binding, with multi-selection.
    ///
    /// - Parameters:
    ///   - data: A binding to the elements at the top of the tree.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    ///   - selection: A binding to the set of selected rows' values.
    ///   - rowContent: Builds the row view for each node, from a binding to it.
    public init<Data, RowContent: View>(
        _ data: Binding<Data>,
        children: WritableKeyPath<Data.Element, Data?>,
        selection: Binding<Set<SelectionValue>>?,
        @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent
    )
    where
        Content == OutlineGroup<Binding<Data>, Data.Element.ID, RowContent>, Data: MutableCollection,
        Data: RandomAccessCollection, Data.Element: Identifiable
    {
        self.init(selection: selection) { OutlineGroup(data, children: children, content: rowContent) }
    }

    /// Creates a list of a tree held in a binding, with single selection that
    /// cannot be emptied — see `List+RequiredSelection.swift`.
    ///
    /// - Parameters:
    ///   - data: A binding to the elements at the top of the tree.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    ///   - selection: A binding to the selected row's value. Activating the
    ///     selected row again leaves it selected.
    ///   - rowContent: Builds the row view for each node, from a binding to it.
    @_disfavoredOverload
    public init<Data, RowContent: View>(
        _ data: Binding<Data>,
        children: WritableKeyPath<Data.Element, Data?>,
        selection: Binding<SelectionValue>,
        @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent
    )
    where
        Content == OutlineGroup<Binding<Data>, Data.Element.ID, RowContent>, Data: MutableCollection,
        Data: RandomAccessCollection, Data.Element: Identifiable
    {
        self.init(data, children: children, selection: Binding<SelectionValue?>(selection), rowContent: rowContent)
    }

    /// Creates a list of a tree held in a binding, keyed by an explicit id,
    /// with single selection.
    ///
    /// - Parameters:
    ///   - data: A binding to the elements at the top of the tree.
    ///   - id: A key path to each element's stable identity.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    ///   - selection: A binding to the selected row's value (`nil` = none).
    ///   - rowContent: Builds the row view for each node, from a binding to it.
    public init<Data, ID: Hashable, RowContent: View>(
        _ data: Binding<Data>,
        id: KeyPath<Data.Element, ID>,
        children: WritableKeyPath<Data.Element, Data?>,
        selection: Binding<SelectionValue?>?,
        @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent
    )
    where
        Content == OutlineGroup<Binding<Data>, ID, RowContent>, Data: MutableCollection,
        Data: RandomAccessCollection
    {
        self.init(selection: selection) { OutlineGroup(data, id: id, children: children, content: rowContent) }
    }

    /// Creates a list of a tree held in a binding, keyed by an explicit id,
    /// with multi-selection.
    ///
    /// - Parameters:
    ///   - data: A binding to the elements at the top of the tree.
    ///   - id: A key path to each element's stable identity.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    ///   - selection: A binding to the set of selected rows' values.
    ///   - rowContent: Builds the row view for each node, from a binding to it.
    public init<Data, ID: Hashable, RowContent: View>(
        _ data: Binding<Data>,
        id: KeyPath<Data.Element, ID>,
        children: WritableKeyPath<Data.Element, Data?>,
        selection: Binding<Set<SelectionValue>>?,
        @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent
    )
    where
        Content == OutlineGroup<Binding<Data>, ID, RowContent>, Data: MutableCollection,
        Data: RandomAccessCollection
    {
        self.init(selection: selection) { OutlineGroup(data, id: id, children: children, content: rowContent) }
    }

    /// Creates a list of a tree held in a binding, keyed by an explicit id,
    /// with single selection that cannot be emptied.
    ///
    /// - Parameters:
    ///   - data: A binding to the elements at the top of the tree.
    ///   - id: A key path to each element's stable identity.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    ///   - selection: A binding to the selected row's value. Activating the
    ///     selected row again leaves it selected.
    ///   - rowContent: Builds the row view for each node, from a binding to it.
    @_disfavoredOverload
    public init<Data, ID: Hashable, RowContent: View>(
        _ data: Binding<Data>,
        id: KeyPath<Data.Element, ID>,
        children: WritableKeyPath<Data.Element, Data?>,
        selection: Binding<SelectionValue>,
        @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent
    )
    where
        Content == OutlineGroup<Binding<Data>, ID, RowContent>, Data: MutableCollection,
        Data: RandomAccessCollection
    {
        self.init(
            data, id: id, children: children, selection: Binding<SelectionValue?>(selection), rowContent: rowContent)
    }
}
