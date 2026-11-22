//  🖥️ TUI — A Terminal UI framework for Swift
//  PulledRowBand.swift
//
//  SCROLL-FIT's pull (design P4), for a view outside this module whose rows
//  vary in height — a `List` of rows of several lines or in sections, a
//  `Table` of multi-line rows, a wrapping `TextEditor`'s paragraphs — and so
//  cannot place a line by arithmetic as `PulledBand.swift`'s fixed pitch
//  does. Its rows are walked by the fill engine (`ScrollColumnFill.swift`):
//  the view keeps an anchor (a row and the lines of it above the viewport's
//  top), walks the request's delta from it in row space, measuring only the
//  rows it crosses, and fills the viewport outward from it. A row never
//  built is priced at the running pitch of those measured, which only the
//  readings use — the view's total, the scrollbar, "N more" — never what is
//  drawn (B-SCROLLFIT-3, B-SCROLLFIT-16).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// What a pulled view of rows of varying height keeps between frames: the
/// anchor its walk moves, the pitches it has measured (the running estimate),
/// and the rows it drew last (the ladder an anchor whose row left the data
/// falls on). Kept in the view's `StateStorage`, one per view.
@MainActor
package final class PulledRows {
    /// The row the viewport's top lies in, the lines of it above the top,
    /// and the dead reckoning that keeps the request's position in step —
    /// in the coordinates of the rows alone (the view's chrome above them
    /// not counted).
    let anchor = ScrollContentAnchor()

    /// The pitches measured, by row, for the running estimate: a bounded
    /// sample, taken afresh when the rows' width or count changes.
    private var sample = RowPitchSample()
    private var sampledShape: (width: Int, count: Int)?

    /// The rows drawn last frame, by key (§5f's ladder).
    fileprivate(set) var ladder: [String: Int] = [:]

    package init() {}

    /// The pitch a row never measured is priced at: the mean of those
    /// measured, rounded, at least a line.
    package var estimatedPitch: Int { sample.roundedPitch ?? 1 }

    /// Whether any pitch has been measured since the rows last changed shape.
    package var hasSamples: Bool { !sample.isEmpty }

    /// The rows' height last reported — exact once the band held the last
    /// row, else the estimate — or `nil` before the first band.
    package var reportedRowsHeight: Int? { anchor.reportedTotal }

    /// Starts the estimate afresh when the rows' width or count changed: a
    /// row's pitch is its lines at a width, and a row at an index is another
    /// row once rows come and go.
    package func noteShape(width: Int, count: Int) {
        guard sampledShape.map({ $0 != (width, count) }) ?? true else { return }
        if sampledShape != nil {
            sample.removeAll()
            anchor.reportedTotal = nil
        }
        sampledShape = (width, count)
    }

    /// Records row `row`'s measured pitch.
    package func note(pitch: Int, of row: Int) {
        sample.note(pitch, of: row)
    }

    /// The rows' height for a measure: what the last band reported, else
    /// `count` rows at the estimated pitch.
    package func estimatedRowsHeight(count: Int) -> Int {
        anchor.reportedTotal ?? Int.lines(ofRows: count, pitch: estimatedPitch)
    }
}

/// The rows of a pulled view as the fill engine walks them, for one frame:
/// each row's pitch measured once, when the walk first reaches it.
@MainActor
private final class PulledRowColumn: ScrollFillColumn {
    let rowCount: Int
    let rows: PulledRows
    private let measure: (Int) -> Int
    private let keyAt: (Int) -> String?
    private let ordinalFor: (String) -> Int?
    private var pitches: [Int: Int] = [:]

    init(
        rows: PulledRows, count: Int, pitch: @escaping (Int) -> Int, key: @escaping (Int) -> String?,
        ordinal: @escaping (String) -> Int?
    ) {
        self.rows = rows
        rowCount = count
        measure = pitch
        keyAt = key
        ordinalFor = ordinal
    }

    func pitch(of ordinal: Int) -> Int {
        if let known = pitches[ordinal] { return known }
        let pitch = max(1, measure(ordinal))
        pitches[ordinal] = pitch
        rows.note(pitch: pitch, of: ordinal)
        return pitch
    }

    func key(at ordinal: Int) -> String? { keyAt(ordinal) }
    func firstOrdinal(forKey key: String) -> Int? { ordinalFor(key) }
    var ladder: [String: Int] { rows.ladder }
    var estimatedPitch: Int { rows.estimatedPitch }
    var anchor: ScrollContentAnchor { rows.anchor }

    /// Row `target`'s top, in viewport lines, read from the row at
    /// `from` whose top is at `fromTop`: walked by exact pitches where it is
    /// near — within `reach` lines — and priced at the estimate past that.
    func top(of target: Int, from: Int, fromTop: Int, reach: Int) -> Int {
        // Every row is a line at least, so a row more than `reach` rows off
        // is more than `reach` lines off: priced without walking to it.
        if abs(target - from) > reach { return fromTop.saturatingAdding(Int.lines(ofRows: target - from, pitch: estimatedPitch)) }
        var row = from
        var y = fromTop
        while row < target {
            if y - fromTop > reach { return y.saturatingAdding(Int.lines(ofRows: target - row, pitch: estimatedPitch)) }
            y += pitch(of: row)
            row += 1
        }
        while row > target {
            if fromTop - y > reach { return y.saturatingSubtracting(Int.lines(ofRows: row - target, pitch: estimatedPitch)) }
            row -= 1
            y -= pitch(of: row)
        }
        return y
    }
}

/// The rows a pulled view of rows of varying height draws this frame, and
/// the band of its lines they make
/// (``PulledBandRequest/band(of:count:top:bottom:pitch:key:ordinal:seekRow:)``).
///
/// The view draws itself framed to ``frameHeight(top:bottom:)`` lines — its
/// chrome above, its rows from ``firstRow`` with ``clip`` lines of it hidden,
/// ``rowLines`` lines of them, its chrome below — and cuts the drawing to
/// ``drawnLines``.
@MainActor
package struct PulledRowsBand {
    /// The band, as the request is answered with it (``PulledBandRequest/answer(_:)``).
    package let band: PulledBand
    /// The first row drawn, and the lines of it above the drawing.
    package let firstRow: Int
    package let clip: Int
    /// The lines of rows drawn, from ``firstRow``'s ``clip``-th line.
    package let rowLines: Int
    /// The lines of the framed drawing that hold the band.
    package let drawnLines: Range<Int>
    /// The rows drawn, and where in the view's lines the first of them
    /// starts (its line 0, clipped or not): what a row's place off the band
    /// is read from (``line(ofRow:)``).
    fileprivate let rows: Range<Int>
    fileprivate let firstRowTop: Int
    fileprivate let column: PulledRowColumn
    /// The viewport's height, which the rows were filled down to.
    fileprivate let viewportHeight: Int

    /// How many rows the viewport shows, whole or in part, clear of the
    /// `pinned` lines over its top and bottom edges (a table's header and
    /// horizontal bar): what a page key steps the cursor by in a view whose
    /// rows vary in height, as a list drawn whole steps by the rows it shows
    /// (B-SCROLLFIT-5). A row only under the pinned lines is not shown, as a
    /// table of one-line rows pages by the viewport less them. Rows that start
    /// below the pinned top lines anyway — the view's top on screen — are
    /// counted as they are.
    package func rowsOnScreen(clearOf pinned: (top: Int, bottom: Int) = (0, 0)) -> Int {
        var top = firstRowTop - band.position
        var count = 0
        for row in rows {
            let height = column.pitch(of: row)
            if top + height > pinned.top, top < viewportHeight - pinned.bottom { count += 1 }
            top += height
        }
        return max(1, count)
    }

    /// The height of the framed drawing, given the view's chrome.
    package func frameHeight(top: Int, bottom: Int) -> Int { top + rowLines + bottom }

    /// Row `row`'s top in the view's lines, and its height: exact within a
    /// few screens of the rows drawn (measuring the rows between), priced at
    /// the running pitch past them — where a cursor row the band does not
    /// hold whole is marked
    /// (``FrameBuffer/markPulledControl(focusID:band:total:cursorLine:cursorHeight:)``),
    /// for the scroll view to reveal. Marked whole, a cursor moved to the last
    /// row puts its bottom at the viewport's, where the walk places the rows
    /// exactly from the last up.
    package func lines(ofRow row: Int, viewportHeight: Int) -> (top: Int, height: Int) {
        let reach = max(64, viewportHeight * 4)
        let top = column.top(of: row, from: rows.lowerBound, fromTop: firstRowTop, reach: reach)
        // A row near the rows drawn is measured; one far off them is priced.
        let near = row >= rows.lowerBound - 64 && row < rows.upperBound + 64
        let height = near ? column.pitch(of: row) : column.estimatedPitch
        let clamped = min(max(0, top), band.total - 1)
        return (clamped, max(1, min(height, band.total - clamped)))
    }
}

extension PulledBandRequest {
    /// The rows of varying height a pulled view draws for this request, and
    /// the band of its lines they make: `count` rows between `top` lines of
    /// chrome above and `bottom` below, row `n` `pitch(n)` lines (asked only
    /// of the rows the walk reaches, at most once a frame), keyed by
    /// `key` and found by key with `ordinal`; `seekRow` names the row a
    /// `scrollTo` key or a focus reveal names, `nil` for a key the view does
    /// not hold, and a seek places it with `seekChrome`'s lines above and
    /// below it — what the view pins over the viewport's edges while its rows
    /// are under them (a table's header and horizontal bar), which a row
    /// sought is kept clear of.
    ///
    /// The viewport's top is walked from the anchor `rows` keeps
    /// (``ScrollFillColumn/advanceAnchor(to:viewportHeight:linesBelow:)``): a
    /// request counted from the view's top or end places it afresh there
    /// (``ScrollFillColumn/enter(edgeOf:estimatedEnd:)``), one counted from
    /// the view's own position walks the delta. A seek makes its row the
    /// anchor, where the request's anchor says. The view's lines are the
    /// dead reckoning's: exact from the anchor outward; where the band holds
    /// the first row they are set so that the view's top is line 0, the
    /// position moving with them (reported, so the scroll view or the column
    /// moves its own), and where it holds the last, the total is exact.
    package func band(
        of rows: PulledRows, count: Int, top: Int, bottom: Int,
        pitch: @escaping (Int) -> Int, key: @escaping (Int) -> String?, ordinal: @escaping (String) -> Int?,
        seekRow: (ScrollToRequest) -> Int?, seekChrome: (above: Int, below: Int) = (0, 0)
    ) -> PulledRowsBand {
        let column = PulledRowColumn(rows: rows, count: count, pitch: pitch, key: key, ordinal: ordinal)
        let viewport = max(1, window.viewportHeight)
        let linesBelow = bottom + window.linesBelow
        // The request in the rows' own lines: from their top, or their end.
        var rowsWindow = window
        let edge = window.edge
        switch edge {
        case .position, .top: rowsWindow.offset = window.offset - top
        case .end: rowsWindow.offset = window.offset + bottom
        }
        column.enter(edgeOf: &rowsWindow)
        column.rebindAnchor(holdsRow: false)
        var resolvedSeek = false
        if let seek = window.seek, let target = seekRow(seek), target >= 0, target < count {
            if edge != .end {
                column.advanceAnchor(to: rowsWindow.offset, viewportHeight: viewport, linesBelow: linesBelow)
            }
            let anchor = rows.anchor
            let targetTop =
                rowsWindow.offset
                + column.top(
                    of: target, from: anchor.ordinal, fromTop: -anchor.within, reach: max(64, viewport * 4))
            let estimate = rows.estimatedPitch
            var placed = window
            placed.offset = rowsWindow.offset + top
            let position = placed.offset(
                realising: seek, targetY: targetTop + top - seekChrome.above,
                rowHeight: seekChrome.above + column.pitch(of: target) + seekChrome.below,
                stackHeight: top + bottom
                    + max(
                        rows.estimatedRowsHeight(count: count),
                        targetTop.saturatingAdding(Int.lines(ofRows: count - target, pitch: estimate))))
            anchor.ordinal = target
            anchor.within = position - top - targetTop
            anchor.derivedOffset = position - top
            rowsWindow.offset = position - top
            resolvedSeek = true
        } else if edge != .end {
            column.advanceAnchor(to: rowsWindow.offset, viewportHeight: viewport, linesBelow: linesBelow)
        }
        rows.anchor.key = key(rows.anchor.ordinal)
        return fill(column, rowsOffset: rowsWindow.offset, top: top, bottom: bottom, resolvedSeek: resolvedSeek)
    }

    /// Fills the viewport from the anchor and reads the band off the rows it
    /// reached (``band(of:count:top:bottom:pitch:key:ordinal:seekRow:)``).
    private func fill(
        _ column: PulledRowColumn, rowsOffset: Int, top: Int, bottom: Int, resolvedSeek: Bool
    ) -> PulledRowsBand {
        let rows = column.rows
        let count = column.rowCount
        let viewport = max(1, window.viewportHeight)
        let anchor = rows.anchor
        // From the anchor's row up to the viewport's top, in viewport lines.
        var first = min(max(0, anchor.ordinal), count - 1)
        var firstTop = -anchor.within
        while firstTop > 0, first > 0 {
            first -= 1
            firstTop -= column.pitch(of: first)
        }
        // Past rows wholly above the viewport, keeping the last: what the
        // content draws below it may fill the viewport.
        while first < count - 1, firstTop + column.pitch(of: first) <= 0 {
            firstTop += column.pitch(of: first)
            first += 1
        }
        // Down to the viewport's bottom; a row at least.
        var end = first
        var bottomY = firstTop
        repeat {
            bottomY += column.pitch(of: end)
            end += 1
        } while end < count && bottomY < viewport

        // The view's ends, where the rows reached them.
        let viewTop: Int? = first == 0 ? firstTop - top : nil
        let viewBottom: Int? = end == count ? bottomY + bottom : nil
        var low = max(viewTop ?? .min, 0)
        var high = min(viewBottom ?? .max, viewport)
        if low >= high {
            // The view lies off the viewport (a column draws it a line past,
            // or off its band for its place in the focus ring): its line
            // nearest the viewport.
            if let viewBottom, viewBottom <= 0 {
                (low, high) = (viewBottom - 1, viewBottom)
            } else if let viewTop, viewTop >= viewport {
                (low, high) = (viewTop, viewTop + 1)
            } else {
                (low, high) = (firstTop, firstTop + 1)
            }
        }

        // The position: the viewport's top in the view's lines. Held to the
        // dead reckoning, but for its ends: where the first row is drawn, the
        // view's top is line 0; and no row above the first drawn takes less
        // than a line.
        var position = rowsOffset + top
        if let viewTop {
            position = -viewTop
        } else {
            position = max(position, top + first - firstTop)
        }
        let corrected = position != rowsOffset + top
        anchor.derivedOffset = position - top
        let estimate = rows.estimatedPitch
        let total = position.saturatingAdding(
            viewBottom ?? bottomY.saturatingAdding(Int.lines(ofRows: count - end, pitch: estimate)).saturatingAdding(bottom))
        anchor.reportedTotal = total - top - bottom

        // The rows the band holds, and where the drawing of them starts.
        var drawFirst = first
        var drawFirstTop = firstTop
        if low >= bottomY {
            // Below the rows (the chrome under them): the last row, unseen.
            drawFirst = end - 1
            drawFirstTop = bottomY - column.pitch(of: drawFirst)
        } else {
            while drawFirst < end - 1, drawFirstTop + column.pitch(of: drawFirst) <= low {
                drawFirstTop += column.pitch(of: drawFirst)
                drawFirst += 1
            }
        }
        let clip = max(0, min(low - drawFirstTop, column.pitch(of: drawFirst) - 1))
        let rowLines = max(1, min(bottomY, max(high, drawFirstTop + clip + 1)) - drawFirstTop - clip)
        func drawn(_ line: Int) -> Int {
            if line < drawFirstTop { return top + line - drawFirstTop }
            if line < bottomY { return top + line - drawFirstTop - clip }
            return top + rowLines + line - bottomY
        }
        let drawnLines = drawn(low)..<(drawn(high - 1) + 1)

        var ladder: [String: Int] = [:]
        for row in first..<end {
            if let key = column.key(at: row) { ladder[key] = row }
        }
        rows.ladder = ladder

        let band = PulledBand(
            position: position, lines: (low + position)..<(high + position), total: total,
            resolvedSeek: resolvedSeek, totalIsEstimate: viewBottom == nil || viewTop == nil)
        if corrected, !resolvedSeek, !window.isPulled {
            window.reportResolvedOffset(position, isHold: true)
        }
        return PulledRowsBand(
            band: band, firstRow: drawFirst, clip: clip, rowLines: rowLines, drawnLines: drawnLines,
            rows: first..<end, firstRowTop: firstTop + position, column: column, viewportHeight: viewport)
    }
}

extension PulledRows {
    /// The rows a view of rows of varying height draws with no request — the
    /// first frame's measuring walk — from its top, down to `reach` lines:
    /// the first row and the number of lines of rows to draw.
    package func top(count: Int, top: Int, bottom: Int, reach: Int, pitch: (Int) -> Int) -> (rowLines: Int, lines: Int) {
        var lines = 0
        var row = 0
        while row < count, top + lines < reach {
            let measured = max(1, pitch(row))
            note(pitch: measured, of: row)
            lines += measured
            row += 1
        }
        let rowLines = max(1, lines)
        return (rowLines, max(1, min(top + rowLines + bottom, reach)))
    }
}
