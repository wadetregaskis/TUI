//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableRowContent.swift
//
//  The protocol a table's rows are written in, the content types that compose
//  rows, and the walk that flattens them for the renderer.
//
//  Created by Wade Tregaskis
//  License: MIT

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
}

// MARK: - Flattening

/// A table's rows, in order, for the renderer: each a value, with the rows
/// beneath it when it is a branch of a hierarchical table.
struct _TableRowList<Value: Identifiable> {
    /// The rows, in order.
    private(set) var nodes: [_TableRowNode<Value>] = []

    /// Whether any row has rows beneath it — only then is the table an outline.
    private(set) var isTree = false

    /// The rows' values, in order: the whole table, when it is not a tree.
    var values: [Value] { nodes.map(\.value) }

    /// Appends a row with nothing beneath it.
    mutating func append(_ value: Value) {
        nodes.append(_TableRowNode(value: value, children: nil, isExpanded: nil))
    }

    /// Appends rows with nothing beneath them.
    mutating func append<S: Sequence>(contentsOf values: S) where S.Element == Value {
        nodes += values.lazy.map { _TableRowNode(value: $0, children: nil, isExpanded: nil) }
    }

    /// Appends a row of a tree — a branch, or a leaf beside one — which makes
    /// the table an outline.
    mutating func append(treeNode node: _TableRowNode<Value>) {
        isTree = true
        nodes.append(node)
    }

    /// Appends another list's rows.
    mutating func append(contentsOf other: _TableRowList<Value>) {
        isTree = isTree || other.isTree
        nodes += other.nodes
    }
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
    /// children come from its row builder.
    let children: (@MainActor () -> [_TableRowNode<Value>])?

    /// The expansion a `DisclosureTableRow` was handed, or `nil` for one the
    /// table keeps itself.
    let isExpanded: Binding<Bool>?
}

/// Row content that hands the renderer its rows itself, rather than through
/// ``TableRowContent/tableRowBody``.
///
/// Every row type this framework defines is one; a `TableRowContent` an app
/// writes is not, and is walked through its body. The row twin of
/// ``_TableColumnPrimitive``.
@MainActor
protocol _TableRowPrimitive<PrimitiveRowValue> {
    /// The value of the rows this content appends; always its
    /// ``TableRowContent/TableRowValue``.
    associatedtype PrimitiveRowValue: Identifiable

    /// Appends this content's rows, in order.
    func appendRows(to rows: inout _TableRowList<PrimitiveRowValue>)
}

/// The rows `content` declares, in order, flattened for the renderer.
@MainActor
func tableRows<Content: TableRowContent>(of content: Content) -> _TableRowList<Content.TableRowValue> {
    var rows = _TableRowList<Content.TableRowValue>()
    appendTableRows(content, to: &rows)
    return rows
}

/// Appends `content`'s rows to `rows`: a primitive's own, anything else's
/// through its body — checked rather than assumed to be of the same row type,
/// as ``appendTableColumns(_:to:)`` does for columns.
@MainActor
func appendTableRows<Content: TableRowContent>(
    _ content: Content, to rows: inout _TableRowList<Content.TableRowValue>
) {
    if let primitive = content as? any _TableRowPrimitive<Content.TableRowValue> {
        primitive.appendRows(to: &rows)
        return
    }
    let body = tableRows(of: content.tableRowBody)
    guard let typed = body as? _TableRowList<Content.TableRowValue> else {
        assertionFailure("\(Content.self)'s tableRowBody has rows of another type than its TableRowValue")
        return
    }
    rows.append(contentsOf: typed)
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

extension TableRow: _TableRowPrimitive {
    typealias PrimitiveRowValue = Value

    func appendRows(to rows: inout _TableRowList<Value>) {
        rows.append(value)
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

extension TupleTableRowContent: _TableRowPrimitive {
    typealias PrimitiveRowValue = Value

    func appendRows(to rows: inout _TableRowList<Value>) {
        appendElements(&rows)
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

extension EmptyTableRowContent: _TableRowPrimitive {
    typealias PrimitiveRowValue = Value

    func appendRows(to rows: inout _TableRowList<Value>) {}
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
    /// Named rather than opaque, as SwiftUI's is, so the type states it.
    public typealias TableRowBody = ForEach<Data, Data.Element.ID, TableRow<Data.Element>>

    /// The rows: one ``TableRow`` per element.
    public var tableRowBody: TableRowBody {
        ForEach(data)
    }
}

extension TableForEachContent: _TableRowPrimitive {
    typealias PrimitiveRowValue = Data.Element

    func appendRows(to rows: inout _TableRowList<Data.Element>) {
        rows.append(contentsOf: data)
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

extension Optional: _TableRowPrimitive where Wrapped: TableRowContent {
    typealias PrimitiveRowValue = Wrapped.TableRowValue

    func appendRows(to rows: inout _TableRowList<Wrapped.TableRowValue>) {
        guard let self else { return }
        appendTableRows(self, to: &rows)
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
        self.content = content()
    }
}

extension Group: _TableRowPrimitive where Content: TableRowContent {
    typealias PrimitiveRowValue = Content.TableRowValue

    func appendRows(to rows: inout _TableRowList<Content.TableRowValue>) {
        appendTableRows(content, to: &rows)
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

extension _ConditionalContent: _TableRowPrimitive
where
    TrueContent: TableRowContent, FalseContent: TableRowContent,
    TrueContent.TableRowValue == FalseContent.TableRowValue
{
    typealias PrimitiveRowValue = TrueContent.TableRowValue

    func appendRows(to rows: inout _TableRowList<TrueContent.TableRowValue>) {
        switch self {
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
        self.init(storing: data, id: \Data.Element.id, content: content)
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
        self.init(storing: data, id: \Data.Element.id) { TableRow($0) }
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
        self.init(storing: data, id: \.self, content: content)
    }
}

extension ForEach: _TableRowPrimitive where Content: TableRowContent {
    typealias PrimitiveRowValue = Content.TableRowValue

    func appendRows(to rows: inout _TableRowList<Content.TableRowValue>) {
        for element in data {
            appendTableRows(content(element), to: &rows)
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
