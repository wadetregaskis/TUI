//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableColumnBuilder+Blocks.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// `SortComparator` is Foundation's.
import Foundation

// SwiftUI's builder spells out every arity to ten as a pair of overloads, and
// each arity's result carries a tuple of that many column types — so the
// longest signatures here have ten parameters and a ten-member tuple by
// design.
// swiftlint:disable function_parameter_count large_tuple

// MARK: - Blocks of two to ten columns

extension TableColumnBuilder {
    /// Creates a sortable column result from two sources.
    public static func buildBlock<
        C0: TableColumnContent, C1: TableColumnContent
    >(
        _ c0: C0, _ c1: C1
    ) -> TupleTableColumnContent<RowValue, Sort, (C0, C1)>
    where
        RowValue == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue
    {
        TupleTableColumnContent((c0, c1)) { columns in
            appendTableColumns(c0, to: &columns)
            appendTableColumns(c1, to: &columns)
        }
    }

    /// Creates an unsortable column result from two sources.
    @_disfavoredOverload
    public static func buildBlock<
        C0: TableColumnContent, C1: TableColumnContent
    >(
        _ c0: C0, _ c1: C1
    ) -> TupleTableColumnContent<RowValue, Never, (C0, C1)>
    where
        RowValue == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue,
        C0.TableColumnSortComparator == Never, C1.TableColumnSortComparator == Never
    {
        TupleTableColumnContent((c0, c1)) { columns in
            appendTableColumns(c0, to: &columns)
            appendTableColumns(c1, to: &columns)
        }
    }

    /// Creates a sortable column result from three sources.
    public static func buildBlock<
        C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2
    ) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2)>
    where
        RowValue == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue,
        C2.TableRowValue == C0.TableRowValue
    {
        TupleTableColumnContent((c0, c1, c2)) { columns in
            appendTableColumns(c0, to: &columns)
            appendTableColumns(c1, to: &columns)
            appendTableColumns(c2, to: &columns)
        }
    }

    /// Creates an unsortable column result from three sources.
    @_disfavoredOverload
    public static func buildBlock<
        C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2
    ) -> TupleTableColumnContent<RowValue, Never, (C0, C1, C2)>
    where
        RowValue == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue,
        C2.TableRowValue == C0.TableRowValue, C0.TableColumnSortComparator == Never,
        C1.TableColumnSortComparator == Never, C2.TableColumnSortComparator == Never
    {
        TupleTableColumnContent((c0, c1, c2)) { columns in
            appendTableColumns(c0, to: &columns)
            appendTableColumns(c1, to: &columns)
            appendTableColumns(c2, to: &columns)
        }
    }

    /// Creates a sortable column result from four sources.
    public static func buildBlock<
        C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent,
        C3: TableColumnContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3
    ) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3)>
    where
        RowValue == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue,
        C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue
    {
        TupleTableColumnContent((c0, c1, c2, c3)) { columns in
            appendTableColumns(c0, to: &columns)
            appendTableColumns(c1, to: &columns)
            appendTableColumns(c2, to: &columns)
            appendTableColumns(c3, to: &columns)
        }
    }

    /// Creates an unsortable column result from four sources.
    @_disfavoredOverload
    public static func buildBlock<
        C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent,
        C3: TableColumnContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3
    ) -> TupleTableColumnContent<RowValue, Never, (C0, C1, C2, C3)>
    where
        RowValue == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue,
        C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue,
        C0.TableColumnSortComparator == Never, C1.TableColumnSortComparator == Never,
        C2.TableColumnSortComparator == Never, C3.TableColumnSortComparator == Never
    {
        TupleTableColumnContent((c0, c1, c2, c3)) { columns in
            appendTableColumns(c0, to: &columns)
            appendTableColumns(c1, to: &columns)
            appendTableColumns(c2, to: &columns)
            appendTableColumns(c3, to: &columns)
        }
    }

    /// Creates a sortable column result from five sources.
    public static func buildBlock<
        C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent,
        C3: TableColumnContent, C4: TableColumnContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4
    ) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3, C4)>
    where
        RowValue == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue,
        C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue,
        C4.TableRowValue == C0.TableRowValue
    {
        TupleTableColumnContent((c0, c1, c2, c3, c4)) { columns in
            appendTableColumns(c0, to: &columns)
            appendTableColumns(c1, to: &columns)
            appendTableColumns(c2, to: &columns)
            appendTableColumns(c3, to: &columns)
            appendTableColumns(c4, to: &columns)
        }
    }

    /// Creates an unsortable column result from five sources.
    @_disfavoredOverload
    public static func buildBlock<
        C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent,
        C3: TableColumnContent, C4: TableColumnContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4
    ) -> TupleTableColumnContent<RowValue, Never, (C0, C1, C2, C3, C4)>
    where
        RowValue == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue,
        C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue,
        C4.TableRowValue == C0.TableRowValue, C0.TableColumnSortComparator == Never,
        C1.TableColumnSortComparator == Never, C2.TableColumnSortComparator == Never,
        C3.TableColumnSortComparator == Never, C4.TableColumnSortComparator == Never
    {
        TupleTableColumnContent((c0, c1, c2, c3, c4)) { columns in
            appendTableColumns(c0, to: &columns)
            appendTableColumns(c1, to: &columns)
            appendTableColumns(c2, to: &columns)
            appendTableColumns(c3, to: &columns)
            appendTableColumns(c4, to: &columns)
        }
    }

    /// Creates a sortable column result from six sources.
    public static func buildBlock<
        C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent,
        C3: TableColumnContent, C4: TableColumnContent, C5: TableColumnContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4,
        _ c5: C5
    ) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3, C4, C5)>
    where
        RowValue == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue,
        C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue,
        C4.TableRowValue == C0.TableRowValue, C5.TableRowValue == C0.TableRowValue
    {
        TupleTableColumnContent((c0, c1, c2, c3, c4, c5)) { columns in
            appendTableColumns(c0, to: &columns)
            appendTableColumns(c1, to: &columns)
            appendTableColumns(c2, to: &columns)
            appendTableColumns(c3, to: &columns)
            appendTableColumns(c4, to: &columns)
            appendTableColumns(c5, to: &columns)
        }
    }

    /// Creates an unsortable column result from six sources.
    @_disfavoredOverload
    public static func buildBlock<
        C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent,
        C3: TableColumnContent, C4: TableColumnContent, C5: TableColumnContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4,
        _ c5: C5
    ) -> TupleTableColumnContent<RowValue, Never, (C0, C1, C2, C3, C4, C5)>
    where
        RowValue == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue,
        C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue,
        C4.TableRowValue == C0.TableRowValue, C5.TableRowValue == C0.TableRowValue,
        C0.TableColumnSortComparator == Never, C1.TableColumnSortComparator == Never,
        C2.TableColumnSortComparator == Never, C3.TableColumnSortComparator == Never,
        C4.TableColumnSortComparator == Never, C5.TableColumnSortComparator == Never
    {
        TupleTableColumnContent((c0, c1, c2, c3, c4, c5)) { columns in
            appendTableColumns(c0, to: &columns)
            appendTableColumns(c1, to: &columns)
            appendTableColumns(c2, to: &columns)
            appendTableColumns(c3, to: &columns)
            appendTableColumns(c4, to: &columns)
            appendTableColumns(c5, to: &columns)
        }
    }

    /// Creates a sortable column result from seven sources.
    public static func buildBlock<
        C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent,
        C3: TableColumnContent, C4: TableColumnContent, C5: TableColumnContent,
        C6: TableColumnContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4,
        _ c5: C5, _ c6: C6
    ) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3, C4, C5, C6)>
    where
        RowValue == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue,
        C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue,
        C4.TableRowValue == C0.TableRowValue, C5.TableRowValue == C0.TableRowValue,
        C6.TableRowValue == C0.TableRowValue
    {
        TupleTableColumnContent((c0, c1, c2, c3, c4, c5, c6)) { columns in
            appendTableColumns(c0, to: &columns)
            appendTableColumns(c1, to: &columns)
            appendTableColumns(c2, to: &columns)
            appendTableColumns(c3, to: &columns)
            appendTableColumns(c4, to: &columns)
            appendTableColumns(c5, to: &columns)
            appendTableColumns(c6, to: &columns)
        }
    }

    /// Creates an unsortable column result from seven sources.
    @_disfavoredOverload
    public static func buildBlock<
        C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent,
        C3: TableColumnContent, C4: TableColumnContent, C5: TableColumnContent,
        C6: TableColumnContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4,
        _ c5: C5, _ c6: C6
    ) -> TupleTableColumnContent<RowValue, Never, (C0, C1, C2, C3, C4, C5, C6)>
    where
        RowValue == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue,
        C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue,
        C4.TableRowValue == C0.TableRowValue, C5.TableRowValue == C0.TableRowValue,
        C6.TableRowValue == C0.TableRowValue, C0.TableColumnSortComparator == Never,
        C1.TableColumnSortComparator == Never, C2.TableColumnSortComparator == Never,
        C3.TableColumnSortComparator == Never, C4.TableColumnSortComparator == Never,
        C5.TableColumnSortComparator == Never, C6.TableColumnSortComparator == Never
    {
        TupleTableColumnContent((c0, c1, c2, c3, c4, c5, c6)) { columns in
            appendTableColumns(c0, to: &columns)
            appendTableColumns(c1, to: &columns)
            appendTableColumns(c2, to: &columns)
            appendTableColumns(c3, to: &columns)
            appendTableColumns(c4, to: &columns)
            appendTableColumns(c5, to: &columns)
            appendTableColumns(c6, to: &columns)
        }
    }

    /// Creates a sortable column result from eight sources.
    public static func buildBlock<
        C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent,
        C3: TableColumnContent, C4: TableColumnContent, C5: TableColumnContent,
        C6: TableColumnContent, C7: TableColumnContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4,
        _ c5: C5, _ c6: C6, _ c7: C7
    ) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3, C4, C5, C6, C7)>
    where
        RowValue == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue,
        C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue,
        C4.TableRowValue == C0.TableRowValue, C5.TableRowValue == C0.TableRowValue,
        C6.TableRowValue == C0.TableRowValue, C7.TableRowValue == C0.TableRowValue
    {
        TupleTableColumnContent((c0, c1, c2, c3, c4, c5, c6, c7)) { columns in
            appendTableColumns(c0, to: &columns)
            appendTableColumns(c1, to: &columns)
            appendTableColumns(c2, to: &columns)
            appendTableColumns(c3, to: &columns)
            appendTableColumns(c4, to: &columns)
            appendTableColumns(c5, to: &columns)
            appendTableColumns(c6, to: &columns)
            appendTableColumns(c7, to: &columns)
        }
    }

    /// Creates an unsortable column result from eight sources.
    @_disfavoredOverload
    public static func buildBlock<
        C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent,
        C3: TableColumnContent, C4: TableColumnContent, C5: TableColumnContent,
        C6: TableColumnContent, C7: TableColumnContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4,
        _ c5: C5, _ c6: C6, _ c7: C7
    ) -> TupleTableColumnContent<RowValue, Never, (C0, C1, C2, C3, C4, C5, C6, C7)>
    where
        RowValue == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue,
        C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue,
        C4.TableRowValue == C0.TableRowValue, C5.TableRowValue == C0.TableRowValue,
        C6.TableRowValue == C0.TableRowValue, C7.TableRowValue == C0.TableRowValue,
        C0.TableColumnSortComparator == Never, C1.TableColumnSortComparator == Never,
        C2.TableColumnSortComparator == Never, C3.TableColumnSortComparator == Never,
        C4.TableColumnSortComparator == Never, C5.TableColumnSortComparator == Never,
        C6.TableColumnSortComparator == Never, C7.TableColumnSortComparator == Never
    {
        TupleTableColumnContent((c0, c1, c2, c3, c4, c5, c6, c7)) { columns in
            appendTableColumns(c0, to: &columns)
            appendTableColumns(c1, to: &columns)
            appendTableColumns(c2, to: &columns)
            appendTableColumns(c3, to: &columns)
            appendTableColumns(c4, to: &columns)
            appendTableColumns(c5, to: &columns)
            appendTableColumns(c6, to: &columns)
            appendTableColumns(c7, to: &columns)
        }
    }

    /// Creates a sortable column result from nine sources.
    public static func buildBlock<
        C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent,
        C3: TableColumnContent, C4: TableColumnContent, C5: TableColumnContent,
        C6: TableColumnContent, C7: TableColumnContent, C8: TableColumnContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4,
        _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8
    ) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3, C4, C5, C6, C7, C8)>
    where
        RowValue == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue,
        C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue,
        C4.TableRowValue == C0.TableRowValue, C5.TableRowValue == C0.TableRowValue,
        C6.TableRowValue == C0.TableRowValue, C7.TableRowValue == C0.TableRowValue,
        C8.TableRowValue == C0.TableRowValue
    {
        TupleTableColumnContent((c0, c1, c2, c3, c4, c5, c6, c7, c8)) { columns in
            appendTableColumns(c0, to: &columns)
            appendTableColumns(c1, to: &columns)
            appendTableColumns(c2, to: &columns)
            appendTableColumns(c3, to: &columns)
            appendTableColumns(c4, to: &columns)
            appendTableColumns(c5, to: &columns)
            appendTableColumns(c6, to: &columns)
            appendTableColumns(c7, to: &columns)
            appendTableColumns(c8, to: &columns)
        }
    }

    /// Creates an unsortable column result from nine sources.
    @_disfavoredOverload
    public static func buildBlock<
        C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent,
        C3: TableColumnContent, C4: TableColumnContent, C5: TableColumnContent,
        C6: TableColumnContent, C7: TableColumnContent, C8: TableColumnContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4,
        _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8
    ) -> TupleTableColumnContent<RowValue, Never, (C0, C1, C2, C3, C4, C5, C6, C7, C8)>
    where
        RowValue == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue,
        C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue,
        C4.TableRowValue == C0.TableRowValue, C5.TableRowValue == C0.TableRowValue,
        C6.TableRowValue == C0.TableRowValue, C7.TableRowValue == C0.TableRowValue,
        C8.TableRowValue == C0.TableRowValue, C0.TableColumnSortComparator == Never,
        C1.TableColumnSortComparator == Never, C2.TableColumnSortComparator == Never,
        C3.TableColumnSortComparator == Never, C4.TableColumnSortComparator == Never,
        C5.TableColumnSortComparator == Never, C6.TableColumnSortComparator == Never,
        C7.TableColumnSortComparator == Never, C8.TableColumnSortComparator == Never
    {
        TupleTableColumnContent((c0, c1, c2, c3, c4, c5, c6, c7, c8)) { columns in
            appendTableColumns(c0, to: &columns)
            appendTableColumns(c1, to: &columns)
            appendTableColumns(c2, to: &columns)
            appendTableColumns(c3, to: &columns)
            appendTableColumns(c4, to: &columns)
            appendTableColumns(c5, to: &columns)
            appendTableColumns(c6, to: &columns)
            appendTableColumns(c7, to: &columns)
            appendTableColumns(c8, to: &columns)
        }
    }

    /// Creates a sortable column result from ten sources.
    public static func buildBlock<
        C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent,
        C3: TableColumnContent, C4: TableColumnContent, C5: TableColumnContent,
        C6: TableColumnContent, C7: TableColumnContent, C8: TableColumnContent,
        C9: TableColumnContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4,
        _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9
    ) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3, C4, C5, C6, C7, C8, C9)>
    where
        RowValue == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue,
        C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue,
        C4.TableRowValue == C0.TableRowValue, C5.TableRowValue == C0.TableRowValue,
        C6.TableRowValue == C0.TableRowValue, C7.TableRowValue == C0.TableRowValue,
        C8.TableRowValue == C0.TableRowValue, C9.TableRowValue == C0.TableRowValue
    {
        TupleTableColumnContent((c0, c1, c2, c3, c4, c5, c6, c7, c8, c9)) { columns in
            appendTableColumns(c0, to: &columns)
            appendTableColumns(c1, to: &columns)
            appendTableColumns(c2, to: &columns)
            appendTableColumns(c3, to: &columns)
            appendTableColumns(c4, to: &columns)
            appendTableColumns(c5, to: &columns)
            appendTableColumns(c6, to: &columns)
            appendTableColumns(c7, to: &columns)
            appendTableColumns(c8, to: &columns)
            appendTableColumns(c9, to: &columns)
        }
    }

    /// Creates an unsortable column result from ten sources.
    @_disfavoredOverload
    public static func buildBlock<
        C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent,
        C3: TableColumnContent, C4: TableColumnContent, C5: TableColumnContent,
        C6: TableColumnContent, C7: TableColumnContent, C8: TableColumnContent,
        C9: TableColumnContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4,
        _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9
    ) -> TupleTableColumnContent<RowValue, Never, (C0, C1, C2, C3, C4, C5, C6, C7, C8, C9)>
    where
        RowValue == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue,
        C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue,
        C4.TableRowValue == C0.TableRowValue, C5.TableRowValue == C0.TableRowValue,
        C6.TableRowValue == C0.TableRowValue, C7.TableRowValue == C0.TableRowValue,
        C8.TableRowValue == C0.TableRowValue, C9.TableRowValue == C0.TableRowValue,
        C0.TableColumnSortComparator == Never, C1.TableColumnSortComparator == Never,
        C2.TableColumnSortComparator == Never, C3.TableColumnSortComparator == Never,
        C4.TableColumnSortComparator == Never, C5.TableColumnSortComparator == Never,
        C6.TableColumnSortComparator == Never, C7.TableColumnSortComparator == Never,
        C8.TableColumnSortComparator == Never, C9.TableColumnSortComparator == Never
    {
        TupleTableColumnContent((c0, c1, c2, c3, c4, c5, c6, c7, c8, c9)) { columns in
            appendTableColumns(c0, to: &columns)
            appendTableColumns(c1, to: &columns)
            appendTableColumns(c2, to: &columns)
            appendTableColumns(c3, to: &columns)
            appendTableColumns(c4, to: &columns)
            appendTableColumns(c5, to: &columns)
            appendTableColumns(c6, to: &columns)
            appendTableColumns(c7, to: &columns)
            appendTableColumns(c8, to: &columns)
            appendTableColumns(c9, to: &columns)
        }
    }
}

// swiftlint:enable function_parameter_count large_tuple
