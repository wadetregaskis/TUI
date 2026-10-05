//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableColumnContent.swift
//
//  The protocol a table's columns are written in, the content types that
//  compose columns, and the walk that flattens them for the renderer.
//
//  Created by Wade Tregaskis
//  License: MIT

// `SortComparator` is Foundation's.
import Foundation

// MARK: - TableColumnContent

/// A type used to represent columns within a table.
///
/// This type provides the body content of the column, as well as the types of
/// the column's row values and the comparator used to sort rows. Factor column
/// content into separate properties or types the way SwiftUI does:
///
/// ```swift
/// var body: some View {
///     Table(people, selection: $selection, sortOrder: $sortOrder) {
///         nameColumns
///         TableColumn("Location", value: \.location)
///     }
/// }
///
/// @TableColumnBuilder<Person, KeyPathComparator<Person>>
/// private var nameColumns: some TableColumnContent<Person, KeyPathComparator<Person>> {
///     TableColumn("First Name", value: \.firstName)
///     TableColumn("Last Name", value: \.lastName)
/// }
/// ```
///
/// The property's primary associated type ``TableRowValue`` is the row type,
/// and ``TableColumnSortComparator`` is the comparator its sortable columns
/// sort with — `Never` for content that cannot sort.
///
/// - Note: SwiftUI declares ``tableColumnBody`` `nonisolated`. Here it is
///   main-actor isolated, like the rest of the protocol: every column
///   initializer in this framework is, so a nonisolated body could not build
///   the columns it returns.
@MainActor
public protocol TableColumnContent<TableRowValue, TableColumnSortComparator>: _TableRowValued {
    /// The type of value of rows presented by this column content.
    associatedtype TableRowValue = TableColumnBody.TableRowValue

    /// The type of sort comparator associated with this table column content.
    associatedtype TableColumnSortComparator: SortComparator =
        TableColumnBody.TableColumnSortComparator

    /// The type of content representing the body of this table column content.
    associatedtype TableColumnBody: TableColumnContent

    /// The composition of content that comprise the table column content.
    var tableColumnBody: TableColumnBody { get }

    /// Appends `content`'s columns to `columns`, in order.
    ///
    /// Not to be implemented by hand. Every column type the framework defines
    /// implements it, and the default — for content an app writes — finds the
    /// columns of ``tableColumnBody``.
    ///
    /// A static requirement rather than a cast to an internal protocol, for
    /// the reason ``View/_renderSelf(_:context:)`` is one. That cast was to a
    /// protocol constrained by the row type, `any P<Content.TableRowValue>`,
    /// whose metadata the runtime looked up by mangled name on every call —
    /// a demangle per column per body evaluation, about 1.8% of a frame of the
    /// `truncate` scenario for its six columns. SwiftUI's own protocol has a
    /// hidden requirement in the same place.
    static func _appendColumns(_ content: Self, to columns: inout _TableColumnList<TableRowValue>)
}

// MARK: - The row type, declared once

/// What table columns and table rows have in common: the type of the rows.
///
/// You don't use this protocol directly. ``TableColumnContent`` and
/// ``TableRowContent`` both refine it, so that a type that is both — `Group`,
/// `Optional`, `_ConditionalContent` — states its row type ONCE, here, rather
/// than once per conformance. Two type aliases of one name on one type (as
/// SwiftUI declares them) are ambiguous to the debug-info round trip of an
/// asserts build of the compiler — the swift.org toolchains for macOS — which
/// then aborts on any debug build that names, say, `Group<…>.TableRowValue`.
public protocol _TableRowValued {
    /// The type of value of the rows.
    associatedtype TableRowValue: Identifiable
}

// MARK: - Flattening

/// The columns of some ``TableColumnContent``, in order, as a table reads them.
///
/// You don't use this type directly: it is what
/// ``TableColumnContent/_appendColumns(_:to:)`` appends to.
public struct _TableColumnList<RowValue> {
    /// The columns, in order.
    var specs: [_TableColumnSpec<RowValue>] = []
}

extension TableColumnContent {
    /// Appends the columns of `content`'s body: what content an app writes
    /// declares. Every column type the framework defines appends its own.
    ///
    /// The body's row type is the content's in every case that compiles
    /// against ``TableColumnBuilder``, but the protocol cannot say so, so it is
    /// checked rather than assumed: content whose body names another row type
    /// contributes nothing (and trips an assertion in a debug build).
    public static func _appendColumns(_ content: Self, to columns: inout _TableColumnList<TableRowValue>) {
        let body = tableColumns(of: content.tableColumnBody)
        guard let typed = body as? [_TableColumnSpec<TableRowValue>] else {
            assertionFailure(
                "\(Self.self)'s tableColumnBody has rows of another type than its TableRowValue")
            return
        }
        columns.specs += typed
    }
}

/// The columns `content` declares, in order, flattened for the renderer.
@MainActor
func tableColumns<Content: TableColumnContent>(
    of content: Content
) -> [_TableColumnSpec<Content.TableRowValue>] {
    var columns = _TableColumnList<Content.TableRowValue>()
    Content._appendColumns(content, to: &columns)
    return columns.specs
}

/// Appends `content`'s columns to `columns`.
@MainActor
func appendTableColumns<Content: TableColumnContent>(
    _ content: Content, to columns: inout _TableColumnList<Content.TableRowValue>
) {
    Content._appendColumns(content, to: &columns)
}

// MARK: - Never

extension Never: _TableRowValued {
    public typealias TableRowValue = Never
}

extension Never: TableColumnContent {
    public typealias TableColumnSortComparator = Never
    public typealias TableColumnBody = Never

    /// Never called: `Never` is the body type of primitive column content.
    public var tableColumnBody: Never { fatalError("Never has no table column body") }
}

// MARK: - Optional

extension Optional: _TableRowValued where Wrapped: _TableRowValued {
    public typealias TableRowValue = Wrapped.TableRowValue
}

extension Optional: TableColumnContent where Wrapped: TableColumnContent {
    public typealias TableColumnSortComparator = Wrapped.TableColumnSortComparator
    public typealias TableColumnBody = Never

    /// Never called: an optional hands its columns to the table directly.
    public var tableColumnBody: Never { fatalError("Optional renders its columns directly") }
}

extension Optional where Wrapped: TableColumnContent {
    /// Appends the wrapped content's columns, or none.
    @MainActor
    public static func _appendColumns(
        _ content: Self, to columns: inout _TableColumnList<Wrapped.TableRowValue>
    ) {
        guard let content else { return }
        appendTableColumns(content, to: &columns)
    }
}

// MARK: - Group

extension Group: _TableRowValued where Content: _TableRowValued {
    public typealias TableRowValue = Content.TableRowValue
}

extension Group: TableColumnContent where Content: TableColumnContent {
    public typealias TableColumnSortComparator = Content.TableColumnSortComparator
    public typealias TableColumnBody = Never

    /// Never called: a group hands its columns to the table directly.
    public var tableColumnBody: Never { fatalError("Group renders its columns directly") }

    /// Creates a group of table columns.
    ///
    /// Use it to apply a column modifier to several columns at once, or to
    /// return several columns from one branch.
    ///
    /// - Parameter content: The columns to group.
    public init<R, C>(@TableColumnBuilder<R, C> content: () -> Content)
    where R == Content.TableRowValue, C == Content.TableColumnSortComparator {
        self.content = content()
    }
}

extension Group where Content: TableColumnContent {
    /// Appends the group's columns.
    @MainActor
    public static func _appendColumns(
        _ content: Self, to columns: inout _TableColumnList<Content.TableRowValue>
    ) {
        appendTableColumns(content.content, to: &columns)
    }
}

// MARK: - Conditional

extension _ConditionalContent: _TableRowValued
where
    TrueContent: _TableRowValued, FalseContent: _TableRowValued,
    TrueContent.TableRowValue == FalseContent.TableRowValue
{
    public typealias TableRowValue = TrueContent.TableRowValue
}

extension _ConditionalContent: TableColumnContent
where
    TrueContent: TableColumnContent, FalseContent: TableColumnContent,
    TrueContent.TableRowValue == FalseContent.TableRowValue,
    TrueContent.TableColumnSortComparator == FalseContent.TableColumnSortComparator
{
    public typealias TableColumnSortComparator = TrueContent.TableColumnSortComparator
    public typealias TableColumnBody = Never

    /// Never called: a branch hands its columns to the table directly.
    public var tableColumnBody: Never { fatalError("_ConditionalContent renders its columns directly") }
}

extension _ConditionalContent
where
    TrueContent: TableColumnContent, FalseContent: TableColumnContent,
    TrueContent.TableRowValue == FalseContent.TableRowValue,
    TrueContent.TableColumnSortComparator == FalseContent.TableColumnSortComparator
{
    /// Appends the columns of the branch taken.
    @MainActor
    public static func _appendColumns(
        _ content: Self, to columns: inout _TableColumnList<TrueContent.TableRowValue>
    ) {
        switch content {
        case .trueContent(let content): appendTableColumns(content, to: &columns)
        case .falseContent(let content): appendTableColumns(content, to: &columns)
        }
    }
}

// MARK: - TupleTableColumnContent

/// A type of table column content that creates table columns created by a
/// Swift tuple of table columns.
///
/// You don't use this type directly: ``TableColumnBuilder`` builds it from the
/// statements of a column closure.
public struct TupleTableColumnContent<RowValue: Identifiable, Sort: SortComparator, T>:
    TableColumnContent
{
    public typealias TableRowValue = RowValue
    public typealias TableColumnSortComparator = Sort
    public typealias TableColumnBody = Never

    /// The tuple of column content.
    public var value: T

    /// Appends the tuple's columns in order. Built where the elements' types
    /// are still known, so the tuple need not be taken apart again.
    let appendElements: (inout _TableColumnList<RowValue>) -> Void

    init(_ value: T, appendColumns: @escaping (inout _TableColumnList<RowValue>) -> Void) {
        self.value = value
        self.appendElements = appendColumns
    }

    /// Never called: a tuple hands its columns to the table directly.
    public var tableColumnBody: Never { fatalError("TupleTableColumnContent renders its columns directly") }
}

extension TupleTableColumnContent {
    /// Appends the tuple's columns, in order.
    public static func _appendColumns(_ content: Self, to columns: inout _TableColumnList<RowValue>) {
        content.appendElements(&columns)
    }
}
