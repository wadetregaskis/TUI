//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableColumnBuilder.swift
//
//  Created by LAYERED.work
//  License: MIT

// `SortComparator` is Foundation's.
import Foundation

// MARK: - Table Column Builder

/// A result builder that creates table column content from closures.
///
/// The `buildBlock` methods in this type create ``TableColumnContent``
/// instances based on the number and types of sources provided as parameters.
/// Don't use this type directly; the `columns` parameter of every ``Table``
/// initializer is annotated with it, and so are properties that factor columns
/// out of a table:
///
/// ```swift
/// @TableColumnBuilder<Person, Never>
/// var detailColumns: some TableColumnContent<Person, Never> {
///     TableColumn("Email", value: \.email)
///     TableColumn("Phone", value: \.phone)
/// }
/// ```
///
/// `Sort` is the comparator type of the table's `sortOrder` binding, or `Never`
/// for a table without one. Every method comes in two forms, as SwiftUI's do:
/// one for content that sorts with `Sort`, and one for content that cannot
/// sort at all — which is what lets an unsortable column sit in a sortable
/// table. The second is disfavoured, again as in SwiftUI: it is what makes a
/// `String` key-path column in a sortable table the sortable overload, and
/// what keeps the two from being ambiguous when `Sort` is `Never`.
///
/// There is no `buildArray`, so a `for` loop does not compile here, exactly as
/// in SwiftUI: ``TableColumnForEach`` builds columns from a collection.
@MainActor
@resultBuilder
public struct TableColumnBuilder<RowValue: Identifiable, Sort: SortComparator> {
    /// Creates a sortable table column expression whose value and sort types
    /// match those of the builder.
    public static func buildExpression<Content: View, Label: View>(
        _ column: TableColumn<RowValue, Sort, Content, Label>
    ) -> TableColumn<RowValue, Sort, Content, Label> {
        column
    }

    /// Creates a table column expression that cannot sort, whose value type
    /// matches that of the builder.
    @_disfavoredOverload
    public static func buildExpression<Content: View, Label: View>(
        _ column: TableColumn<RowValue, Never, Content, Label>
    ) -> TableColumn<RowValue, Never, Content, Label> {
        column
    }

    /// Creates a sortable table column expression whose value and sort types
    /// match those of the builder.
    public static func buildExpression<Column: TableColumnContent>(_ column: Column) -> Column
    where RowValue == Column.TableRowValue, Sort == Column.TableColumnSortComparator {
        column
    }

    /// Creates a table column expression that cannot sort, whose value type
    /// matches that of the builder.
    @_disfavoredOverload
    public static func buildExpression<Column: TableColumnContent>(_ column: Column) -> Column
    where RowValue == Column.TableRowValue, Column.TableColumnSortComparator == Never {
        column
    }

    /// Creates a single, sortable column result.
    public static func buildBlock<Column: TableColumnContent>(_ column: Column) -> Column
    where RowValue == Column.TableRowValue, Sort == Column.TableColumnSortComparator {
        column
    }

    /// Creates a single, unsortable column result.
    @_disfavoredOverload
    public static func buildBlock<Column: TableColumnContent>(_ column: Column) -> Column
    where RowValue == Column.TableRowValue, Column.TableColumnSortComparator == Never {
        column
    }

    /// Produces an optional column for an `if` with no `else`, sortable.
    public static func buildIf<C: TableColumnContent>(_ content: C?) -> C?
    where RowValue == C.TableRowValue, Sort == C.TableColumnSortComparator {
        content
    }

    /// Produces an optional column for an `if` with no `else`, unsortable.
    @_disfavoredOverload
    public static func buildIf<C: TableColumnContent>(_ content: C?) -> C?
    where RowValue == C.TableRowValue, C.TableColumnSortComparator == Never {
        content
    }

    /// Creates a column result for the first of two column content
    /// alternatives: the `if` branch of an `if`/`else`.
    public static func buildEither<T: TableColumnContent, F: TableColumnContent>(
        first: T
    ) -> _ConditionalContent<T, F>
    where
        RowValue == T.TableRowValue, Sort == T.TableColumnSortComparator,
        T.TableColumnSortComparator == F.TableColumnSortComparator,
        T.TableRowValue == F.TableRowValue
    {
        .trueContent(first)
    }

    /// The `if` branch of an `if`/`else` whose columns cannot sort.
    @_disfavoredOverload
    public static func buildEither<T: TableColumnContent, F: TableColumnContent>(
        first: T
    ) -> _ConditionalContent<T, F>
    where
        RowValue == T.TableRowValue, T.TableColumnSortComparator == Never,
        T.TableRowValue == F.TableRowValue, F.TableColumnSortComparator == Never
    {
        .trueContent(first)
    }

    /// Creates a column result for the second of two column content
    /// alternatives: the `else` branch of an `if`/`else`.
    public static func buildEither<T: TableColumnContent, F: TableColumnContent>(
        second: F
    ) -> _ConditionalContent<T, F>
    where
        RowValue == T.TableRowValue, Sort == T.TableColumnSortComparator,
        T.TableColumnSortComparator == F.TableColumnSortComparator,
        T.TableRowValue == F.TableRowValue
    {
        .falseContent(second)
    }

    /// The `else` branch of an `if`/`else` whose columns cannot sort.
    @_disfavoredOverload
    public static func buildEither<T: TableColumnContent, F: TableColumnContent>(
        second: F
    ) -> _ConditionalContent<T, F>
    where
        RowValue == T.TableRowValue, T.TableColumnSortComparator == Never,
        T.TableRowValue == F.TableRowValue, F.TableColumnSortComparator == Never
    {
        .falseContent(second)
    }

    /// Provides support for `if #available(…)` around sortable columns.
    public static func buildLimitedAvailability(
        _ content: any TableColumnContent<RowValue, Sort>
    ) -> some TableColumnContent<RowValue, Sort> {
        _AnyTableColumnContent<RowValue, Sort>(content)
    }

    /// Provides support for `if #available(…)` around columns that cannot
    /// sort.
    @_disfavoredOverload
    public static func buildLimitedAvailability(
        _ content: any TableColumnContent<RowValue, Never>
    ) -> some TableColumnContent<RowValue, Never> {
        _AnyTableColumnContent<RowValue, Never>(content)
    }
}

// MARK: - Erased column content

/// Column content of an erased type, which is all `if #available(…)` can
/// produce: the branch's concrete type may not exist on an older system.
struct _AnyTableColumnContent<RowValue: Identifiable, Sort: SortComparator>:
    TableColumnContent
{
    typealias TableRowValue = RowValue
    typealias TableColumnSortComparator = Sort
    typealias TableColumnBody = Never

    /// The flattened columns of the erased content, taken when it is erased.
    let columns: [_TableColumnSpec<RowValue>]

    init<Content: TableColumnContent>(_ content: Content) where Content.TableRowValue == RowValue {
        columns = tableColumns(of: content)
    }

    /// Never called: erased content hands its columns to the table directly.
    var tableColumnBody: Never { fatalError("_AnyTableColumnContent renders its columns directly") }
}

extension _AnyTableColumnContent {
    static func _appendColumns(_ content: Self, to columns: inout _TableColumnList<RowValue>) {
        columns.specs += content.columns
    }
}
