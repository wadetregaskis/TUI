//  🖥️ TUI — A Terminal UI framework for Swift
//  GridLattice.swift
//
//  The columns and rows a grid's cells decide, worked out once for the views
//  that lay cells out on a lattice.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

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
///
/// Those are the columns' own widths. Offered another width, the columns share
/// it as a row's children do (``fit(toWidth:grows:rows:minimum:measure:)``).
struct GridLattice {
    /// One cell, as the lattice needs it.
    struct Cell {
        /// How many columns the cell spans, at least 1.
        let span: Int
        /// The cell's size at an unspecified proposal.
        let size: ViewSize
        /// The column alignment the cell sets for its column, if any.
        let columnAlignment: HorizontalAlignment?
        /// The axes on which the cell does not size its column or row.
        let unsizedAxes: Axis.Set

        /// The width the cell asks its columns for: none, when it is unsized
        /// horizontally.
        var sizingWidth: Int { unsizedAxes.contains(.horizontal) ? 0 : size.width }

        /// The height the cell asks its row for: none, when it is unsized
        /// vertically.
        var sizingHeight: Int { unsizedAxes.contains(.vertical) ? 0 : size.height }
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
                height = max(height, cell.sizingHeight)
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
                    columns[index] = max(columns[index], cell.sizingWidth)
                    if let guide = cell.columnAlignment, columnAlignment[index] == nil {
                        columnAlignment[index] = guide
                    }
                }
                if row.spansFullWidth {
                    fullWidthNeed = max(fullWidthNeed, cell.sizingWidth)
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
                if cell.sizingWidth > covered {
                    columns[index + cell.span - 1] += cell.sizingWidth - covered
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
        let total: Int = columns.reduce(0, +)
        return total + max(0, columns.count - 1) * horizontalSpacing
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

// MARK: - Fitting a Width

extension GridLattice {
    /// Where a cell is in the rows the lattice was built from: its row, and
    /// its place among that row's cells.
    struct CellIndex {
        let row: Int
        let cell: Int
    }

    /// Shares `width` among the columns, as an `HStack` shares a row among its
    /// children, and finds each row's height at the widths its cells get.
    ///
    /// Measured (`Tools/SwiftUIProbes/Grid narrower than its columns/grid.out`):
    /// SwiftUI's `Grid` asks each cell its width offered nothing and offered
    /// everything, and deals the columns the width left, the least flexible
    /// first, each offered an equal share of what is left; a column takes its
    /// widest cell's answer. So no column is dropped: a column of text wraps (or
    /// truncates, under `lineLimit(1)`) and the grid grows taller, a rigid
    /// column keeps its width, and a column that fills takes what the others
    /// leave. That is ``distributeLinearSpace(naturalSizes:isFlexible:available:spacing:shares:isSpacer:priorities:minimumSize:statedMinimum:sizeAt:)``,
    /// a row's own deal, with the columns for its children.
    ///
    /// Where even the columns' minimums do not fit — a rigid column wider than
    /// the grid — SwiftUI's grid is wider than its offer; this one places the
    /// columns in order until the width runs out, as TUI's stacks do.
    ///
    /// Nothing is measured, and nothing changes, when every column fits whole
    /// and none fills: the case of nearly every grid.
    ///
    /// - Parameters:
    ///   - width: The width to fill.
    ///   - grows: Whether a filling column grows into a width wider than the
    ///     columns; not where the grid is asked its own width.
    ///   - rows: The rows the lattice was built from.
    ///   - minimum: A cell's width when offered none, a minimum it states
    ///     included.
    ///   - measure: A cell's size when offered a proposal.
    mutating func fit(
        toWidth width: Int, grows: Bool = true, rows: [Row], minimum: (CellIndex) -> Int,
        measure: (CellIndex, ProposedViewSize) -> ViewSize
    ) {
        // The cells that decide each column's width: the ones Pass A counts.
        var members = [[CellIndex]](repeating: [], count: columns.count)
        var fills = [Bool](repeating: false, count: columns.count)
        for (rowIndex, row) in rows.enumerated() where !row.spansFullWidth {
            var column = 0
            for (cellIndex, cell) in row.cells.enumerated() {
                defer { column += cell.span }
                guard cell.span == 1, !cell.unsizedAxes.contains(.horizontal), column < columns.count else { continue }
                members[column].append(CellIndex(row: rowIndex, cell: cellIndex))
                if cell.size.isWidthFlexible { fills[column] = true }
            }
        }
        let total = totalWidth
        guard width < total || (grows && width > total && fills.contains(true)) else { return }

        func widest(_ column: Int, _ answer: (CellIndex) -> Int) -> Int? {
            members[column].map(answer).max()
        }
        columns = distributeLinearSpace(
            naturalSizes: columns, isFlexible: fills, available: max(0, width), spacing: horizontalSpacing,
            minimumSize: { widest($0, minimum) ?? 0 },
            statedMinimum: { column in widest(column) { fills[column] ? minimum($0) : 0 } ?? 0 },
            sizeAt: { column, offer in widest(column) { measure($0, ProposedViewSize(width: offer, height: nil)).width } })

        // A cell given less than it asked for wraps into more lines; one given
        // as much keeps the height it had.
        for (rowIndex, row) in rows.enumerated() {
            var height = 0
            var column = 0
            for (cellIndex, cell) in row.cells.enumerated() {
                defer { column += cell.span }
                let box = row.spansFullWidth ? totalWidth : boxWidth(fromColumn: column, span: cell.span)
                guard !cell.unsizedAxes.contains(.vertical) else { continue }
                let size =
                    box < cell.size.width
                    ? measure(CellIndex(row: rowIndex, cell: cellIndex), ProposedViewSize(width: max(0, box), height: nil))
                    : cell.size
                height = max(height, size.height)
            }
            heights[rowIndex] = height
        }
    }
}
