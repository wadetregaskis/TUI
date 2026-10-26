//  🖥️ TUI — A Terminal UI framework for Swift
//  TableOutlineRoots.swift
//
//  The roots of `Table(_:children:)` kept as the collection they came from,
//  and the outline made from them kept from pass to pass while the roots and
//  the open branches are the same — so a hierarchical table costs what the
//  rows it draws cost, as a flat one does (decisions B-FP2-5).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation

// MARK: - The roots as data

/// The roots of a `Table(_:children:)`, as the collection they came from: a
/// node is made for a root only where the outline needs one — a branch —
/// where `TableOutlineGroupContent`'s rows are a node for every root, made
/// each time the table is.
struct _TableOutlineRoots<Value: Identifiable> {
    /// The roots, in order: the collection itself where it is an array, which
    /// costs no copy.
    let values: [Value]

    /// The key path to a row's children, which two readings must share to be
    /// the same rows.
    private let children: AnyKeyPath

    /// Whether a root has rows beneath it: children, even none.
    let isBranch: (Value) -> Bool

    /// A root's node, the rows beneath it made only when it opens.
    let node: @MainActor (Value) -> _TableRowNode<Value>

    /// Whether two readings over one array buffer are the same rows: so where
    /// the children are a stored property of a value type, and are values
    /// themselves. A class's rows, or children a computed property or a class
    /// collection gives, can change under one buffer, and are flattened again
    /// every pass.
    private let comparesByStorage: Bool

    @MainActor
    init<Data: RandomAccessCollection>(_ data: Data, children: KeyPath<Value, Data?>) where Data.Element == Value {
        values = Array(data)
        self.children = children
        isBranch = { $0[keyPath: children] != nil }
        node = { TableOutlineGroupContent<Data>.node($0, children: children) }
        comparesByStorage =
            MemoryLayout<Value>.offset(of: children) != nil
            && !(Value.self is AnyObject.Type) && !(Data.self is AnyObject.Type)
    }

    /// Whether these are the rows `other` is: one array buffer, held by both,
    /// so neither can have changed it in place, and one key path to the
    /// children.
    func hasSameRows(as other: Self) -> Bool {
        guard comparesByStorage, other.comparesByStorage, values.count == other.values.count,
            children == other.children
        else { return false }
        return values.withUnsafeBufferPointer { mine in
            other.values.withUnsafeBufferPointer { theirs in mine.baseAddress == theirs.baseAddress }
        }
    }
}

// MARK: - Flattening the roots

extension _TableOutline {
    /// Flattens a collection's roots: the roots as they are, and beneath each
    /// open branch its rows, in reading order.
    ///
    /// Only the branches among the roots are visited (`branches`, their
    /// indices); a leaf among the roots is not noted at all — a row with no
    /// placement draws as one (``prefix(for:)``) — and where no branch is open
    /// the rows are the roots' own array, shared rather than copied.
    static func flattening(
        roots: _TableOutlineRoots<Value>, branches: [Int], expansion: StateBox<Set<AnyHashable>>
    ) -> Flattening {
        var flat = Flattening()
        var start = 0
        var spliced = false
        for index in branches {
            let node = roots.node(roots.values[index])
            guard isOpen(node, in: expansion) else {
                flat.placements[node.value.id] = Placement(depth: 0, disclosure: .closed)
                flat.branches[node.value.id] = node
                continue
            }
            if !spliced { flat.values.reserveCapacity(roots.values.count) }
            spliced = true
            flat.values += roots.values[start..<index]
            start = index + 1
            // The open branch and its rows, as a tree of one root.
            let beneath = flattening(_TableRowBranch(nodes: [node]), expansion: expansion)
            flat.values += beneath.values
            flat.placements.merge(beneath.placements) { _, new in new }
            flat.parents.merge(beneath.parents) { _, new in new }
            flat.branches.merge(beneath.branches) { _, new in new }
        }
        if spliced {
            flat.values += roots.values[start...]
        } else {
            flat.values = roots.values
        }
        return flat
    }
}

// MARK: - Kept from pass to pass

/// A `Table(_:children:)`'s outline, kept at the table's identity while its
/// roots and its open branches are the same, so a pass that changes neither —
/// a cursor move, a scroll, a selection — makes none.
///
/// Two levels: the branches among the roots, found again only when the roots
/// change; and the outline, made again when the roots or the open branches do.
@MainActor
final class _TableOutlineCache<Value: Identifiable> {
    private var roots: _TableOutlineRoots<Value>?
    private var branchIndices: [Int] = []
    private var outline: _TableOutline<Value>?
    private var expansionSeen: Set<AnyHashable> = []
    private var expansionBox: ObjectIdentifier?

    /// The outline of `roots` with the branches `expansion` opens: the one
    /// made last, where neither has changed since.
    func outline(of roots: _TableOutlineRoots<Value>, expansion: StateBox<Set<AnyHashable>>) -> _TableOutline<Value> {
        if self.roots.map({ !$0.hasSameRows(as: roots) }) ?? true {
            branchIndices = roots.values.indices.filter { roots.isBranch(roots.values[$0]) }
            self.roots = roots
            outline = nil
        }
        if let outline, expansionBox == ObjectIdentifier(expansion), expansionSeen == expansion.value {
            return outline
        }
        let made = _TableOutline(
            _TableOutline.flattening(roots: roots, branches: branchIndices, expansion: expansion),
            expansion: expansion)
        outline = made
        expansionSeen = expansion.value
        expansionBox = ObjectIdentifier(expansion)
        return made
    }
}
