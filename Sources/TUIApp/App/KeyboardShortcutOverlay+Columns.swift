//  🖥️ TUI — A Terminal UI framework for Swift
//  KeyboardShortcutOverlay+Columns.swift
//
//  The list of shortcuts laid out in columns across the width it has: each
//  section kept whole where it can be, several to a column where they are
//  short, and a long one carried on into the next column under its heading
//  again, so the list scrolls only when the terminal truly can't show it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

// MARK: - The Layout

/// The list's sections in columns: which rows of which section each column
/// shows, top to bottom, with a blank row between one section and the next.
///
/// The owner (2026-11-10): keep "each headered section as one column
/// (possibly multiple headered sections in one column, if they're short
/// enough)", but "wrap if the sections are long enough (better to wrap and use
/// available horizontal space than require vertical scrolling)", and never
/// scroll sideways. So:
///
/// - In as many columns as the width holds, the shortest layout that keeps
///   every section whole, in order, the columns filled from the left. It is
///   taken whenever it fits the height the list has.
/// - Where it doesn't, a section taller than a column carries on into the
///   next one, its heading repeated ("Edit (cont.)"), and the columns are
///   as short as that makes them; a section a column can hold is still kept
///   whole, moved to the next column rather than split.
/// - Where that is still too tall, and splitting the short sections too
///   would make the list fit, they are split as well: a newspaper's columns.
///   Where even that wouldn't fit, they aren't, since the list scrolls
///   anyway.
///
/// One column never splits anything, so a terminal too narrow for two shows
/// the list as it always did, scrolling.
struct ShortcutOverlayColumns: Equatable {
    /// The rows `rows` of section `section`, under its heading: its own where
    /// `rows` starts at 0, and repeated, marked as carried on, where it
    /// doesn't.
    struct Piece: Equatable {
        let section: Int
        let rows: Range<Int>

        /// Whether this carries on a section begun in the column before.
        var continues: Bool { rows.lowerBound > 0 }

        /// Its heading and its rows.
        var height: Int { 1 + rows.count }
    }

    /// Each column's pieces, left to right.
    let columns: [[Piece]]

    /// The tallest column's rows, the blank rows between sections included.
    var height: Int { columns.lazy.map(Self.height(of:)).max() ?? 0 }

    /// Whether a section carries on from one column into another.
    var splitsASection: Bool { columns.contains { $0.contains(where: \.continues) } }

    /// The rows `column` takes.
    static func height(of column: [Piece]) -> Int {
        column.reduce(0) { $0 + $1.height } + max(0, column.count - 1)
    }

    /// Sections of `rowCounts` rows each (their headings not counted) in at
    /// most `maxColumns` columns, for a list `availableHeight` rows tall: see
    /// the type's own documentation for the choice.
    static func laidOut(rowCounts: [Int], maxColumns: Int, availableHeight: Int) -> Self {
        let wholeHeights: [Int] = rowCounts.map { 1 + $0 }
        let total: Int = wholeHeights.reduce(0, +) + max(0, wholeHeights.count - 1)
        let oneColumn = Self(
            columns: [rowCounts.indices.map { Piece(section: $0, rows: 0..<rowCounts[$0]) }])
        guard maxColumns > 1, wholeHeights.count > 1 || (rowCounts.first ?? 0) > 1 else { return oneColumn }

        // The shortest whole layout: a column no shorter than the tallest
        // section, which therefore splits none.
        var kept = oneColumn
        for height in (wholeHeights.max() ?? 0)..<total {
            if let flowed = flowed(rowCounts, height: height, maxColumns: maxColumns) {
                kept = flowed
                break
            }
        }
        guard kept.height > availableHeight else { return kept }

        // Too tall: the long sections split. No column is shorter than its
        // share of the rows.
        let share: Int = max(2, (wholeHeights.reduce(0, +) + maxColumns - 1) / maxColumns)
        func shortest(below limit: Int, splittingAll: Bool) -> Self? {
            guard share < limit else { return nil }
            for height in share..<limit {
                if let flowed = flowed(rowCounts, height: height, maxColumns: maxColumns, splittingAll: splittingAll) {
                    return flowed
                }
            }
            return nil
        }
        let long = shortest(below: kept.height, splittingAll: false) ?? kept
        guard long.height > availableHeight else { return long }
        // Still too tall: every section split, if that makes it fit.
        if let all = shortest(below: long.height, splittingAll: true), all.height <= availableHeight { return all }
        return long
    }

    /// The sections poured into columns `height` rows tall, in order, or `nil`
    /// where they need more than `maxColumns` of them.
    ///
    /// A section that fits in a column is split only `splittingAll`: it goes
    /// to the next column where this one hasn't room. Any other fills what is
    /// left of this column and carries on into the next, under its heading
    /// again, but not from a column's foot with fewer than two of its rows
    /// under the heading there: it starts on the next column instead.
    static func flowed(
        _ rowCounts: [Int], height: Int, maxColumns: Int, splittingAll: Bool = false
    ) -> Self? {
        var columns: [[Piece]] = [[]]
        var used = 0
        func place(_ piece: Piece) {
            used += (used > 0 ? 1 : 0) + piece.height
            columns[columns.count - 1].append(piece)
        }
        func nextColumn() {
            columns.append([])
            used = 0
        }
        for (section, count) in rowCounts.enumerated() {
            if !splittingAll, 1 + count <= height {
                if used > 0, used + 1 + 1 + count > height { nextColumn() }
                place(Piece(section: section, rows: 0..<count))
                continue
            }
            var start = 0
            while start < count {
                let room: Int = height - used - (used > 0 ? 1 : 0) - 1
                if used > 0, room < min(2, count - start) {
                    nextColumn()
                    continue
                }
                let taken = min(room, count - start)
                place(Piece(section: section, rows: start..<(start + taken)))
                start += taken
                if start < count { nextColumn() }
            }
        }
        return columns.count <= maxColumns ? Self(columns: columns) : nil
    }
}

// MARK: - The Columns Drawn

/// The list's sections in columns of one width, laid out
/// (``ShortcutOverlayColumns``) for the width it is offered — by its dialog,
/// trying widths — and the `visibleHeight` rows its dialog shows.
///
/// A core: what it draws depends on the width it is offered, which a
/// composition can't ask, and the dialog's own scroll view takes a body that
/// is too tall. No state of its own.
struct _ShortcutOverlayColumnsCore: View, Renderable, Layoutable {
    let listing: ShortcutOverlayListing
    /// The keys' column's width, in every column, so the columns line up.
    let keyWidth: Int
    /// The rows the dialog shows of its body without scrolling.
    let visibleHeight: Int

    /// The blank cells between two columns.
    static let gap = 3

    var body: Never { fatalError("_ShortcutOverlayColumnsCore renders via Renderable") }

    func sizeThatFits(proposal: ProposedViewSize, context: RenderContext) -> ViewSize {
        measureChild(
            arranged(width: proposal.width ?? context.availableWidth, measuring: true), proposal: proposal,
            context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIView.renderToBuffer(arranged(width: context.availableWidth, measuring: context.isMeasuring), context: context)
    }

    /// The columns for `width` cells.
    ///
    /// **The scroll bar's column.** The dialog's scroll view measures its
    /// content at the width it offers, but draws a content that overflows a
    /// column narrower, its bar taking the last. Laid out for that column
    /// less, columns that just fitted lost one as they were drawn, leaving a
    /// gap where it had been measured. So a layout too tall for the dialog is
    /// measured for a column less and a blank column after it: drawn in the
    /// width that leaves, it lays out the same.
    private func arranged(width: Int, measuring: Bool) -> some View {
        var laidOut = layout(width: width)
        var reserved = 0
        if measuring, laidOut.columns.height > visibleHeight, width > 1 {
            laidOut = layout(width: width - 1)
            reserved = 1
        }
        let sections = listing.sections
        let pieces = laidOut.columns.columns
        let keyWidth = keyWidth
        let shownWidth = min(laidOut.columnWidth, max(1, width - reserved))
        let headings = laidOut.headings
        return HStack(alignment: .top, spacing: Self.gap) {
            ForEach(pieces.indices, id: \.self) { column in
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(pieces[column].indices, id: \.self) { index in
                        let piece = pieces[column][index]
                        ShortcutOverlaySectionView(
                            title: headings(piece), rows: Array(sections[piece.section].rows[piece.rows]),
                            keyWidth: keyWidth)
                    }
                }
                .frame(width: shownWidth, alignment: .leading)
            }
        }
        .padding(.trailing, reserved)
    }

    /// The sections laid out in columns for `width` cells, how wide each
    /// column is, and the heading over each piece.
    private func layout(width: Int) -> (
        columns: ShortcutOverlayColumns, columnWidth: Int,
        headings: (ShortcutOverlayColumns.Piece) -> String
    ) {
        let sections = listing.sections
        let continued = LocalizationService.shared.string(for: LocalizationKey.Menu.shortcutsContinued)
        let carriedOn = sections.map { continued.replacingOccurrences(of: "%@", with: $0.title) }
        // A section's width: its heading's, or its widest row's, the keys in
        // their column and two cells after it.
        let widths: [Int] = sections.map { section in
            max(section.title.strippedLength, keyWidth + 2 + (section.rows.map(\.title.strippedLength).max() ?? 0))
        }
        func columns(_ columnWidth: Int) -> ShortcutOverlayColumns {
            let fitting: Int = (max(0, width) + Self.gap) / (columnWidth + Self.gap)
            return .laidOut(
                rowCounts: sections.map(\.rows.count), maxColumns: max(1, fitting), availableHeight: visibleHeight)
        }
        var columnWidth = max(1, widths.max() ?? 0)
        var laidOut = columns(columnWidth)
        // A heading carried on is longer than the section's own: where one
        // is wider than the columns, they widen to it, which may hold fewer.
        let wider = laidOut.columns.joined().filter(\.continues).map { carriedOn[$0.section].strippedLength }
        if let widest = wider.max(), widest > columnWidth {
            columnWidth = widest
            laidOut = columns(columnWidth)
        }
        return (
            laidOut, columnWidth,
            { piece in piece.continues ? carriedOn[piece.section] : sections[piece.section].title }
        )
    }
}
