//  🖥️ TUI — A Terminal UI framework for Swift
//  TableRowContent.swift
//
//  The protocol a table's rows are written in, the content types that compose
//  rows, and the walk that flattens them for the renderer.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - TableRowContent

/// A type used to represent table rows.
///
/// Like a ``View``, a `TableRowContent` describes rows by composing other row
/// content. The simplest row is a ``TableRow``; ``ForEach`` builds rows from a
/// collection, and ``TableRowBuilder`` composes several, with an `if` and
/// `Group` among them:
///
/// ```swift
/// Table(of: Person.self) {
///     TableColumn("Name", value: \.name)
/// } rows: {
///     TableRow(Person(givenName: "Juan", familyName: "Chavez"))
///     ForEach(people) { person in
///         TableRow(person)
///     }
/// }
/// ```
///
/// Row content factored into a property or a type of its own is written the
/// way SwiftUI's is: a ``tableRowBody`` built with
/// `@TableRowBuilder<Value>`.
@MainActor
public protocol TableRowContent<TableRowValue>: _TableRowValued {
    /// The type of value represented by this table row content.
    associatedtype TableRowValue = TableRowBody.TableRowValue

    /// The type of content representing the body of this table row content.
    associatedtype TableRowBody: TableRowContent

    /// The composition of content that comprise the table row content.
    var tableRowBody: TableRowBody { get }

    /// Appends `content`'s rows to `rows`, in order.
    ///
    /// Not to be implemented by hand. Every row type the framework defines
    /// implements it, and the default — for content an app writes — finds the
    /// rows of ``tableRowBody``.
    ///
    /// A static requirement rather than a cast to an internal protocol, for
    /// the reason ``TableColumnContent/_appendColumns(_:to:)`` is one: that
    /// cast was to `any P<Content.TableRowValue>`, whose metadata the runtime
    /// looked up by mangled name on every call — and a `ForEach` of rows made
    /// it once per ROW, on every body evaluation.
    static func _appendRows(_ content: Self, to rows: inout _TableRowList<TableRowValue>)
}

// MARK: - Flattening

/// A table's rows, in order, for the renderer: each a value, with the rows
/// beneath it when it is a branch of a hierarchical table.
///
/// You don't use this type directly: it is what
/// ``TableRowContent/_appendRows(_:to:)`` appends to.
public struct _TableRowList<Value: Identifiable> {
    /// The rows' values, in order: the whole table, when it is not a tree.
    private(set) var values: [Value] = []

    /// The rows as nodes, once one of them has needed to be more than its
    /// value — a branch, or a row a row modifier reached — and `nil` until
    /// then, with ``values`` as the whole of the list.
    ///
    /// A flat list of plain rows, which a `ForEach` of `TableRow`s makes, is
    /// nearly every list, and a node per row — built, then mapped back to its
    /// value for the table — was about a third of the body evaluation of such
    /// a table. When it is set it has one node per value, in order.
    private var builtNodes: [_TableRowNode<Value>]?

    /// The rows, in order.
    var nodes: [_TableRowNode<Value>] {
        builtNodes ?? values.map { _TableRowNode(value: $0, children: nil, isExpanded: nil) }
    }

    /// Whether any row has rows beneath it — only then is the table an outline.
    private(set) var isTree = false

    /// Whether a row modifier reached any of these rows — only then does the
    /// table read their traits at all.
    private(set) var hasTraits = false

    /// The loops among these rows that take payloads in between their rows,
    /// each with the rows it drew.
    private(set) var insertions: [_TableRowInsertion] = []

    /// The section headers among these rows, each at the row it is drawn
    /// above — the count of rows before it, so one after the last row is
    /// drawn below them all.
    private(set) var sectionHeaders: [_TableSectionHeader] = []

    /// Appends a section's header row: a view across the table, drawn above
    /// whatever row is appended next.
    mutating func appendSectionHeader(_ view: AnyView) {
        sectionHeaders.append(_TableSectionHeader(view: view, beforeRow: values.count))
    }

    /// The rows' traits, in order, or `nil` when no row modifier reached them.
    var traits: [_TableRowTraits]? { hasTraits ? nodes.map { $0.traits } : nil }

    /// Appends a row with nothing beneath it.
    mutating func append(_ value: Value) {
        values.append(value)
        builtNodes?.append(_TableRowNode(value: value, children: nil, isExpanded: nil))
    }

    /// Appends rows with nothing beneath them.
    mutating func append<S: Sequence>(contentsOf newValues: S) where S.Element == Value {
        let start = values.endIndex
        values += newValues
        builtNodes? += values[start...].lazy.map { _TableRowNode(value: $0, children: nil, isExpanded: nil) }
    }

    /// Appends a row of a tree — a branch, or a leaf beside one — which makes
    /// the table an outline.
    mutating func append(treeNode node: _TableRowNode<Value>) {
        isTree = true
        buildNodes()
        values.append(node.value)
        builtNodes?.append(node)
    }

    /// Appends another list's rows, and its loops' insertions at the rows
    /// they land on here.
    mutating func append(contentsOf other: _TableRowList<Value>) {
        isTree = isTree || other.isTree
        hasTraits = hasTraits || other.hasTraits
        let base = values.count
        insertions += other.insertions.map { insertion in
            var moved = insertion
            moved.rows = (insertion.rows.lowerBound + base)..<(insertion.rows.upperBound + base)
            return moved
        }
        sectionHeaders += other.sectionHeaders.map { header in
            var moved = header
            moved.beforeRow += base
            return moved
        }
        if builtNodes != nil || other.builtNodes != nil {
            buildNodes()
            builtNodes? += other.nodes
        }
        values += other.values
    }

    /// These rows as a branch of a tree, or a tree's roots: the rows, and the
    /// loops among them that take payloads in between their rows.
    var branch: _TableRowBranch<Value> { _TableRowBranch(nodes: nodes, insertions: insertions) }

    /// Makes every row here one loop that takes payloads in between its rows.
    mutating func addInsertion(accepts: @escaping (Any) -> Bool, perform: @escaping (Int, [Any]) -> Void) {
        insertions.append(_TableRowInsertion(rows: 0..<values.count, accepts: accepts, perform: perform))
    }

    /// Applies a row modifier to every row here, and to every row beneath
    /// them whenever those are built.
    @MainActor
    mutating func modifyTraits(_ apply: @escaping (inout _TableRowTraits) -> Void) {
        hasTraits = true
        builtNodes = nodes.map { $0.applying(apply) }
    }

    /// Gives every row its node, from here on.
    private mutating func buildNodes() {
        if builtNodes == nil { builtNodes = nodes }
    }
}

/// The rows beneath a branch of a hierarchical table — or a tree's roots — and
/// the loops among them that take payloads in between their rows, counted in
/// these rows' own numbering (``_TableRowList/insertions``).
struct _TableRowBranch<Value: Identifiable> {
    var nodes: [_TableRowNode<Value>]
    var insertions: [_TableRowInsertion] = []
    /// A tree's roots as the collection they came from, in place of
    /// ``nodes`` — `Table(_:children:)`'s, whose outline is kept from pass to
    /// pass (``_TableOutlineCache``).
    var roots: _TableOutlineRoots<Value>?
}

/// One row of a table, and — when it is a branch of a hierarchical table — how
/// to reach the rows beneath it.
struct _TableRowNode<Value: Identifiable> {
    /// The row's value.
    let value: Value

    /// The rows beneath this one, built only when the branch is opened — a
    /// closed folder's contents are never walked. `nil` for a leaf; an empty
    /// result is a branch with nothing in it, which still draws a triangle,
    /// as in SwiftUI.
    ///
    /// Main-actor isolated because building rows is: a `DisclosureTableRow`'s
    /// children come from its row builder, with the loops among them.
    private(set) var children: (@MainActor () -> _TableRowBranch<Value>)?

    /// The expansion a `DisclosureTableRow` was handed, or `nil` for one the
    /// table keeps itself.
    let isExpanded: Binding<Bool>?

    /// What the row modifiers around this row said about it.
    private(set) var traits = _TableRowTraits()

    /// This row with a row modifier applied — to it, and to the rows beneath
    /// it as they are built, since a modifier on a branch's content reaches
    /// every row that content makes.
    @MainActor
    func applying(_ apply: @escaping (inout _TableRowTraits) -> Void) -> Self {
        var node = self
        apply(&node.traits)
        if let children {
            node.children = {
                var branch = children()
                branch.nodes = branch.nodes.map { $0.applying(apply) }
                return branch
            }
        }
        return node
    }
}

extension TableRowContent {
    /// Appends the rows of `content`'s body: what content an app writes
    /// declares. Every row type the framework defines appends its own.
    ///
    /// Checked rather than assumed to be of the same row type, as the
    /// columns' default is: content whose body names another row type
    /// contributes nothing (and trips an assertion in a debug build).
    public static func _appendRows(_ content: Self, to rows: inout _TableRowList<TableRowValue>) {
        let body = tableRows(of: content.tableRowBody)
        guard let typed = body as? _TableRowList<TableRowValue> else {
            assertionFailure("\(Self.self)'s tableRowBody has rows of another type than its TableRowValue")
            return
        }
        rows.append(contentsOf: typed)
    }
}

/// The rows `content` declares, in order, flattened for the renderer.
@MainActor
func tableRows<Content: TableRowContent>(of content: Content) -> _TableRowList<Content.TableRowValue> {
    var rows = _TableRowList<Content.TableRowValue>()
    Content._appendRows(content, to: &rows)
    return rows
}

/// Appends `content`'s rows to `rows`.
@MainActor
func appendTableRows<Content: TableRowContent>(
    _ content: Content, to rows: inout _TableRowList<Content.TableRowValue>
) {
    Content._appendRows(content, to: &rows)
}

// MARK: - TableRow

/// A row that represents a data value in a table.
///
/// Create a row from a value when building a table's rows with the
/// `rows:` closure of a ``Table`` initializer:
///
/// ```swift
/// Table(of: Purchase.self) {
///     TableColumn("Item", value: \.item)
/// } rows: {
///     TableRow(Purchase(item: "Coffee", price: 2.5))
///     ForEach(purchases) { TableRow($0) }
/// }
/// ```
public struct TableRow<Value: Identifiable>: TableRowContent {
    public typealias TableRowValue = Value
    public typealias TableRowBody = Never

    /// The value the row represents.
    let value: Value

    /// Creates a table row for the given value.
    ///
    /// The table's columns build the row's cells from it.
    ///
    /// - Parameter value: The value of the row.
    public init(_ value: Value) {
        self.value = value
    }

    /// Never called: a row hands itself to the table directly.
    public var tableRowBody: Never { fatalError("TableRow is primitive table row content") }
}

extension TableRow {
    /// Appends this row: a row hands itself to the table directly.
    public static func _appendRows(_ content: Self, to rows: inout _TableRowList<Value>) {
        rows.append(content.value)
    }
}

// MARK: - TupleTableRowContent

/// A type of table row content that creates table rows created by a Swift
/// tuple of table rows.
///
/// You don't use this type directly: ``TableRowBuilder`` builds it from the
/// statements of a row closure.
public struct TupleTableRowContent<Value: Identifiable, T>: TableRowContent {
    public typealias TableRowValue = Value
    public typealias TableRowBody = Never

    /// The tuple of row content.
    public var value: T

    /// Appends the tuple's rows in order, built where the elements' types are
    /// still known.
    let appendElements: (inout _TableRowList<Value>) -> Void

    init(_ value: T, appendRows: @escaping (inout _TableRowList<Value>) -> Void) {
        self.value = value
        self.appendElements = appendRows
    }

    /// Never called: a tuple hands its rows to the table directly.
    public var tableRowBody: Never { fatalError("TupleTableRowContent renders its rows directly") }
}

extension TupleTableRowContent {
    /// Appends the tuple's rows, in order.
    public static func _appendRows(_ content: Self, to rows: inout _TableRowList<Value>) {
        content.appendElements(&rows)
    }
}

// MARK: - EmptyTableRowContent

/// A table row content that doesn't produce any rows.
///
/// You don't use this type directly: it stands for the header or footer a
/// row ``Section`` was not given.
public struct EmptyTableRowContent<Value: Identifiable>: TableRowContent {
    public typealias TableRowValue = Value
    public typealias TableRowBody = Never

    init() {}

    /// Never called: there are no rows to describe.
    public var tableRowBody: Never { fatalError("EmptyTableRowContent has no rows") }
}

extension EmptyTableRowContent {
    /// Appends nothing.
    public static func _appendRows(_ content: Self, to rows: inout _TableRowList<Value>) {}
}

// MARK: - TableForEachContent

/// A type of table row content that creates table rows created by iterating
/// over a collection.
///
/// You don't use this type directly: the ``Table`` initializers that take a
/// collection build their rows with it.
public struct TableForEachContent<Data: RandomAccessCollection>: TableRowContent
where Data.Element: Identifiable {
    public typealias TableRowValue = Data.Element

    /// The rows' data.
    let data: Data

    init(_ data: Data) {
        self.data = data
    }

    /// The type of the rows: one ``TableRow`` per element.
    ///
    /// Spelled out where SwiftUI's is opaque: SwiftUI declares the alias, and an
    /// opaque body here would declare none.
    public typealias TableRowBody = ForEach<Data, Data.Element.ID, TableRow<Data.Element>>

    /// The rows: one ``TableRow`` per element.
    public var tableRowBody: TableRowBody {
        ForEach(data)
    }
}

extension TableForEachContent {
    /// Appends a row for each element of the data.
    public static func _appendRows(_ content: Self, to rows: inout _TableRowList<Data.Element>) {
        rows.append(contentsOf: content.data)
    }
}

// MARK: - Never

extension Never: TableRowContent {
    public typealias TableRowBody = Never

    /// Never called: `Never` is the body type of primitive row content.
    public var tableRowBody: Never { fatalError("Never has no table row body") }
}

// MARK: - Optional

extension Optional: TableRowContent where Wrapped: TableRowContent {
    public typealias TableRowBody = Never

    /// Never called: an optional hands its rows to the table directly.
    public var tableRowBody: Never { fatalError("Optional renders its rows directly") }
}

extension Optional where Wrapped: TableRowContent {
    /// Appends the wrapped content's rows, or none.
    @MainActor
    public static func _appendRows(_ content: Self, to rows: inout _TableRowList<Wrapped.TableRowValue>) {
        guard let content else { return }
        appendTableRows(content, to: &rows)
    }
}

// MARK: - Group

extension Group: TableRowContent where Content: TableRowContent {
    public typealias TableRowBody = Never

    /// Never called: a group hands its rows to the table directly.
    public var tableRowBody: Never { fatalError("Group renders its rows directly") }

    /// Creates a group of table rows.
    ///
    /// - Parameter content: The rows to group.
    public init<R>(@TableRowBuilder<R> content: () -> Content) where R == Content.TableRowValue {
        self = .grouping(content())
    }
}

extension Group where Content: TableRowContent {
    /// Appends the group's rows.
    @MainActor
    public static func _appendRows(_ content: Self, to rows: inout _TableRowList<Content.TableRowValue>) {
        appendTableRows(content.content, to: &rows)
    }
}

// MARK: - Conditional

extension _ConditionalContent: TableRowContent
where
    TrueContent: TableRowContent, FalseContent: TableRowContent,
    TrueContent.TableRowValue == FalseContent.TableRowValue
{
    public typealias TableRowBody = Never

    /// Never called: a branch hands its rows to the table directly.
    public var tableRowBody: Never { fatalError("_ConditionalContent renders its rows directly") }
}

extension _ConditionalContent
where
    TrueContent: TableRowContent, FalseContent: TableRowContent,
    TrueContent.TableRowValue == FalseContent.TableRowValue
{
    /// Appends the rows of the branch taken.
    @MainActor
    public static func _appendRows(
        _ content: Self, to rows: inout _TableRowList<TrueContent.TableRowValue>
    ) {
        switch content {
        case .trueContent(let content): appendTableRows(content, to: &rows)
        case .falseContent(let content): appendTableRows(content, to: &rows)
        }
    }
}

// MARK: - ForEach

extension ForEach: _TableRowValued where Content: TableRowContent {
    public typealias TableRowValue = Content.TableRowValue
}

extension ForEach: TableRowContent where Content: TableRowContent {
    public typealias TableRowBody = Never

    /// Never called: a loop hands its rows to the table directly.
    public var tableRowBody: Never { fatalError("ForEach renders its rows directly") }

    /// Creates an instance that uniquely identifies and creates table rows
    /// across updates based on the identity of the underlying data.
    ///
    /// - Parameters:
    ///   - data: The identified data that the instance uses to create table
    ///     rows dynamically.
    ///   - content: The table row builder that creates rows dynamically.
    public init<V>(
        _ data: Data, @TableRowBuilder<V> content: @escaping (Data.Element) -> Content
    ) where ID == Data.Element.ID, V == Content.TableRowValue, Data.Element: Identifiable {
        self.init(storing: data, id: \Data.Element.id, directID: { $0.id }, content: content)
    }

    /// Creates an instance that uniquely identifies and creates table rows
    /// across updates based on the provided key path to the underlying data's
    /// identifier.
    ///
    /// - Parameters:
    ///   - data: The data that the instance uses to create table rows
    ///     dynamically.
    ///   - id: The key path to the provided data's identifier.
    ///   - content: The table row builder that creates rows dynamically.
    public init<V>(
        _ data: Data, id: KeyPath<Data.Element, ID>,
        @TableRowBuilder<V> content: @escaping (Data.Element) -> Content
    ) where V == Content.TableRowValue {
        self.init(storing: data, id: id, content: content)
    }

    /// Creates an instance that generates table rows for the elements of a
    /// collection: one ``TableRow`` each.
    ///
    /// - Parameter data: The identified data the rows are created from.
    public init(_ data: Data)
    where ID == Data.Element.ID, Content == TableRow<Data.Element>, Data.Element: Identifiable {
        self.init(storing: data, id: \Data.Element.id, directID: { $0.id }, content: { TableRow($0) })
    }

    /// Creates an instance that computes table rows over a given constant
    /// range.
    ///
    /// - Parameters:
    ///   - data: A constant range.
    ///   - content: The table row builder that creates rows dynamically.
    public init<V>(
        _ data: Range<Int>, @TableRowBuilder<V> content: @escaping (Int) -> Content
    ) where Data == Range<Int>, ID == Int, V == Content.TableRowValue {
        self.init(storing: data, id: \.self, directID: { $0 }, content: content)
    }
}

extension ForEach where Content: TableRowContent {
    /// Appends the rows built for each element, in order.
    @MainActor
    public static func _appendRows(_ content: Self, to rows: inout _TableRowList<Content.TableRowValue>) {
        for element in content.data {
            appendTableRows(content.content(element), to: &rows)
        }
    }
}

// MARK: - DynamicTableRowContent

/// A type of table row content that generates table rows from an underlying
/// collection of data.
///
/// ``ForEach`` is the conformer: its ``data`` is the collection its rows come
/// from.
@MainActor
public protocol DynamicTableRowContent: TableRowContent {
    /// The type of the underlying collection of data.
    associatedtype Data: Collection

    /// The collection of underlying data.
    var data: Data { get }
}

extension ForEach: DynamicTableRowContent where Content: TableRowContent {}
