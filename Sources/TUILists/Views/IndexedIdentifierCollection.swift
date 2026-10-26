//  🖥️ TUI — A Terminal UI framework for Swift
//  IndexedIdentifierCollection.swift
//
//  The collection an editable `ForEach` iterates: each position of the bound
//  collection, with the identity of the element there.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// A collection of the positions of another collection, each with the
/// identity of the element at it.
///
/// You don't create this: it is the `Data` of a ``ForEach`` built from a
/// binding with `editActions:` — `ForEach($items, editActions: .all)` — which
/// hands each row a binding to the element at one of these positions and
/// keys the row by the element's identity.
///
/// It reads the bound collection as it was when the `ForEach` was built and
/// computes each element's identity when asked, so building one costs nothing
/// however long the collection is.
public struct IndexedIdentifierCollection<Base: Collection, ID: Hashable>: Collection {
    /// One position of the base collection, and the identity of the element
    /// there. Opaque, as SwiftUI's is.
    public struct Element {
        /// The position in the base collection.
        let index: Base.Index
        /// The identity of the element at ``index``.
        let id: ID
    }

    /// A position in the base collection.
    public typealias Index = Base.Index

    /// The positions of this collection.
    public typealias Indices = DefaultIndices<Self>

    /// An iterator over the positions.
    public typealias Iterator = IndexingIterator<Self>

    /// The collection whose positions these are.
    let base: Base

    /// The path from an element to its identity.
    let idKeyPath: KeyPath<Base.Element, ID>

    init(_ base: Base, id idKeyPath: KeyPath<Base.Element, ID>) {
        self.base = base
        self.idKeyPath = idKeyPath
    }

    /// The position of the first element.
    public var startIndex: Index { base.startIndex }

    /// The position one past the last element.
    public var endIndex: Index { base.endIndex }

    /// The position after `i`.
    public func index(after i: Index) -> Index { base.index(after: i) }

    /// The position `position`, with the identity of the element there.
    public subscript(position: Index) -> Element {
        Element(index: position, id: base[position][keyPath: idKeyPath])
    }
}

extension IndexedIdentifierCollection: BidirectionalCollection where Base: BidirectionalCollection {
    /// The position before `i`.
    public func index(before i: Index) -> Index { base.index(before: i) }
}

extension IndexedIdentifierCollection: RandomAccessCollection where Base: RandomAccessCollection {}
