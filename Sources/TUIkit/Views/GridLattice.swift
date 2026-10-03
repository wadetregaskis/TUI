//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GridLattice.swift
//
//  The columns and rows a grid's cells decide, worked out once for the views
//  that lay cells out on a lattice.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Grid Lattice

/// A grid's column widths, row heights and per-column alignments, decided by
/// its cells.
///
/// Column widths come from the single-column cells alone. A spanning cell that
/// needs more than the columns it covers grows the LAST of them — the columns
/// it shares with single-column cells keep the width those cells asked for,
/// which is the property that makes a grid look like a grid. A row that spans
/// the whole grid (a child that is not in any row, such as a `Divider` between
/// rows) belongs to no column; it grows the last column only if the grid would
/// otherwise be narrower than it.
struct GridLattice {
    /// One cell, as the lattice needs it.
    struct Cell {
        /// How many columns the cell spans, at least 1.
        let span: Int
        /// The cell's size at an unspecified proposal.
        let size: ViewSize
        /// The column alignment the cell sets for its column, if any.
        let columnAlignment: HorizontalAlignment?
    }

    /// One row of cells.
    struct Row {
        let cells: [Cell]
        /// Whether this row is one child spanning every column.
        let spansFullWidth: Bool
    }

    /// Each column's width.
    private(set) var columns: [Int] = []

    /// Each row's height.
    private(set) var heights: [Int] = []

    /// The alignment a cell set for each column, by column index — the first
    /// cell the walk meets wins.
    private(set) var columnAlignment: [Int: HorizontalAlignment] = [:]

    /// The columns between cells.
    let horizontalSpacing: Int

    /// A grid's columns between cells when it states none: one, because a
    /// column gap of zero runs adjacent text together.
    static let defaultHorizontalSpacing = 1

    /// A grid's blank lines between rows when it states none: none, because
    /// rows are already separated by being different lines.
    static let defaultVerticalSpacing = 0

    /// The lattice `rows` decide, with `horizontalSpacing` columns between
    /// neighbouring cells.
    init(rows: [Row], horizontalSpacing: Int) {
        self.horizontalSpacing = horizontalSpacing

        // The widest child that spans the whole grid, which belongs to no
        // column — see Pass C.
        var fullWidthNeed = 0

        // Pass A: single-column cells set their column's width.
        for row in rows {
            var height = 0
            var index = 0
            for cell in row.cells {
                height = max(height, cell.size.height)
                widen(to: index + cell.span)
                // `span == 1` is not enough on its own. A child that is not in
                // a row arrives here as a one-cell row with span 1, and the
                // render draws it at `x: 0` across the FULL width — it is not
                // in column 0, so its width must not become column 0's. It
                // did, which pushed every other column right by the
                // difference: two short cells beside a sentence put the second
                // column a sentence-width away. Pass B already excludes these
                // rows; Pass A is where it was missed.
                if cell.span == 1 && !row.spansFullWidth {
                    columns[index] = max(columns[index], cell.size.width)
                    if let guide = cell.columnAlignment, columnAlignment[index] == nil {
                        columnAlignment[index] = guide
                    }
                }
                if row.spansFullWidth {
                    fullWidthNeed = max(fullWidthNeed, cell.size.width)
                }
                index += cell.span
            }
            heights.append(height)
        }

        // Pass B: spanning cells grow their last column if they still overflow.
        for row in rows where !row.spansFullWidth {
            var index = 0
            // Every cell, not just the spanning ones: a `where` on the loop
            // skips the whole body, `index += span` included, so a spanning
            // cell preceded by any ordinary one measured its width against the
            // wrong columns and grew the wrong column. The render loop advances
            // for every cell; this has to agree with it.
            for cell in row.cells {
                defer { index += cell.span }
                guard cell.span > 1 else { continue }
                let covered =
                    columns[index..<(index + cell.span)].reduce(0, +)
                    + (cell.span - 1) * horizontalSpacing
                if cell.size.width > covered {
                    columns[index + cell.span - 1] += cell.size.width - covered
                }
            }
        }

        // Pass C: a full-width child is a cell spanning every column, so it
        // grows the last one when it still does not fit — exactly what Pass B
        // does for an explicit `gridCellColumns` span. Excluding it from the
        // per-column vote must not shrink the grid: the render lays it out at
        // the grid's own width, and a grid narrower than its widest child would
        // clip the child instead of moving a column.
        if fullWidthNeed > 0 {
            widen(to: 1)
            let shortfall = fullWidthNeed - totalWidth
            if shortfall > 0 {
                columns[columns.count - 1] += shortfall
            }
        }
    }

    private mutating func widen(to count: Int) {
        while columns.count < count { columns.append(0) }
    }

    /// The grid's total width.
    var totalWidth: Int {
        columns.reduce(0, +) + max(0, columns.count - 1) * horizontalSpacing
    }

    /// Each column's x origin, accumulated rather than divided — the integer
    /// rule recorded on `Layout`.
    var columnOrigins: [Int] {
        var origins: [Int] = []
        origins.reserveCapacity(columns.count)
        var x = 0
        for column in columns {
            origins.append(x)
            x += column + horizontalSpacing
        }
        return origins
    }

    /// The width of a box spanning `span` columns from `column`, gaps
    /// included.
    func boxWidth(fromColumn column: Int, span: Int) -> Int {
        columns[column..<min(columns.count, column + span)].reduce(0, +)
            + (span - 1) * horizontalSpacing
    }

    /// The y each row starts at, in cells.
    ///
    /// Accumulated rather than multiplied, and clamped the same way the row
    /// canvases are — a zero-height row still occupies the one line a grid
    /// gives every row.
    func rowTops(spacing: Int) -> [Int] {
        var tops: [Int] = []
        tops.reserveCapacity(heights.count)
        var y = 0
        for (index, height) in heights.enumerated() {
            if index > 0 { y += spacing }
            tops.append(y)
            y += max(1, height)
        }
        return tops
    }

    /// The grid's total height: every row at least a line, and the gaps
    /// between them.
    func totalHeight(spacing: Int) -> Int {
        heights.reduce(0) { $0 + max(1, $1) } + max(0, heights.count - 1) * spacing
    }

    /// Where a cell of the given size sits inside its box.
    ///
    /// Precedence matches SwiftUI: the cell's own `gridCellAnchor` beats the
    /// column's `gridColumnAlignment`, which beats the row's alignment, which
    /// beats the grid's. Each axis floors exactly once — see ``AlignmentID``.
    /// Takes a size rather than a buffer, because a `.gradientExtent(.subtree)`
    /// ramp has to know where a cell will land BEFORE the cell renders — and
    /// the only size available then is the measured one.
    static func placement(
        width renderedWidth: Int,
        height renderedHeight: Int,
        in box: CellRect,
        anchor: UnitPoint?,
        rowAlignment: VerticalAlignment?,
        columnAlignment: HorizontalAlignment?,
        gridAlignment: Alignment
    ) -> (x: Int, y: Int) {
        if let anchor {
            let dx = Int((anchor.x * Double(box.width - renderedWidth)).rounded(.down))
            let dy = Int((anchor.y * Double(box.height - renderedHeight)).rounded(.down))
            return (
                x: box.x + min(max(0, dx), max(0, box.width - renderedWidth)),
                y: box.y + min(max(0, dy), max(0, box.height - renderedHeight))
            )
        }
        let horizontal = columnAlignment ?? gridAlignment.horizontal
        let vertical = rowAlignment ?? gridAlignment.vertical
        return (
            x: box.x + horizontal.childOffset(childWidth: renderedWidth, in: box.width),
            y: box.y + vertical.childOffset(childHeight: renderedHeight, in: box.height)
        )
    }
}
