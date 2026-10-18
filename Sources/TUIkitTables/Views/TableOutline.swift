//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableOutline.swift
//
//  Hierarchical tables: the row content that builds a tree — `OutlineGroup`,
//  `DisclosureTableRow`, the rows of `Table(_:children:)` — and the outline a
//  table draws from it: which rows show, how deep each sits, and the triangle
//  that opens or closes a branch.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitLists

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
/// children come from its row builder, and a recursive open builds them. The
/// handler's key dispatch is nonisolated in its type but runs on the main
/// actor all the same (`StdinArrivalStream` delivers input there): the opening
/// witness says so with `MainActor.assumeIsolated`, and the parent lookup
/// reads only a map written once, in the initializer.
@MainActor
final class _TableOutline<Value: Identifiable>: OutlineRowActivating {
    /// Whether a row has rows beneath it, and whether they show.
    enum Disclosure: Equatable {
        case leaf, closed, open
    }

    /// One visible row's place in the tree.
    struct Placement {
        let depth: Int
        let disclosure: Disclosure
    }

    /// The visible rows' values, in the order they are drawn.
    let values: [Value]

    /// What the row modifiers said about each visible row, parallel to
    /// ``values``, or `nil` when they said nothing about any.
    let traits: [_TableRowTraits]?

    /// Where each visible row sits.
    private let placements: [Value.ID: Placement]

    /// Each visible row's parent, for Left's walk out of a subtree.
    ///
    /// `nonisolated(unsafe)` so ``parentRowID(of:)`` can answer from the
    /// handler's nonisolated key dispatch: written once, in the initializer,
    /// and only read after — the invariant ``OutlineActivation`` rests on.
    nonisolated(unsafe) private let parents: [Value.ID: Value.ID]

    /// The visible branches, to open or close.
    private let branches: [Value.ID: _TableRowNode<Value>]

    /// The expansion of every branch that keeps no binding of its own.
    private let expansion: StateBox<Set<AnyHashable>>

    /// Flattens `tree`: every root, and beneath each open branch its rows, in
    /// reading order. A closed branch's rows are never built.
    init(tree: [_TableRowNode<Value>], expansion: StateBox<Set<AnyHashable>>) {
        self.expansion = expansion
        var values: [Value] = []
        var traits: [_TableRowTraits] = []
        var anyTraits = false
        var placements: [Value.ID: Placement] = [:]
        var parents: [Value.ID: Value.ID] = [:]
        var branches: [Value.ID: _TableRowNode<Value>] = [:]
        // An explicit stack, not recursion: a deep tree must not bring the
        // render pass any nearer the stack limit. Pushed in reverse so the top
        // is always the next row in reading order.
        var stack: [(node: _TableRowNode<Value>, depth: Int, parent: Value.ID?)] =
            tree.reversed().map { ($0, 0, nil) }
        while let (node, depth, parent) = stack.popLast() {
            let id = node.value.id
            values.append(node.value)
            traits.append(node.traits)
            anyTraits = anyTraits || !node.traits.isEmpty
            if let parent { parents[id] = parent }
            guard let children = node.children else {
                placements[id] = Placement(depth: depth, disclosure: .leaf)
                continue
            }
            branches[id] = node
            let isOpen = Self.isOpen(node, in: expansion)
            placements[id] = Placement(depth: depth, disclosure: isOpen ? .open : .closed)
            guard isOpen else { continue }
            for child in children().reversed() {
                stack.append((child, depth + 1, id))
            }
        }
        self.values = values
        self.traits = anyTraits ? traits : nil
        self.placements = placements
        self.parents = parents
        self.branches = branches
    }

    /// Whether a branch is open: as its own binding says, or as the table
    /// remembers. A branch starts closed, as SwiftUI's do.
    private static func isOpen(_ node: _TableRowNode<Value>, in expansion: StateBox<Set<AnyHashable>>) -> Bool {
        node.isExpanded?.wrappedValue ?? expansion.value.contains(AnyHashable(node.value.id))
    }

    // MARK: Drawing

    /// Cells each level of the tree indents by: the width of the triangle and
    /// the blank after it, so a child's triangle sits under its parent's label.
    static var indentStep: Int { DisclosureMetrics.triangleColumnWidth }

    /// What the first column's cell begins with: the row's indentation, then
    /// its triangle — or, for a leaf, a blank of the triangle's width, so the
    /// labels of a level line up whatever they are.
    func prefix(for id: Value.ID) -> String {
        guard let placement = placements[id] else { return "" }
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
        guard let placement = placements[id], placement.disclosure != .leaf else { return nil }
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
            column.cell = .text { value in
                let text = make(value)
                let prefix = self.prefix(for: value.id)
                // A plain text stays plain, and so stays on the string path.
                return text.drawsAsPlainString
                    ? Text(verbatim: prefix + text.content) : Text(verbatim: prefix) + text
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
    nonisolated func setRowExpanded(
        _ id: AnyHashable, to target: Bool?, includingDescendants: Bool
    ) -> Bool {
        // `AnyHashable` is not `Sendable`, but this never leaves the thread it
        // arrived on: `assumeIsolated` runs the closure here, synchronously.
        nonisolated(unsafe) let id = id
        return MainActor.assumeIsolated {
            setExpanded(id, to: target, includingDescendants: includingDescendants)
        }
    }

    /// ``setRowExpanded(_:to:includingDescendants:)``, on the main actor.
    @discardableResult
    func setExpanded(_ id: AnyHashable, to target: Bool?, includingDescendants: Bool) -> Bool {
        guard let rowID = id.base as? Value.ID, let node = branches[rowID] else { return false }
        let open = target ?? !Self.isOpen(node, in: expansion)
        var changed = false
        var stack = [node]
        while let current = stack.popLast() {
            if Self.isOpen(current, in: expansion) != open {
                set(current, open: open)
                changed = true
            }
            guard includingDescendants, let children = current.children else { continue }
            stack += children().filter { $0.children != nil }
        }
        return changed
    }

    /// The row this one sits under, or `nil` for a root row.
    nonisolated func parentRowID(of id: AnyHashable) -> AnyHashable? {
        guard let rowID = id.base as? Value.ID, let parent = parents[rowID] else { return nil }
        return AnyHashable(parent)
    }

    private func set(_ node: _TableRowNode<Value>, open: Bool) {
        if let binding = node.isExpanded {
            binding.wrappedValue = open
        } else if open {
            expansion.value.insert(AnyHashable(node.value.id))
        } else {
            expansion.value.remove(AnyHashable(node.value.id))
        }
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
        var rowsBeneath: (@MainActor () -> [_TableRowNode<Data.Element>])?
        if let kids = element[keyPath: children] {
            rowsBeneath = { kids.map { node($0, children: children) } }
        }
        return _TableRowNode(value: element, children: rowsBeneath, isExpanded: nil)
    }
}

// MARK: - OutlineGroup of table rows

extension OutlineGroup: _TableRowValued where Leaf: TableRowContent, Data.Element == Leaf.TableRowValue {
    public typealias TableRowValue = Leaf.TableRowValue
}

extension OutlineGroup: TableRowContent
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

extension OutlineGroup
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
        var rowsBeneath: (@MainActor () -> [_TableRowNode<Data.Element>])?
        if let kids = element[keyPath: children] {
            rowsBeneath = { kids.map { node($0, children: children, content: content) } }
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
                value: value, children: { tableRows(of: content()).nodes },
                isExpanded: row.isExpanded))
    }
}
