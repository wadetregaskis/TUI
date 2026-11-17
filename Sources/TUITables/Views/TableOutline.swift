//  🖥️ TUI — A Terminal UI framework for Swift
//  TableOutline.swift
//
//  Hierarchical tables: the row content that builds a tree — `OutlineGroup`,
//  `DisclosureTableRow`, the rows of `Table(_:children:)` — and the outline a
//  table draws from it: which rows show, how deep each sits, and the triangle
//  that opens or closes a branch.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUILists

// MARK: - An outline row's place

// These are not nested in `_TableOutline`: a type nested in a generic class is
// generic itself, though it uses nothing of `Value`, and the code that lists the
// rows runs unspecialised over the app's row type. So each row listed looked up
// the metadata of `_TableOutline<Value>.Row`, and of an array of it, at run
// time (`swift_getGenericMetadata`); a top-level type's is found once.

/// Whether an outline row has rows beneath it, and whether they show.
enum _TableOutlineDisclosure: Equatable {
    case leaf, closed, open
}

/// One visible row's place in the tree.
struct _TableOutlinePlacement {
    let depth: Int
    let disclosure: _TableOutlineDisclosure
}

/// One visible row's place in the tree, and its links to the rows around it,
/// by index: kept parallel to the outline's values rather than by id, so that
/// listing a row costs an append, not a store in a dictionary or three.
struct _TableOutlineRow {
    let placement: _TableOutlinePlacement
    /// The row it sits under, by its index in the values, or -1 for a root.
    let parent: Int
    /// Its node among the outline's branches, or -1 for a leaf.
    let branch: Int

    /// This row in an outline that lists `rows` rows and `branches` branches
    /// before the ones it was listed among.
    func shifted(rows: Int, branches: Int) -> Self {
        Self(
            placement: placement, parent: parent < 0 ? -1 : parent + rows,
            branch: branch < 0 ? -1 : branch + branches)
    }
}

/// Where a row waiting on the flattening's stack goes: how deep, under which
/// row, and among which list of siblings with loops. Beside the stack of the
/// rows themselves, so that this part is not generic either.
private struct _TableOutlinePending {
    let depth: Int
    let parent: Int
    let siblings: Int?
}

// MARK: - The outline a table draws

/// A hierarchical table's rows as one frame draws them: the rows that show,
/// how deep each sits, which are branches and which way they point, and how to
/// open or close one.
///
/// A class for the reason ``OutlineActivation`` is one: the table's row handler
/// keeps it and calls it from key dispatch, outside the render pass that built
/// it. It is built once per pass and only read afterwards, and the next pass
/// replaces it.
///
/// Main-actor isolated, because building rows is — a `DisclosureTableRow`'s
/// children come from its row builder, and a recursive open builds them — and
/// as the handler's key dispatch is (`StdinArrivalStream` delivers input there).
@MainActor
final class _TableOutline<Value: Identifiable>: OutlineRowActivating {
    typealias Disclosure = _TableOutlineDisclosure
    typealias Placement = _TableOutlinePlacement
    typealias Row = _TableOutlineRow

    /// The visible rows' values, in the order they are drawn.
    let values: [Value]

    /// What the row modifiers said about each visible row, parallel to
    /// ``values``, or `nil` when they said nothing about any.
    let traits: [_TableRowTraits]?

    /// Where each visible row sits, parallel to ``values``.
    private let rows: [Row]

    /// The visible branches, to open or close, by ``Row/branch``.
    private let branchNodes: [_TableRowNode<Value>]

    /// Each visible row's index in ``values`` by its id, made the first time a
    /// row is asked for by id — a draw asks for the rows it draws, a key for
    /// the row it acts on — and not by the flattening, which lists every open
    /// row of a tree written as row content again every pass. Where two rows
    /// share an id, which SwiftUI's rows may not, the later one answers.
    private var rowIndices: [Value.ID: Int]?

    /// The expansion of every branch that keeps no binding of its own.
    private let expansion: _TableOutlineExpansion<Value>

    /// Called when any branch in the outline is expanded or collapsed.
    var onExpansionChange: ((Value.ID, Bool) -> Void)?

    /// The loops among the shown rows that take payloads in between their
    /// rows, as one table-wide insertion over the shown rows' slots — `nil`
    /// where no shown loop takes any (``_TableOutlineInsertions``).
    let insertionAction: _TableDropInsertion?

    /// Flattens `tree`: every root, and beneath each open branch its rows, in
    /// reading order. A closed branch's rows are never built.
    convenience init(tree: _TableRowBranch<Value>, expansion: _TableOutlineExpansion<Value>) {
        self.init(Self.flattening(tree, expansion: expansion.read()), expansion: expansion)
    }

    /// The outline `flat` describes, opening and closing branches in
    /// `expansion`.
    init(_ flat: Flattening, expansion: _TableOutlineExpansion<Value>) {
        self.expansion = expansion
        self.values = flat.values
        self.traits = flat.anyTraits ? flat.traits : nil
        self.rows = flat.rows
        self.branchNodes = flat.branchNodes
        self.insertionAction = flat.insertionAction
    }

    /// What flattening a tree finds: the rows that show, in order, and where
    /// each sits.
    struct Flattening {
        var values: [Value] = []
        /// Empty until a row has traits, then one per row (``noteTraits(_:at:)``).
        var traits: [_TableRowTraits] = []
        var anyTraits = false
        var rows: [Row] = []
        var branchNodes: [_TableRowNode<Value>] = []
        var insertionAction: _TableDropInsertion?

        /// Notes row `row`'s traits: nothing while no row has had any, so a
        /// tree no row modifier reached lists no traits at all.
        mutating func noteTraits(_ rowTraits: _TableRowTraits, at row: Int) {
            if anyTraits {
                traits.append(rowTraits)
            } else if !rowTraits.isEmpty {
                anyTraits = true
                traits = Array(repeating: _TableRowTraits(), count: row)
                traits.append(rowTraits)
            }
        }

        /// Notes a row listed at `depth` under the row `parent` (-1 for a
        /// root): `node`, a branch when it has rows beneath it.
        mutating func noteRow(_ node: _TableRowNode<Value>, depth: Int, parent: Int, isOpen: Bool) {
            guard node.children != nil else {
                rows.append(Row(placement: Placement(depth: depth, disclosure: .leaf), parent: parent, branch: -1))
                return
            }
            rows.append(
                Row(
                    placement: Placement(depth: depth, disclosure: isOpen ? .open : .closed), parent: parent,
                    branch: branchNodes.count))
            branchNodes.append(node)
        }

        /// Appends `other`'s rows and branches after these, their links
        /// shifted to where they now are. Not its values: the caller splices
        /// those.
        mutating func appendPlacements(of other: Self) {
            let rowBase = rows.count
            let branchBase = branchNodes.count
            rows += other.rows.lazy.map { $0.shifted(rows: rowBase, branches: branchBase) }
            branchNodes += other.branchNodes
        }
    }

    /// Flattens `tree`: every root, and beneath each open branch its rows.
    static func flattening(
        _ tree: _TableRowBranch<Value>, expansion: _TableOutlineExpansion<Value>.Reading
    ) -> Flattening {
        var flat = Flattening()
        // Where each list of siblings drew its rows — the roots, and each open
        // branch's — for the loops among them.
        var insertions = _TableOutlineInsertions(roots: tree.insertions)
        // An explicit stack, not recursion: a deep tree must not bring the
        // render pass any nearer the stack limit. Pushed in reverse so the top
        // is always the next row in reading order. A row's parent is its index.
        // Two stacks in step, the rows and where each goes, not one stack of
        // tuples: a tuple over `Value` had its metadata looked up for every
        // push and pop.
        let roots = insertions.rootList
        var stack = Array(tree.nodes.reversed())
        var pending = [_TableOutlinePending](
            repeating: _TableOutlinePending(depth: 0, parent: -1, siblings: roots), count: stack.count)
        while let node = stack.popLast(), let place = pending.popLast() {
            let (depth, parent, siblings) = (place.depth, place.parent, place.siblings)
            let row = flat.values.count
            insertions.drew(row: row, depth: depth, in: siblings)
            flat.values.append(node.value)
            flat.noteTraits(node.traits, at: row)
            guard let children = node.children else {
                flat.noteRow(node, depth: depth, parent: parent, isOpen: false)
                continue
            }
            let isOpen = Self.isOpen(node, in: expansion)
            flat.noteRow(node, depth: depth, parent: parent, isOpen: isOpen)
            guard isOpen else { continue }
            let branch = children()
            let list = insertions.opened(after: row, depth: depth + 1, loops: branch.insertions)
            stack += branch.nodes.reversed()
            // One by one, not `+= repeatElement(…)`: that took the generic
            // `+=` of a sequence, unspecialised, element by element.
            let place = _TableOutlinePending(depth: depth + 1, parent: row, siblings: list)
            for _ in 0..<branch.nodes.count { pending.append(place) }
        }
        flat.insertionAction = insertions.action(rowCount: flat.values.count)
        return flat
    }

    /// Whether a branch is open: as its own binding says, or as the table
    /// remembers. A branch starts closed, as SwiftUI's do.
    static func isOpen(_ node: _TableRowNode<Value>, in expansion: _TableOutlineExpansion<Value>.Reading) -> Bool {
        node.isExpanded?.wrappedValue ?? expansion.contains(node.value.id)
    }

    // MARK: Drawing

    /// Cells each level of the tree indents by: the width of the triangle and
    /// the blank after it, so a child's triangle sits under its parent's label.
    static var indentStep: Int { DisclosureMetrics.triangleColumnWidth }

    /// The index in ``values`` of the row `id` names, or `nil` for a row this
    /// outline does not show: from ``rowIndices``, made on the first ask.
    private func rowIndex(of id: Value.ID) -> Int? {
        if let rowIndices { return rowIndices[id] }
        var indices = [Value.ID: Int](minimumCapacity: values.count)
        for index in values.indices { indices[values[index].id] = index }
        rowIndices = indices
        return indices[id]
    }

    /// The place of the row `id` names, or `nil` for a row this outline does
    /// not show.
    private func row(for id: Value.ID) -> Row? {
        rowIndex(of: id).map { rows[$0] }
    }

    /// What the first column's cell begins with: the row's indentation, then
    /// its triangle — or, for a leaf, a blank of the triangle's width, so the
    /// labels of a level line up whatever they are.
    func prefix(for id: Value.ID) -> String {
        // A row this outline does not show draws as a leaf among the roots.
        let placement = row(for: id)?.placement ?? Placement(depth: 0, disclosure: .leaf)
        let indent = String.spaces(placement.depth * Self.indentStep)
        let blank = String.spaces(DisclosureMetrics.glyphSpacing)
        switch placement.disclosure {
        case .leaf: return indent + String.spaces(Self.indentStep)
        case .closed: return indent + TerminalSymbols.disclosureCollapsed + blank
        case .open: return indent + TerminalSymbols.disclosureExpanded + blank
        }
    }

    /// The cells of a row's first column that toggle it, measured from where
    /// the column starts: its triangle and the blank after it. `nil` for a
    /// leaf.
    func triangleColumns(for id: Value.ID) -> Range<Int>? {
        guard let placement = row(for: id)?.placement, placement.disclosure != .leaf else { return nil }
        let start = placement.depth * Self.indentStep
        return start..<(start + Self.indentStep)
    }

    /// `column` drawing each row's ``prefix(for:)`` before its cell: the
    /// first column of a hierarchical table, where the tree is drawn.
    ///
    /// The prefix is part of the cell, so everything that reads a cell — the
    /// `.fit` scan, a row's height, the row memo's comparison — reads it too.
    /// The column no longer names a property alone: its text now depends on
    /// the expansion as well as the row, which is what keeps the memo from
    /// serving a row whose triangle turned.
    func disclosing(_ column: _TableColumnSpec<Value>) -> _TableColumnSpec<Value> {
        var column = column
        column.namesAProperty = false
        switch column.cell {
        case .string(let extract):
            column.cell = .string { self.prefix(for: $0.id) + extract($0) }
        case .text(let make):
            // `make` reads a key in the table's language first, so the prefix
            // goes in front of the words the cell draws.
            column.cell = .text { value, context in
                let text = make(value, context)
                let prefix = self.prefix(for: value.id)
                // A plain text stays plain, and so stays on the string path.
                return text.drawsAsPlainString
                    ? Text(verbatim: prefix + text.content) : text.prefixed(with: prefix)
            }
        case .view(let render):
            column.cell = .view { value, context in
                // The view lays out in what the prefix leaves of the cell, and
                // the lines after its first sit under its first, not under the
                // triangle.
                let prefix = self.prefix(for: value.id)
                let width = prefix.strippedLength
                let content = render(
                    value,
                    context.withAvailableSize(
                        width: max(1, context.availableWidth - width),
                        height: context.availableHeight))
                var cell = FrameBuffer(
                    lines: [prefix]
                        + Array(
                            repeating: String.spaces(width),
                            count: max(0, content.height - 1)))
                cell.appendHorizontally(content)
                return cell
            }
        }
        return column
    }

    // MARK: Opening and closing

    /// Opens, closes or toggles a branch — and with `includingDescendants`,
    /// every branch beneath it however deep, so reopening it shows it as it
    /// was left.
    @discardableResult
    func setRowExpanded(_ id: AnyHashable, to target: Bool?, includingDescendants: Bool) -> Bool {
        setExpanded(id, to: target, includingDescendants: includingDescendants)
    }

    /// ``setRowExpanded(_:to:includingDescendants:)``, on the main actor.
    @discardableResult
    func setExpanded(_ id: AnyHashable, to target: Bool?, includingDescendants: Bool) -> Bool {
        guard let rowID = id.base as? Value.ID, let branch = row(for: rowID)?.branch, branch >= 0 else {
            return false
        }
        let node = branchNodes[branch]
        // Read once, now: a key handled before the next frame sees what the
        // one before it wrote.
        let reading = expansion.read()
        let open = target ?? !Self.isOpen(node, in: reading)
        var changed: [_TableRowNode<Value>] = []
        var stack = [node]
        while let current = stack.popLast() {
            if Self.isOpen(current, in: reading) != open {
                changed.append(current)
            }
            guard includingDescendants, let children = current.children else { continue }
            stack += children().nodes.filter { $0.children != nil }
        }
        set(changed, open: open)
        return !changed.isEmpty
    }

    /// The row this one sits under, or `nil` for a root row.
    func parentRowID(of id: AnyHashable) -> AnyHashable? {
        guard let rowID = id.base as? Value.ID, let parent = row(for: rowID)?.parent, parent >= 0 else { return nil }
        return AnyHashable(values[parent].id)
    }

    /// Opens or closes `nodes`: each through its own binding where it has
    /// one, the rest in one write to the expansion.
    private func set(_ nodes: [_TableRowNode<Value>], open: Bool) {
        var kept: [Value.ID] = []
        for node in nodes {
            if let binding = node.isExpanded {
                binding.wrappedValue = open
            } else {
                kept.append(node.value.id)
            }
        }
        expansion.set(kept, open: open)
        for node in nodes { onExpansionChange?(node.value.id, open) }
    }
}

/// A tree of row content's first level, as the key a pass keeps the table's
/// outline under (`RenderCache.composedOncePerPass`). Never drawn.
///
/// Not the tree itself: a table's parent evaluates its body again for the
/// draw, unless its body is slow enough for the pass to keep (`BodyKeep`),
/// and every row builder in the tree is then a new closure, at a new address,
/// over the same rows. Within one pass, at one place, the app's state is the
/// state the measure saw, so rows whose first level is the same — the same
/// rows by id, in the same order, the same ones branches, with the same loops
/// among them — are taken to be the same rows beneath. That is a premise
/// about one pass, not across passes, where the rows are always built again
/// (the row-builder question, G1-rows, is the owner's).
struct _TableOutlineSource<Value: Identifiable>: View {
    /// The first level's rows, hashed: their count, ids and which are
    /// branches, and the number of loops among them.
    let firstLevel: Int

    init(_ tree: _TableRowBranch<Value>) {
        var hasher = Hasher()
        hasher.combine(tree.nodes.count)
        hasher.combine(tree.insertions.count)
        for node in tree.nodes {
            hasher.combine(node.value.id)
            hasher.combine(node.children != nil)
        }
        firstLevel = hasher.finalize()
    }

    var body: Never {
        fatalError("_TableOutlineSource is a key, never drawn")
    }
}

// MARK: - Insertions between an outline's rows

/// Where the loops of a hierarchical table's shown rows take payloads in
/// between their rows (decisions B80): a `ForEach`'s
/// `.dropDestination(for:action:)` or `.onInsert(of:perform:)`, among the
/// roots or the rows of an open branch.
///
/// Each loop's offsets are slots between the shown rows: its offset `k` is the
/// slot before its `k`-th row, and its last the slot after its last row's
/// shown subtree. A slot two loops reach — the end of a branch's rows is also
/// the place before the next row of the list it is in — goes to the deeper,
/// the rows the slot is among, and to a shallower one only where the deeper
/// does not take the payload. A loop under a closed branch has no shown rows
/// and takes nothing.
///
/// Measured on macOS 15.8 (`Tools/SwiftUIProbes/Hierarchical table
/// insertions/outlineinsert.swift`): a drop SwiftUI's outline proposes among
/// a branch's rows goes to the loop of those rows, at its offset among them,
/// and one among the roots to the roots' loop. A terminal's drop slot is a
/// line between rows, with no indentation to say how deep it is aimed, which
/// is what the deeper loop answers for. Not copied: where the rows of a
/// branch have no loop that takes the drop, SwiftUI hands it to the roots'
/// loop at the offset it had among the branch's rows — a place among the
/// roots unrelated to where it was dropped.
struct _TableOutlineInsertions {
    /// A list of siblings: its rows' shown indices, its depth, the shown row
    /// after which it starts, and its loops in its own numbering.
    private struct Siblings {
        var rows: [Int] = []
        let depth: Int
        let start: Int
        let loops: [_TableRowInsertion]
    }

    /// The lists of siblings with loops among them: a slot can only be one of
    /// theirs, so a list without loops is not noted at all.
    private var lists: [Siblings] = []

    /// The number of the roots' list, where the roots have loops.
    let rootList: Int?

    /// The shown row the depths start at: the first a list with loops holds,
    /// `nil` while none has been seen. No row before it is in a list with
    /// loops, and a subtree's end lies after its row, so nothing earlier is
    /// needed — and an outline with no loop notes nothing.
    private var depthsStart: Int?

    /// The depth of each shown row from ``depthsStart`` on, for where a row's
    /// subtree ends.
    private var depths: [Int] = []

    init(roots: [_TableRowInsertion]) {
        if roots.isEmpty {
            rootList = nil
        } else {
            lists = [Siblings(depth: 0, start: 0, loops: roots)]
            rootList = 0
            depthsStart = 0
        }
    }

    /// Notes that shown row `row`, at `depth`, is the next row of the list of
    /// siblings `list` — `nil` for a list with no loops.
    mutating func drew(row: Int, depth: Int, in list: Int?) {
        if depthsStart != nil { depths.append(depth) }
        if let list { lists[list].rows.append(row) }
    }

    /// Starts the list of an opened branch — the shown row `row` — whose rows
    /// sit at `depth`, with its loops; returns the list's number for its rows,
    /// or `nil` where it has no loops.
    mutating func opened(after row: Int, depth: Int, loops: [_TableRowInsertion]) -> Int? {
        guard !loops.isEmpty else { return nil }
        if depthsStart == nil { depthsStart = row + 1 }
        lists.append(Siblings(depth: depth, start: row + 1, loops: loops))
        return lists.count - 1
    }

    /// The insertion over `rowCount` shown rows, or `nil` where no loop shown
    /// takes anything. A slot no loop that takes the payload reaches — among
    /// the roots of a tree whose loops are its branches', say — takes nothing:
    /// it opens no gap, and a drop there is refused.
    func action(rowCount: Int) -> _TableDropInsertion? {
        // No list with loops: nothing was noted, and nothing is worked out.
        guard let depthsStart else { return nil }
        let ends = subtreeEnds(rowCount: rowCount, from: depthsStart)
        var found: [(depth: Int, slots: [Int], loop: _TableRowInsertion)] = []
        for list in lists {
            for loop in list.loops {
                let slots = Self.slots(of: loop.rows, in: list) { ends[$0 - depthsStart] }
                guard !slots.isEmpty else { continue }
                found.append((list.depth, slots, loop))
            }
        }
        guard !found.isEmpty else { return nil }
        let targets = found
        /// The loop `slot` goes to for `payloads`, and its offset there: the
        /// deepest loop at the slot that takes one of them; among loops of one
        /// depth, the first, as a flat table's.
        func owner(at slot: Int, of payloads: [Any]) -> (offset: Int, loop: _TableRowInsertion)? {
            guard
                let owner = targets.filter({ $0.slots.contains(slot) && payloads.contains(where: $0.loop.accepts) })
                    .max(by: { $0.depth < $1.depth }),
                let offset = owner.slots.firstIndex(of: slot)
            else { return nil }
            return (offset, owner.loop)
        }
        return _TableDropInsertion(
            accepts: { payload in targets.contains { $0.loop.accepts(payload) } },
            takes: { slot, payload in owner(at: slot, of: [payload]) != nil },
            perform: { slot, payloads in
                guard let (offset, loop) = owner(at: slot, of: payloads) else { return }
                loop.perform(offset, payloads.filter(loop.accepts))
            })
    }

    /// For each shown row from `first` on, the shown row after its subtree:
    /// the next row no deeper than it, or `rowCount`. Indexed from `first`.
    private func subtreeEnds(rowCount: Int, from first: Int) -> [Int] {
        var ends = [Int](repeating: rowCount, count: depths.count)
        var open: [Int] = []
        for row in depths.indices {
            while let top = open.last, depths[top] >= depths[row] {
                ends[top] = first + row
                open.removeLast()
            }
            open.append(row)
        }
        return ends
    }

    /// The slots a loop over `rows` of `list` reaches, by offset: before each
    /// of its rows, then after its last row's subtree (`end`). A loop with no
    /// rows has the one slot where its rows would be.
    private static func slots(of rows: Range<Int>, in list: Siblings, end: (Int) -> Int) -> [Int] {
        guard rows.upperBound <= list.rows.count else { return [] }
        let before = rows.map { list.rows[$0] }
        let after: Int
        if let last = rows.last {
            after = end(list.rows[last])
        } else if rows.lowerBound < list.rows.count {
            after = list.rows[rows.lowerBound]
        } else {
            after = list.rows.last.map(end) ?? list.start
        }
        return before + [after]
    }
}

// MARK: - TableOutlineGroupContent

/// An opaque table row type created by a table's hierarchical initializers.
///
/// You don't use this type directly: `Table(_:children:columns:)` and its
/// siblings build their rows with it.
public struct TableOutlineGroupContent<Data: RandomAccessCollection>: TableRowContent
where Data.Element: Identifiable {
    public typealias TableRowValue = Data.Element

    /// The top-level rows.
    let data: Data

    /// Each row's children — `nil` for a leaf.
    let children: KeyPath<Data.Element, Data?>

    init(_ data: Data, children: KeyPath<Data.Element, Data?>) {
        self.data = data
        self.children = children
    }

    /// The type of the rows: an outline of one ``TableRow`` per element.
    ///
    /// Spelled out where SwiftUI's is opaque: SwiftUI declares the alias, and an
    /// opaque body here would declare none.
    public typealias TableRowBody = OutlineGroup<Data, Data.Element.ID, TableRow<Data.Element>>

    /// The rows: an outline of one ``TableRow`` per element.
    public var tableRowBody: TableRowBody {
        OutlineGroup(data, children: children)
    }
}

extension TableOutlineGroupContent {
    /// Appends a tree node for each root element.
    public static func _appendRows(_ content: Self, to rows: inout _TableRowList<Data.Element>) {
        for element in content.data {
            rows.append(treeNode: node(element, children: content.children))
        }
    }

    /// One element's row, and lazily the rows of its children.
    static func node(
        _ element: Data.Element, children: KeyPath<Data.Element, Data?>
    ) -> _TableRowNode<Data.Element> {
        var rowsBeneath: (@MainActor () -> _TableRowBranch<Data.Element>)?
        if let kids = element[keyPath: children] {
            rowsBeneath = { _TableRowBranch(nodes: kids.map { node($0, children: children) }) }
        }
        return _TableRowNode(value: element, children: rowsBeneath, isExpanded: nil)
    }
}

// MARK: - OutlineGroup of table rows

@MainActor extension OutlineGroup: _TableRowValued where Leaf: TableRowContent, Data.Element == Leaf.TableRowValue {
    public typealias TableRowValue = Leaf.TableRowValue
}

@MainActor extension OutlineGroup: TableRowContent
where Leaf: TableRowContent, Data.Element == Leaf.TableRowValue, ID == Data.Element.ID {
    public typealias TableRowBody = Never

    /// Never called: the outline hands its rows to the table directly.
    public var tableRowBody: Never { fatalError("OutlineGroup renders its rows directly") }

    /// Creates an outline group of table rows rooted at a single element: a
    /// ``TableRow`` for each node, its children beneath it.
    ///
    /// - Parameters:
    ///   - root: The element at the top of the tree.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    public init<DataElement: Identifiable>(_ root: DataElement, children: KeyPath<DataElement, Data?>)
    where Leaf == TableRow<DataElement>, DataElement == Data.Element {
        self.init(roots: [root], id: \.id, children: children) { TableRow($0) }
    }

    /// Creates an outline group of table rows from a collection of top-level
    /// elements: a ``TableRow`` for each node, its children beneath it.
    ///
    /// - Parameters:
    ///   - data: The elements at the top of the tree.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    public init<DataElement: Identifiable>(_ data: Data, children: KeyPath<DataElement, Data?>)
    where Leaf == TableRow<DataElement>, DataElement == Data.Element {
        self.init(roots: Array(data), id: \.id, children: children) { TableRow($0) }
    }

    /// Creates an outline group of table rows rooted at a single element, each
    /// node's row built by `content`.
    ///
    /// - Parameters:
    ///   - root: The element at the top of the tree.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    ///   - content: Builds a node's row.
    public init<DataElement>(
        _ root: DataElement, children: KeyPath<DataElement, Data?>,
        @TableRowBuilder<DataElement> content: @escaping (DataElement) -> Leaf
    ) where DataElement == Data.Element {
        self.init(roots: [root], id: \.id, children: children, content: content)
    }

    /// Creates an outline group of table rows from a collection of top-level
    /// elements, each node's row built by `content`.
    ///
    /// - Parameters:
    ///   - data: The elements at the top of the tree.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    ///   - content: Builds a node's row.
    public init<DataElement>(
        _ data: Data, children: KeyPath<DataElement, Data?>,
        @TableRowBuilder<DataElement> content: @escaping (DataElement) -> Leaf
    ) where DataElement == Data.Element {
        self.init(roots: Array(data), id: \.id, children: children, content: content)
    }

    /// Creates an outline group of table rows rooted at a single element, each
    /// node's row built by `content`, naming the elements' identity.
    ///
    /// - Parameters:
    ///   - root: The element at the top of the tree.
    ///   - id: The key path to an element's identity — its `id`, as the rows
    ///     of a table are always known by.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    ///   - content: Builds a node's row.
    public init<DataElement>(
        _ root: DataElement, id: KeyPath<DataElement, ID>, children: KeyPath<DataElement, Data?>,
        @TableRowBuilder<DataElement> content: @escaping (DataElement) -> Leaf
    ) where ID == DataElement.ID, DataElement == Data.Element {
        self.init(roots: [root], id: id, children: children, content: content)
    }

    /// Creates an outline group of table rows from a collection of top-level
    /// elements, each node's row built by `content`, naming the elements'
    /// identity.
    ///
    /// - Parameters:
    ///   - data: The elements at the top of the tree.
    ///   - id: The key path to an element's identity — its `id`, as the rows
    ///     of a table are always known by.
    ///   - children: A key path to an element's children, or `nil` for a leaf.
    ///   - content: Builds a node's row.
    public init<DataElement>(
        _ data: Data, id: KeyPath<DataElement, ID>, children: KeyPath<DataElement, Data?>,
        @TableRowBuilder<DataElement> content: @escaping (DataElement) -> Leaf
    ) where ID == DataElement.ID, DataElement == Data.Element {
        self.init(roots: Array(data), id: id, children: children, content: content)
    }
}

@MainActor extension OutlineGroup
where Leaf: TableRowContent, Data.Element == Leaf.TableRowValue, ID == Data.Element.ID {
    /// Appends a tree node for each root.
    @MainActor
    public static func _appendRows(_ group: Self, to rows: inout _TableRowList<Leaf.TableRowValue>) {
        for root in group.roots {
            rows.append(treeNode: node(root, children: group.childrenKeyPath, content: group.content))
        }
    }

    /// One element's row — the row its content builds, with whatever row
    /// modifiers that carries — and lazily the rows of its children.
    private static func node(
        _ element: Data.Element, children: KeyPath<Data.Element, Data?>,
        content: @escaping (Data.Element) -> Leaf
    ) -> _TableRowNode<Data.Element> {
        var rowsBeneath: (@MainActor () -> _TableRowBranch<Data.Element>)?
        if let kids = element[keyPath: children] {
            rowsBeneath = { _TableRowBranch(nodes: kids.map { node($0, children: children, content: content) }) }
        }
        let built = tableRows(of: content(element)).nodes.first
        return _TableRowNode(
            value: built?.value ?? element, children: rowsBeneath, isExpanded: nil,
            traits: built?.traits ?? _TableRowTraits())
    }
}

// MARK: - DisclosureTableRow

/// A kind of table row that shows or hides additional rows based on the state
/// of a disclosure control.
///
/// ```swift
/// Table(of: Item.self) {
///     TableColumn("Name", value: \.name)
/// } rows: {
///     DisclosureTableRow(folder, isExpanded: $isOpen) {
///         ForEach(folder.files) { TableRow($0) }
///     }
/// }
/// ```
///
/// The row draws a triangle in the table's first column. A click on it, or
/// Right and Left on the focused row, opens and closes it; ⌥Right and ⌥Left
/// carry that through every disclosure beneath it.
public struct DisclosureTableRow<Label: TableRowContent, Content: TableRowContent>: TableRowContent
where Label.TableRowValue == Content.TableRowValue {
    public typealias TableRowValue = Label.TableRowValue
    public typealias TableRowBody = Never

    /// The row itself.
    let label: Label

    /// The rows beneath it.
    let content: () -> Content

    /// Who owns the expansion: the caller, or the table when `nil`.
    let isExpanded: Binding<Bool>?

    /// Creates a disclosure table row with the given value and rows beneath it.
    ///
    /// - Parameters:
    ///   - value: The value of the disclosable table row.
    ///   - isExpanded: A binding to a Boolean value that determines whether
    ///     the row is expanded; `nil` for the table to keep it, starting
    ///     closed.
    ///   - content: The rows to show when the row is expanded.
    public init<Value>(
        _ value: Value, isExpanded: Binding<Bool>? = nil,
        @TableRowBuilder<Value> content: @escaping () -> Content
    ) where Label == TableRow<Value>, Value == Content.TableRowValue {
        self.label = TableRow(value)
        self.content = content
        self.isExpanded = isExpanded
    }

    /// Never called: a disclosure row hands its rows to the table directly.
    public var tableRowBody: Never { fatalError("DisclosureTableRow renders its rows directly") }
}

extension DisclosureTableRow {
    /// Appends this row, with the rows disclosed beneath it.
    public static func _appendRows(_ row: Self, to rows: inout _TableRowList<Label.TableRowValue>) {
        guard let value = tableRows(of: row.label).values.first else { return }
        let content = row.content
        rows.append(
            treeNode: _TableRowNode(
                value: value, children: { tableRows(of: content()).branch },
                isExpanded: row.isExpanded))
    }
}
