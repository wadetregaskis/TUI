//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GridRowGroup.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitView

extension ChildView {
    /// The mark this child carries as a flattened grid row's cell, read
    /// through any modifiers written on the row — they wrap each cell outside
    /// its mark — or `nil` for a child that is not one.
    var gridRowMark: GridRowMark? {
        throughWrappers(wrappedView, as: (any GridRowMarking).self)?.gridRowMark
    }
}

// MARK: - Grouping Children into Rows

/// One row of a grid, grouped from its container's children.
struct GridRowGroup<Cell> {
    /// The row's cells, in order.
    var cells: [Cell]

    /// The row's vertical alignment override, if it set one.
    var alignment: VerticalAlignment?

    /// Whether this row is one child that is in no row and spans every column.
    var spansFullWidth: Bool
}

/// `children` grouped into grid rows by their marks — what `Grid` and
/// `GridLayout` both lay out, so the two cannot group differently.
///
/// A marked child that starts a row starts one, and the marked children after
/// it join it. An unmarked child is offered to `wholeRow`, for a row that
/// arrived whole; anything else is one child spanning every column, which is
/// how a `Divider` between rows works.
@MainActor
func groupGridRows<Cell>(
    _ children: [Cell], mark: (Cell) -> GridRowMark?,
    wholeRow: (Cell) -> (cells: [Cell], alignment: VerticalAlignment?)?
) -> [GridRowGroup<Cell>] {
    var rows: [GridRowGroup<Cell>] = []
    var open: GridRowGroup<Cell>?
    for child in children {
        if let mark = mark(child) {
            if mark.startsRow || open == nil {
                if let row = open { rows.append(row) }
                open = GridRowGroup(cells: [child], alignment: mark.alignment, spansFullWidth: false)
            } else {
                open?.cells.append(child)
            }
            continue
        }
        if let row = open {
            rows.append(row)
            open = nil
        }
        if let whole = wholeRow(child) {
            rows.append(GridRowGroup(cells: whole.cells, alignment: whole.alignment, spansFullWidth: false))
        } else {
            rows.append(GridRowGroup(cells: [child], alignment: nil, spansFullWidth: true))
        }
    }
    if let row = open { rows.append(row) }
    return rows
}
