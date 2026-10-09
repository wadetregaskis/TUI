//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableRowBuilder+Blocks.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// SwiftUI's builder spells out every arity to ten, and each arity's result
// carries a tuple of that many row types — so the longest signatures here
// have ten parameters and a ten-member tuple by design.
// swiftlint:disable function_parameter_count large_tuple

// MARK: - Blocks of two to ten rows

extension TableRowBuilder {
    /// Creates a row result from two sources.
    public static func buildBlock<
        C0: TableRowContent, C1: TableRowContent
    >(
        _ c0: C0, _ c1: C1
    ) -> TupleTableRowContent<Value, (C0, C1)>
    where
        Value == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue
    {
        TupleTableRowContent((c0, c1)) { rows in
            appendTableRows(c0, to: &rows)
            appendTableRows(c1, to: &rows)
        }
    }

    /// Creates a row result from three sources.
    public static func buildBlock<
        C0: TableRowContent, C1: TableRowContent, C2: TableRowContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2
    ) -> TupleTableRowContent<Value, (C0, C1, C2)>
    where
        Value == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue,
        C2.TableRowValue == C0.TableRowValue
    {
        TupleTableRowContent((c0, c1, c2)) { rows in
            appendTableRows(c0, to: &rows)
            appendTableRows(c1, to: &rows)
            appendTableRows(c2, to: &rows)
        }
    }

    /// Creates a row result from four sources.
    public static func buildBlock<
        C0: TableRowContent, C1: TableRowContent, C2: TableRowContent,
        C3: TableRowContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3
    ) -> TupleTableRowContent<Value, (C0, C1, C2, C3)>
    where
        Value == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue,
        C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue
    {
        TupleTableRowContent((c0, c1, c2, c3)) { rows in
            appendTableRows(c0, to: &rows)
            appendTableRows(c1, to: &rows)
            appendTableRows(c2, to: &rows)
            appendTableRows(c3, to: &rows)
        }
    }

    /// Creates a row result from five sources.
    public static func buildBlock<
        C0: TableRowContent, C1: TableRowContent, C2: TableRowContent,
        C3: TableRowContent, C4: TableRowContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4
    ) -> TupleTableRowContent<Value, (C0, C1, C2, C3, C4)>
    where
        Value == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue,
        C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue,
        C4.TableRowValue == C0.TableRowValue
    {
        TupleTableRowContent((c0, c1, c2, c3, c4)) { rows in
            appendTableRows(c0, to: &rows)
            appendTableRows(c1, to: &rows)
            appendTableRows(c2, to: &rows)
            appendTableRows(c3, to: &rows)
            appendTableRows(c4, to: &rows)
        }
    }

    /// Creates a row result from six sources.
    public static func buildBlock<
        C0: TableRowContent, C1: TableRowContent, C2: TableRowContent,
        C3: TableRowContent, C4: TableRowContent, C5: TableRowContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4,
        _ c5: C5
    ) -> TupleTableRowContent<Value, (C0, C1, C2, C3, C4, C5)>
    where
        Value == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue,
        C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue,
        C4.TableRowValue == C0.TableRowValue, C5.TableRowValue == C0.TableRowValue
    {
        TupleTableRowContent((c0, c1, c2, c3, c4, c5)) { rows in
            appendTableRows(c0, to: &rows)
            appendTableRows(c1, to: &rows)
            appendTableRows(c2, to: &rows)
            appendTableRows(c3, to: &rows)
            appendTableRows(c4, to: &rows)
            appendTableRows(c5, to: &rows)
        }
    }

    /// Creates a row result from seven sources.
    public static func buildBlock<
        C0: TableRowContent, C1: TableRowContent, C2: TableRowContent,
        C3: TableRowContent, C4: TableRowContent, C5: TableRowContent,
        C6: TableRowContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4,
        _ c5: C5, _ c6: C6
    ) -> TupleTableRowContent<Value, (C0, C1, C2, C3, C4, C5, C6)>
    where
        Value == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue,
        C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue,
        C4.TableRowValue == C0.TableRowValue, C5.TableRowValue == C0.TableRowValue,
        C6.TableRowValue == C0.TableRowValue
    {
        TupleTableRowContent((c0, c1, c2, c3, c4, c5, c6)) { rows in
            appendTableRows(c0, to: &rows)
            appendTableRows(c1, to: &rows)
            appendTableRows(c2, to: &rows)
            appendTableRows(c3, to: &rows)
            appendTableRows(c4, to: &rows)
            appendTableRows(c5, to: &rows)
            appendTableRows(c6, to: &rows)
        }
    }

    /// Creates a row result from eight sources.
    public static func buildBlock<
        C0: TableRowContent, C1: TableRowContent, C2: TableRowContent,
        C3: TableRowContent, C4: TableRowContent, C5: TableRowContent,
        C6: TableRowContent, C7: TableRowContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4,
        _ c5: C5, _ c6: C6, _ c7: C7
    ) -> TupleTableRowContent<Value, (C0, C1, C2, C3, C4, C5, C6, C7)>
    where
        Value == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue,
        C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue,
        C4.TableRowValue == C0.TableRowValue, C5.TableRowValue == C0.TableRowValue,
        C6.TableRowValue == C0.TableRowValue, C7.TableRowValue == C0.TableRowValue
    {
        TupleTableRowContent((c0, c1, c2, c3, c4, c5, c6, c7)) { rows in
            appendTableRows(c0, to: &rows)
            appendTableRows(c1, to: &rows)
            appendTableRows(c2, to: &rows)
            appendTableRows(c3, to: &rows)
            appendTableRows(c4, to: &rows)
            appendTableRows(c5, to: &rows)
            appendTableRows(c6, to: &rows)
            appendTableRows(c7, to: &rows)
        }
    }

    /// Creates a row result from nine sources.
    public static func buildBlock<
        C0: TableRowContent, C1: TableRowContent, C2: TableRowContent,
        C3: TableRowContent, C4: TableRowContent, C5: TableRowContent,
        C6: TableRowContent, C7: TableRowContent, C8: TableRowContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4,
        _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8
    ) -> TupleTableRowContent<Value, (C0, C1, C2, C3, C4, C5, C6, C7, C8)>
    where
        Value == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue,
        C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue,
        C4.TableRowValue == C0.TableRowValue, C5.TableRowValue == C0.TableRowValue,
        C6.TableRowValue == C0.TableRowValue, C7.TableRowValue == C0.TableRowValue,
        C8.TableRowValue == C0.TableRowValue
    {
        TupleTableRowContent((c0, c1, c2, c3, c4, c5, c6, c7, c8)) { rows in
            appendTableRows(c0, to: &rows)
            appendTableRows(c1, to: &rows)
            appendTableRows(c2, to: &rows)
            appendTableRows(c3, to: &rows)
            appendTableRows(c4, to: &rows)
            appendTableRows(c5, to: &rows)
            appendTableRows(c6, to: &rows)
            appendTableRows(c7, to: &rows)
            appendTableRows(c8, to: &rows)
        }
    }

    /// Creates a row result from ten sources.
    public static func buildBlock<
        C0: TableRowContent, C1: TableRowContent, C2: TableRowContent,
        C3: TableRowContent, C4: TableRowContent, C5: TableRowContent,
        C6: TableRowContent, C7: TableRowContent, C8: TableRowContent,
        C9: TableRowContent
    >(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4,
        _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9
    ) -> TupleTableRowContent<Value, (C0, C1, C2, C3, C4, C5, C6, C7, C8, C9)>
    where
        Value == C0.TableRowValue, C1.TableRowValue == C0.TableRowValue,
        C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue,
        C4.TableRowValue == C0.TableRowValue, C5.TableRowValue == C0.TableRowValue,
        C6.TableRowValue == C0.TableRowValue, C7.TableRowValue == C0.TableRowValue,
        C8.TableRowValue == C0.TableRowValue, C9.TableRowValue == C0.TableRowValue
    {
        TupleTableRowContent((c0, c1, c2, c3, c4, c5, c6, c7, c8, c9)) { rows in
            appendTableRows(c0, to: &rows)
            appendTableRows(c1, to: &rows)
            appendTableRows(c2, to: &rows)
            appendTableRows(c3, to: &rows)
            appendTableRows(c4, to: &rows)
            appendTableRows(c5, to: &rows)
            appendTableRows(c6, to: &rows)
            appendTableRows(c7, to: &rows)
            appendTableRows(c8, to: &rows)
            appendTableRows(c9, to: &rows)
        }
    }
}

// swiftlint:enable function_parameter_count large_tuple
