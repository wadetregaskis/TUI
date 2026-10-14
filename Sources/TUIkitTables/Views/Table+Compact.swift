//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Table+Compact.swift
//
//  A table in a horizontally compact size class shows its first column alone,
//  without headers, as SwiftUI's does on iPhone (decisions B3): "the table
//  automatically hides headers and all columns after the first".
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

extension Table {
    /// The columns the table shows: those its customization shows — an empty
    /// customization still hides the columns whose default visibility is
    /// `.hidden`, as SwiftUI's table does with no binding at all — and where
    /// `compact`, only the first of them.
    ///
    /// The first column then takes the table's whole width, whatever width it
    /// was given: on iPhone the table is a list of its first column, and a
    /// column left at the width it had beside the others would leave the rest
    /// of every row empty.
    func shownColumns(compact: Bool) -> [_TableColumnSpec<Value>] {
        let shown = (columnCustomization?.wrappedValue ?? TableColumnCustomization()).shownColumns(columns)
        guard compact, var first = shown.first else { return shown }
        first.width = .flexible
        first.resizedWidth = nil
        return [first]
    }
}
