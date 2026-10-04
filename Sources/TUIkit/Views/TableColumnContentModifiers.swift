//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableColumnContentModifiers.swift
//
//  The modifiers every kind of column content takes — one column, a group, a
//  column loop — and the content they produce.
//
//  Created by Wade Tregaskis
//  License: MIT

// `SortComparator` is Foundation's.
import Foundation

// MARK: - Modified columns

/// Column content whose every column has had something said about it.
///
/// A column modifier applies to all the columns of the content it modifies,
/// and the one nearest a column wins: `Group { a.alignment(.center); b }
/// .alignment(.trailing)` centres `a` and right-aligns `b`. So each modifier
/// states an attribute only where nothing inside has stated it already.
struct _ModifiedTableColumnContent<Base: TableColumnContent>: TableColumnContent {
    typealias TableRowValue = Base.TableRowValue
    typealias TableColumnSortComparator = Base.TableColumnSortComparator
    typealias TableColumnBody = Never

    /// The content modified.
    let base: Base

    /// States the attribute on one of the content's columns.
    let modify: (inout _TableColumnSpec<Base.TableRowValue>) -> Void

    /// Never called: modified content hands its columns to the table directly.
    var tableColumnBody: Never { fatalError("_ModifiedTableColumnContent renders its columns directly") }
}

extension _ModifiedTableColumnContent: _TableColumnPrimitive {
    typealias ColumnRow = Base.TableRowValue

    func appendColumns(to columns: inout [_TableColumnSpec<Base.TableRowValue>]) {
        let start = columns.endIndex
        appendTableColumns(base, to: &columns)
        for index in start..<columns.endIndex {
            modify(&columns[index])
        }
    }
}

// MARK: - Alignment

extension TableColumnContent {
    /// Sets the alignment of the column, applying to both its column header
    /// label and the row view content for that column.
    ///
    /// Applied to several columns — a `Group`, a ``TableColumnForEach`` — it
    /// aligns each of them that does not say otherwise itself.
    ///
    /// - Parameter alignment: The alignment to apply to the column.
    public func alignment(
        _ alignment: TableColumnAlignment
    ) -> some TableColumnContent<TableRowValue, TableColumnSortComparator> {
        _ModifiedTableColumnContent(base: self) { column in
            guard !column.alignmentIsStated else { return }
            column.alignment = alignment.horizontal
            column.alignmentIsStated = true
        }
    }
}
