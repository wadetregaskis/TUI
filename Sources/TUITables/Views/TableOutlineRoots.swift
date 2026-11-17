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

    /// The app's expansion, from `Table(_:children:expansion:)`, or `nil` for
    /// the table to keep its own. Not part of what makes two readings the same
    /// rows: a change to it makes a new outline over the same roots
    /// (``_TableOutlineCache``).
    let expansion: Binding<Set<Value.ID>>?

    @MainActor
    init<Data: RandomAccessCollection>(
        _ data: Data, children: KeyPath<Value, Data?>, expansion: Binding<Set<Value.ID>>? = nil
    ) where Data.Element == Value {
        values = Array(data)
        self.expansion = expansion
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
            other.values.withUnsafeBufferPointer { theirs in unsafe mine.baseAddress == theirs.baseAddress }
        }
    }
}

// MARK: - Flattening the roots

extension _TableOutline {
    /// Flattens a collection's roots: the roots as they are, and beneath each
    /// open branch its rows, in reading order.
    ///
    /// Only the branches among the roots are visited (`branches`, their
    /// indices); a leaf among the roots is given a leaf's row without being
    /// looked at, and where no branch is open the rows are the roots' own
    /// array, shared rather than copied.
    static func flattening(
        roots: _TableOutlineRoots<Value>, branches: [Int], expansion: _TableOutlineExpansion<Value>.Reading
    ) -> Flattening {
        var flat = Flattening()
        let leaf = Row(placement: Placement(depth: 0, disclosure: .leaf), parent: -1, branch: -1)
        // The first root not yet copied into the values, once a branch has
        // opened; and the first root not yet given a row.
        var start = 0
        var listed = 0
        var spliced = false
        for index in branches {
            let node = roots.node(roots.values[index])
            flat.rows += repeatElement(leaf, count: index - listed)
            listed = index + 1
            guard isOpen(node, in: expansion) else {
                flat.noteRow(node, depth: 0, parent: -1, isOpen: false)
                continue
            }
            if !spliced { flat.values.reserveCapacity(roots.values.count) }
            spliced = true
            flat.values += roots.values[start..<index]
            start = index + 1
            // The open branch and its rows, as a tree of one root.
            let beneath = flattening(_TableRowBranch(nodes: [node]), expansion: expansion)
            flat.values += beneath.values
            flat.appendPlacements(of: beneath)
        }
        flat.rows += repeatElement(leaf, count: roots.values.count - listed)
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
/// change; and the outline, made again when the roots change, and spliced when
/// the open branches do (``_TableOutline/splicing(_:to:expansion:)``): the
/// rows beneath a branch that opened or closed put in or taken out, the rest
/// kept, so a key that opens one branch of a big open tree costs that
/// branch's rows rather than every open one (finding M6-2, from tuitree).
@MainActor
final class _TableOutlineCache<Value: Identifiable> {
    private var roots: _TableOutlineRoots<Value>?
    private var branchIndices: [Int] = []
    private var outline: _TableOutline<Value>?
    private var expansionSeen: _TableOutlineExpansion<Value>.Reading?

    /// The rows the outlines made here have listed, all told — every row of
    /// one made whole, the rows put in or taken out of one spliced: what a
    /// pass adds to `RowWork.listed`, so a perf case sees a kept outline
    /// made again.
    private(set) var listed = 0

    /// The outline of `roots` with the branches `expansion` opens: the one
    /// made last, where neither has changed since.
    func outline(of roots: _TableOutlineRoots<Value>, expansion: _TableOutlineExpansion<Value>) -> _TableOutline<Value> {
        if self.roots.map({ !$0.hasSameRows(as: roots) }) ?? true {
            branchIndices = roots.values.indices.filter { roots.isBranch(roots.values[$0]) }
            self.roots = roots
            outline = nil
        }
        let reading = expansion.read()
        if let outline, let seen = expansionSeen {
            if seen == reading { return outline }
            if let changed = outline.changedIDs(from: seen, to: reading) {
                switch outline.splicing(changed, to: reading, expansion: expansion) {
                case .some(.unchanged):
                    outline.writes = []
                    expansionSeen = reading
                    return outline
                case .some(.spliced(let made, let count)):
                    self.outline = made
                    expansionSeen = reading
                    listed += count
                    return made
                case .none:
                    break
                }
            }
        }
        let made = _TableOutline(
            _TableOutline.flattening(roots: roots, branches: branchIndices, expansion: reading),
            expansion: expansion)
        outline = made
        expansionSeen = reading
        listed += made.values.count
        return made
    }
}
