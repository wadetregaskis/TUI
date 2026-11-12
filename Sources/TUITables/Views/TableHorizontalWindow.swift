//  🖥️ TUI — A Terminal UI framework for Swift
//  TableHorizontalWindow.swift
//
//  The columns a table draws when they do not all fit: the arithmetic of
//  scrolling a table sideways a whole column at a time.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The window

/// Which of a table's columns are drawn when their minimum widths do not fit
/// beside one another, and how wide (decisions TABLE-HSCROLL).
///
/// SwiftUI's table on macOS scrolls sideways once its columns' minimum widths
/// exceed its own, by points. A terminal's table scrolls by whole columns: the
/// window starts at the first cell of one of them, and runs on until the width
/// is spent, the column it runs out in cut short (its cells end in `…`, which
/// says there is more). Cut through the middle at the leading edge, a cell
/// reads as another value — `12,345` as `345` — and a cell is too coarse to
/// show a sliver of a glyph, as a scrolled-off point does.
///
/// Every width here is in cells, and every position is counted from the first
/// column's first cell — the scrolling band begins after the selection gutter,
/// which stays where it is.
struct TableHorizontalWindow: Equatable {
    /// The index, among the table's columns, of the first column drawn.
    let first: Int

    /// The widths of the columns drawn, from ``first``: their own, but for
    /// the last, which is cut to what is left of the window when it does not
    /// fit whole.
    let widths: [Int]

    /// Where each column the window may start at begins (``stops(of:spacing:viewport:)``).
    let stops: [Int]

    /// Every column's width as the window lays them out, its own or not: what
    /// the header publishes the columns off screen at, for a drag to lay them
    /// out from.
    let minimums: [Int]

    /// The width the scrollbar measures the columns as: theirs, and the blank
    /// past the last one that a window starting at the last stop shows.
    let extent: Int

    /// The width of the window: the columns' width less the gutter.
    let viewport: Int

    /// Whether the table draws its vertical scrollbar beside this window —
    /// decided where the window was, so the rows and the window agree on the
    /// width the columns have.
    let showsVerticalBar: Bool

    /// The lines the horizontal scrollbar takes under the rows: one, or none
    /// where the indicators are hidden or there is no line to spare.
    let barLines: Int

    /// Where the window starts, in cells.
    var offset: Int { stops[min(first, stops.count - 1)] }

    // MARK: Arithmetic

    /// Whether `widths`, spaced by `spacing` after a `gutter`, are wider than
    /// `columnsWidth`.
    static func overflows(_ widths: [Int], spacing: Int, gutter: Int, columnsWidth: Int) -> Bool {
        let total: Int = gutter + widths.reduce(0, +) + spacing * max(0, widths.count - 1)
        return total > columnsWidth
    }

    /// Where each column a window `viewport` cells wide may start at begins,
    /// and the scrollbar's extent: every column's start up to the first from
    /// which the rest fit — a window never starts further along than it must
    /// to show the last column, so the last screen is as full as it can be.
    static func stops(of widths: [Int], spacing: Int, viewport: Int) -> (stops: [Int], extent: Int) {
        guard !widths.isEmpty else { return ([0], viewport) }
        let total: Int = widths.reduce(0, +) + spacing * (widths.count - 1)
        var stops: [Int] = []
        var start = 0
        for width in widths {
            stops.append(start)
            if total - start <= viewport { break }
            start += width + spacing
        }
        let last = stops[stops.count - 1]
        return (stops, max(total, last + viewport))
    }

    /// The stop to draw from, given the position asked for (`requested`, in
    /// cells), the stop last drawn from, and whether the scrollbar's thumb is
    /// being dragged — as an index into `stops`.
    ///
    /// The scrollbar moves the position in cells. A drag of its thumb lands on
    /// the nearest stop. A step lands on the next stop the way it went — an
    /// arrow's one cell would otherwise round back to where it started — and
    /// a page on the stop of the column the position fell in, so the column
    /// cut short at the window's edge is the next page's first.
    static func snappedStart(requested: Int, drawn: Int, dragging: Bool, stops: [Int]) -> Int {
        guard stops.count > 1 else { return 0 }
        let last = stops.count - 1
        let atOrBefore = stops.lastIndex { $0 <= requested } ?? 0
        if dragging {
            let after = min(last, atOrBefore + 1)
            return requested - stops[atOrBefore] <= stops[after] - requested ? atOrBefore : after
        }
        let drawnIndex = stops.lastIndex { $0 <= drawn } ?? 0
        if requested > drawn {
            return min(last, atOrBefore > drawnIndex ? atOrBefore : drawnIndex + 1)
        }
        if requested < drawn {
            let atOrAfter = stops.firstIndex { $0 >= requested } ?? last
            return max(0, atOrAfter < drawnIndex ? atOrAfter : drawnIndex - 1)
        }
        return min(last, drawnIndex)
    }

    /// The start, as an index into `stops`, nearest `start` from which column
    /// `column` is drawn whole — or from its own first cell, when it is wider
    /// than the window.
    static func revealing(
        column: Int, from start: Int, widths: [Int], spacing: Int, viewport: Int, stops: [Int]
    ) -> Int {
        guard widths.indices.contains(column) else { return start }
        if column <= start { return min(column, stops.count - 1) }
        let columnStart: Int = widths[..<column].reduce(0, +) + spacing * column
        let columnEnd = columnStart + widths[column]
        var first = start
        while first < min(column, stops.count - 1), columnEnd - stops[first] > viewport { first += 1 }
        return first
    }

    /// The widths of the columns a window `viewport` cells wide shows from
    /// column `first`: whole while they fit, and the one the window runs out
    /// in cut to what is left of it. Where that is not one cell, or the last
    /// column fits with room to spare, the last column shown takes what is
    /// left, as SwiftUI's last column takes the room past the others: the
    /// window is always filled, so the table is as wide on every column.
    static func shownWidths(from first: Int, of widths: [Int], spacing: Int, viewport: Int) -> [Int] {
        var shown: [Int] = []
        var left = viewport
        for index in first..<widths.count {
            let gap = shown.isEmpty ? 0 : spacing
            if gap + widths[index] <= left {
                shown.append(widths[index])
                left -= gap + widths[index]
                continue
            }
            if left - gap >= 1 {
                shown.append(left - gap)
                left = 0
            }
            break
        }
        guard !shown.isEmpty else { return [max(1, viewport)] }
        shown[shown.count - 1] += left
        return shown
    }
}
