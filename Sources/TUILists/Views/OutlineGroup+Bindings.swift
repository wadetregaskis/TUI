//  🖥️ TUI — A Terminal UI framework for Swift
//  OutlineGroup+Bindings.swift
//
//  An outline of a tree held in a binding: each row handed a binding to its
//  node, writing back through the tree, as SwiftUI's four `Binding` forms of
//  `OutlineGroup` do.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension Binding {
    /// A node's children, as a binding to their collection, through a binding
    /// to the node — `nil` for a leaf, whose children are `nil`.
    ///
    /// A subscript rather than a function so that ``OutlineGroup`` can keep it
    /// as the key path it keeps for a tree of values: the binding forms walk
    /// the same tree, one binding per node, each child's binding derived from
    /// its parent's so a write reaches the root.
    subscript<Children>(outlineChildren children: WritableKeyPath<Value, Children?>) -> Binding<Children>? {
        Binding<Children>(self[dynamicMember: children])
    }
}

// MARK: - Initializers (a binding to a tree)

extension OutlineGroup where Leaf: View {
    /// Creates an outline rooted at the element a binding holds, handing each
    /// row a binding to its node.
    ///
    /// - Parameters:
    ///   - root: A binding to the element at the top of the tree.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    ///   - content: Builds a node's label from a binding to the node.
    public init<C, E>(
        _ root: Binding<E>,
        children: WritableKeyPath<E, C?>,
        @ViewBuilder content: @escaping (Binding<E>) -> Leaf
    )
    where
        Data == Binding<C>, ID == E.ID, C: MutableCollection, C: RandomAccessCollection, E: Identifiable,
        E == C.Element
    {
        self.init(roots: [root], id: \.id, children: \.[outlineChildren: children], content: content)
    }

    /// Creates an outline of the top-level elements a binding holds, handing
    /// each row a binding to its node.
    ///
    /// - Parameters:
    ///   - data: A binding to the elements at the top of the tree.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    ///   - content: Builds a node's label from a binding to the node.
    public init<C, E>(
        _ data: Binding<C>,
        children: WritableKeyPath<E, C?>,
        @ViewBuilder content: @escaping (Binding<E>) -> Leaf
    )
    where
        Data == Binding<C>, ID == E.ID, C: MutableCollection, C: RandomAccessCollection, E: Identifiable,
        E == C.Element
    {
        self.init(roots: Array(data), id: \.id, children: \.[outlineChildren: children], content: content)
    }

    /// Creates an outline rooted at the element a binding holds, keyed by an
    /// explicit id, handing each row a binding to its node.
    ///
    /// - Parameters:
    ///   - root: A binding to the element at the top of the tree.
    ///   - id: A key path to each element's stable identity.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    ///   - content: Builds a node's label from a binding to the node.
    public init<C, E>(
        _ root: Binding<E>,
        id: KeyPath<E, ID>,
        children: WritableKeyPath<E, C?>,
        @ViewBuilder content: @escaping (Binding<E>) -> Leaf
    ) where Data == Binding<C>, C: MutableCollection, C: RandomAccessCollection, E == C.Element {
        self.init(
            roots: [root], id: (\Binding<E>.wrappedValue).appending(path: id),
            children: \.[outlineChildren: children], content: content)
    }

    /// Creates an outline of the top-level elements a binding holds, keyed by
    /// an explicit id, handing each row a binding to its node.
    ///
    /// - Parameters:
    ///   - data: A binding to the elements at the top of the tree.
    ///   - id: A key path to each element's stable identity.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    ///   - content: Builds a node's label from a binding to the node.
    public init<C, E>(
        _ data: Binding<C>,
        id: KeyPath<E, ID>,
        children: WritableKeyPath<E, C?>,
        @ViewBuilder content: @escaping (Binding<E>) -> Leaf
    ) where Data == Binding<C>, C: MutableCollection, C: RandomAccessCollection, E == C.Element {
        self.init(
            roots: Array(data), id: (\Binding<E>.wrappedValue).appending(path: id),
            children: \.[outlineChildren: children], content: content)
    }
}
