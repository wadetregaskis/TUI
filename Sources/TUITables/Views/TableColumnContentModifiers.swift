//  🖥️ TUI — A Terminal UI framework for Swift
//  TableColumnContentModifiers.swift
//
//  The modifiers every kind of column content takes — one column, a group, a
//  column loop — and the content they produce.
//
//  Created by Wade Tregaskis
//  License: MIT

// `SortComparator` is Foundation's.
import Foundation
import TUIFoundation

// MARK: - Modified columns

/// Column content whose every column has had something said about it.
///
/// A column modifier applies to all the columns of the content it modifies,
/// and the one nearest a column wins: `Group { a.alignment(.center); b }
/// .alignment(.trailing)` centres `a` and right-aligns `b`. So each modifier
/// states an attribute only where nothing inside has stated it already.
nonisolated struct _ModifiedTableColumnContent<Base: TableColumnContent>: TableColumnContent {
    typealias TableRowValue = Base.TableRowValue
    typealias TableColumnSortComparator = Base.TableColumnSortComparator
    typealias TableColumnBody = Never

    /// The content modified.
    let base: Base

    /// States the attribute on one of the content's columns.
    let modify: (inout _TableColumnSpec<Base.TableRowValue>) -> Void

    /// Never called: modified content hands its columns to the table directly.
    @MainActor var tableColumnBody: Never { fatalError("_ModifiedTableColumnContent renders its columns directly") }
}

@MainActor extension _ModifiedTableColumnContent {
    static func _appendColumns(_ content: Self, to columns: inout _TableColumnList<Base.TableRowValue>) {
        let start = columns.specs.endIndex
        appendTableColumns(content.base, to: &columns)
        for index in start..<columns.specs.endIndex {
            content.modify(&columns.specs[index])
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

// MARK: - Customization

extension TableColumnContent {
    /// Sets the identifier to be associated with a column when persisting its
    /// state with ``TableColumnCustomization``.
    ///
    /// This is required to allow user customization of a specific table
    /// column, in addition to the table as a whole being provided a binding to
    /// a `TableColumnCustomization`. The identifier needs to be stable,
    /// including across app version updates, since it is used to persist the
    /// customization.
    ///
    /// - Parameter id: The identifier to associate with a column.
    public func customizationID(
        _ id: String
    ) -> some TableColumnContent<TableRowValue, TableColumnSortComparator> {
        _ModifiedTableColumnContent(base: self) { column in
            if column.customizationID == nil { column.customizationID = id }
        }
    }

    /// Sets the default visibility of a table column.
    ///
    /// A `.hidden` column is not shown unless the table is also bound to a
    /// ``TableColumnCustomization`` that makes it visible — measured in
    /// SwiftUI, it is hidden whether or not the table has such a binding.
    ///
    /// - Parameter visibility: The default visibility to apply to columns.
    public func defaultVisibility(
        _ visibility: Visibility
    ) -> some TableColumnContent<TableRowValue, TableColumnSortComparator> {
        _ModifiedTableColumnContent(base: self) { column in
            if column.defaultVisibility == nil { column.defaultVisibility = visibility }
        }
    }

    /// Sets the disabled customization behavior for a table column.
    ///
    /// A table lets the user resize its columns — dragging the gap after a
    /// header, Ctrl-K's `-` and `+` — bound to a ``TableColumnCustomization``
    /// or not, and a table bound to one lets them reorder and hide the columns
    /// with an identifier too — dragging a header, the header's menu, Ctrl-K's
    /// `<` and `>`. This takes away the behaviors given: `.reorder` stops the
    /// column moving and other columns moving past it by a drag over it,
    /// `.resize` leaves it no gap to drag and no `-`/`+`, bound or not, and
    /// `.visibility` disables its row in the column menu. It never stops the
    /// app changing a customization itself, in SwiftUI or here.
    ///
    /// - Parameter behavior: The behavior to disable, or `.all` to not allow
    ///   any customization.
    public func disabledCustomizationBehavior(
        _ behavior: TableColumnCustomizationBehavior
    ) -> some TableColumnContent<TableRowValue, TableColumnSortComparator> {
        _ModifiedTableColumnContent(base: self) { column in
            if column.disabledCustomizationBehavior == nil {
                column.disabledCustomizationBehavior = behavior
            }
        }
    }
}
