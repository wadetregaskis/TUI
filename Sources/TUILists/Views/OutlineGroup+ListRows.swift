//  🖥️ TUI — A Terminal UI framework for Swift
//  OutlineGroup+ListRows.swift
//
//  An outline's rows in a `List`: windowed, as a `ForEach`'s are. The list
//  asks how many rows there are and what each is called, and builds a row's
//  box only for the rows it walks, about a screenful. The rows that show are
//  kept at the outline's identity from pass to pass while its roots and its
//  open branches are the same, so a scroll or a cursor move walks no tree.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

// MARK: - Kept from pass to pass

/// Where an outline keeps its state, under its identity
/// (``OutlineGroup/expansion(context:)``).
enum OutlineStateIndex {
    /// The open branches' ids.
    static let expansion = 0
    /// The rows that show (``OutlineVisibleNodes``).
    static let visibleNodes = 1
}

/// An outline's visible nodes, kept at its identity while its roots and its
/// open branches are the same: a pass that changes neither, a scroll, a
/// cursor move or a selection, flattens nothing, and the list then builds the
/// rows it draws and no others. As `Table(_:children:)`'s outline is kept
/// (`_TableOutlineCache`, decisions B-FP2-5), and by the same test of
/// "the same roots": one array buffer, held here so that no other array can
/// take its address, of values whose children are stored in them. Any other
/// tree (a class's nodes, children a computed property gives, the bindings of
/// `OutlineGroup($tree, children:)`) can change under one buffer, and is
/// flattened again every pass, still drawing only the rows on screen.
///
/// Not actor-isolated, as ``OutlineActivation`` is not: the disclosure
/// closures read it from key dispatch, and the render loop is the only writer.
final class OutlineVisibleNodes<Element, ID: Hashable> {
    /// The rows that show, in reading order.
    private(set) var nodes: [OutlineNode<Element, ID>] = []

    /// The roots the nodes were flattened from, or `nil` when they cannot be
    /// told apart from another tree's (see above), and are not kept.
    private var roots: [Element]?
    private var keyPaths: [AnyKeyPath] = []
    private var expansionSeen: Set<ID> = []
    private var expansionBox: ObjectIdentifier?

    /// Each row's index by the id the list knows it by, made by the first
    /// keystroke that asks after the nodes change, and the id type it is for.
    private var rowIndex: (type: ObjectIdentifier, indices: [AnyHashable: Int])?

    /// The nodes of `roots` with `expansion`'s branches open: those of the
    /// last call where nothing has changed since, else `flatten()`'s.
    func nodes(
        roots: [Element], keyPaths: [AnyKeyPath], comparesByStorage: Bool, expansion: StateBox<Set<ID>>,
        flatten: () -> [OutlineNode<Element, ID>]
    ) -> [OutlineNode<Element, ID>] {
        if let kept = self.roots, comparesByStorage, self.keyPaths == keyPaths, kept.count == roots.count,
            expansionBox == ObjectIdentifier(expansion), expansionSeen == expansion.value,
            kept.withUnsafeBufferPointer({ mine in
                roots.withUnsafeBufferPointer { theirs in unsafe mine.baseAddress == theirs.baseAddress }
            }) {
            return nodes
        }
        nodes = flatten()
        self.roots = comparesByStorage ? roots : nil
        self.keyPaths = keyPaths
        expansionSeen = expansion.value
        expansionBox = ObjectIdentifier(expansion)
        rowIndex = nil
        return nodes
    }

    /// The index of the row the list knows by `rowID`, where each row is named
    /// by `names`. Found from a map made once per flattening, by the first
    /// keystroke that asks: a frame asks nothing.
    func index(of rowID: AnyHashable, names: any OutlineRowNaming) -> Int? {
        if let rowIndex, rowIndex.type == names.idType { return rowIndex.indices[rowID] }
        var indices: [AnyHashable: Int] = [:]
        indices.reserveCapacity(nodes.count)
        for index in nodes.indices {
            guard let id = names.rowID(of: nodes, at: index) else { continue }
            indices[id] = indices[id] ?? index
        }
        rowIndex = (names.idType, indices)
        return indices[rowID]
    }
}

/// What a list calls an outline's rows, for one type of list id: the node's id
/// where it is one, else the row's index — a list with no selection binding is
/// keyed by `Int`, so its rows are POSITIONS. A value rather than a closure
/// over the id type, so the disclosure closures, which key dispatch calls, hold
/// no generic metatype (SE-0470).
protocol OutlineRowNaming {
    /// The id type, telling one list's names from another's.
    var idType: ObjectIdentifier { get }

    /// The name of `nodes[index]`, or `nil` where it has none of this type.
    func rowID<Element, ID>(of nodes: [OutlineNode<Element, ID>], at index: Int) -> AnyHashable?
}

/// ``OutlineRowNaming`` for ids of type `RowID`.
struct OutlineRowNames<RowID: Hashable>: OutlineRowNaming {
    var idType: ObjectIdentifier { ObjectIdentifier(RowID.self) }

    func rowID<Element, ID>(of nodes: [OutlineNode<Element, ID>], at index: Int) -> AnyHashable? {
        guard let id = typed(nodes, index) else { return nil }
        return AnyHashable(id)
    }

    /// The name, as the list's own type.
    func typed<Element, ID>(_ nodes: [OutlineNode<Element, ID>], _ index: Int) -> RowID? {
        (nodes[index].id as? RowID) ?? (index as? RowID)
    }
}

// MARK: - The rows

@MainActor extension OutlineGroup: WindowedOutlineListRows where Leaf: View {
    package func windowedListRows<RowID: Hashable>(context: RenderContext) -> OutlineListRows<RowID>? {
        guard windowsListRows else { return nil }
        let rows: OutlineListRows<RowID> = listRows(context: context)
        // Row 0's answer decides the whole list, as a `ForEach`'s does: every
        // node's id is of one type, so the cast that works for one works for all.
        // swiftlint:disable:next empty_count
        guard rows.count == 0 || rows.rowID(0) != nil else { return nil }  // `count` is an Int, not a Collection's
        return rows
    }

    /// The rows that show, as the list reads them, with the disclosure
    /// installed for this pass's rows.
    func listRows<RowID: Hashable>(context: RenderContext) -> OutlineListRows<RowID> {
        let expansion = expansion(context: context)
        let kept = visibleNodes(context: context, expansion: expansion)
        // The disclosure has to be reachable from whichever id the list hands
        // back, so the rows and the keys name the rows alike.
        let names = OutlineRowNames<RowID>()
        installActivation(kept, names: names, expansion: expansion)
        // This pass's nodes, not the kept object, which a later pass may
        // flatten again under a list still holding these rows.
        let rows = kept.nodes
        return OutlineListRows(
            count: rows.count, rowID: { index in names.typed(rows, index) },
            make: { index in listRowContent(for: rows[index], expansion: expansion, context: context) })
    }

    /// The kept visible nodes, brought up to date for this pass.
    private func visibleNodes(
        context: RenderContext, expansion: StateBox<Set<ID>>
    ) -> OutlineVisibleNodes<Data.Element, ID> {
        let identity = context.withChildIdentity(erasedType: Self.self, key: "outline").identity
        let kept =
            context.stateStorage?.storage(
                for: StateStorage.StateKey(identity: identity, propertyIndex: OutlineStateIndex.visibleNodes),
                default: OutlineVisibleNodes<Data.Element, ID>()
            ).value ?? OutlineVisibleNodes()
        // A tree of values whose children are stored in them: then one buffer
        // is one tree (see `OutlineVisibleNodes`).
        let comparesByStorage =
            MemoryLayout<Data.Element>.offset(of: childrenKeyPath) != nil
            && !(Data.Element.self is AnyObject.Type) && !(Data.self is AnyObject.Type)
        _ = kept.nodes(
            roots: roots, keyPaths: [idKeyPath, childrenKeyPath], comparesByStorage: comparesByStorage,
            expansion: expansion
        ) { visibleNodes(expanded: expansion.value) }
        return kept
    }

    /// One row's box: its size and its drawing, both made only when the list
    /// asks for them.
    private func listRowContent(
        for node: Node, expansion: StateBox<Set<ID>>, context: RenderContext
    ) -> LazyListRowContent {
        context.renderCache?.rowWork.listed += 1  // see `RowWork.listed`
        let view = row(for: node, expansion: expansion, rowOwnsFocus: true)
        let rowContext = context.withChildIdentity(
            erasedType: _OutlineRow<Data.Element, ID, Leaf>.self, key: identityKey(node.id))
        return LazyListRowContent(
            identity: rowContext.identity,
            carriesBadge: false,
            measure: {
                let proposal = ProposedViewSize(width: rowContext.availableWidth, height: nil)
                return (measureChild(view, proposal: proposal, context: rowContext), rowContext.availableWidth)
            },
            render: { placement, prominence in
                var rowContext = rowContext
                rowContext.gradientFrame = placement ?? rowContext.gradientFrame
                // As a `ForEach` row's render applies it — see there.
                if prominence != .standard {
                    rowContext.environment.backgroundProminence = prominence
                }
                return (TUIView.renderToBuffer(view, context: rowContext), nil)
            })
    }

    /// Points the list's disclosure keys at this pass's rows.
    ///
    /// A row is found from the id the list hands back through a map the
    /// first keystroke makes (``OutlineVisibleNodes/index(of:names:)``), not
    /// one made each pass: a pass that takes no key pays nothing for it. The
    /// kept nodes are read as they are when the key arrives: the ones the last
    /// pass drew, which the list's ids name.
    private func installActivation(
        _ kept: OutlineVisibleNodes<Data.Element, ID>, names: any OutlineRowNaming, expansion: StateBox<Set<ID>>
    ) {
        let branchesUnder = subtreeBranchWalk()
        activation.parentOf = { erased in
            guard let index = kept.index(of: erased, names: names) else { return nil }
            let parent = kept.nodes[index].parent
            return parent < 0 ? nil : names.rowID(of: kept.nodes, at: parent)
        }
        activation.apply = { erased, target, includingDescendants in
            // A leaf, and an id this pass's rows do not know, let the key fall
            // through.
            guard let index = kept.index(of: erased, names: names), kept.nodes[index].isBranch else { return false }
            let node = kept.nodes[index]
            // The ELEMENT, not just its id: a recursive open or close walks a
            // subtree that is mostly not on screen, whose closed branches were
            // never flattened, and the element is what still knows where they
            // are.
            let all = includingDescendants ? branchesUnder(node.element) : [node.id]
            // A recursive gesture takes its DIRECTION from the node it was
            // aimed at, then imposes that one state on the whole subtree —
            // rather than toggling each branch to its own opposite, which
            // would open half a tree and close the other half.
            let wanted = target ?? !expansion.value.contains(node.id)
            let before = expansion.value.count
            if wanted {
                expansion.value.formUnion(all)
            } else {
                expansion.value.subtract(all)
            }
            return expansion.value.count != before
        }
    }
}

// MARK: - Outlines inside sections

/// The outlines inside a list's sections, as one: each opens the rows it knows
/// and walks out of them, and a row none knows lets the key fall through.
///
/// A list asks the view its rows came from to open a row, which for a section
/// is the `Section`, and a section opens nothing: so Left, Right and their
/// Option forms did nothing to an outline inside one. The section hands its
/// outline up instead (`SectionContentRows.rowsContent`), and the list keeps
/// every section's (``RowSource/sectionOutlines``).
@MainActor
struct SectionOutlines: OutlineRowActivating {
    let outlines: [any OutlineRowActivating]

    /// The outlines as one, or `nil` where there are none; the outline itself
    /// where there is one.
    static func make(_ outlines: [any OutlineRowActivating]) -> (any OutlineRowActivating)? {
        outlines.count > 1 ? Self(outlines: outlines) : outlines.first
    }

    /// The first outline that moved, asked in order: one that does not know
    /// the row moves nothing.
    @discardableResult
    func setRowExpanded(_ id: AnyHashable, to target: Bool?, includingDescendants: Bool) -> Bool {
        outlines.contains { $0.setRowExpanded(id, to: target, includingDescendants: includingDescendants) }
    }

    /// The parent the first outline that knows one names. A root row has none
    /// in its own outline, and no other outline knows it.
    func parentRowID(of id: AnyHashable) -> AnyHashable? {
        for outline in outlines {
            if let parent = outline.parentRowID(of: id) { return parent }
        }
        return nil
    }
}

@MainActor extension OutlineGroup: ListRowExtractor where Leaf: View {
    /// One list row per visible node, every one at once: what a `Section`
    /// among other rows asks, and one with its windowing off. A `List` of an
    /// outline alone, or of one `Section` holding it, asks
    /// ``windowedListRows(context:)``, and builds only the rows it draws.
    ///
    /// A row whose id the list cannot name is left out, as it always was here.
    package func extractListRows<RowID: Hashable>(context: RenderContext) -> [ListRow<RowID>] {
        let rows: OutlineListRows<RowID> = listRows(context: context)
        return rows.all
    }
}
