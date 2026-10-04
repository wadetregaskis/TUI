//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SoftWrapLayout.swift
//
//  The rows an editable text soft-wraps into, in terminal cells, and the
//  mapping between a caret's character offset and a row and a column.
//
//  Created by Wade Tregaskis
//  License: MIT

/// The rows an editable text soft-wraps into at a width, in terminal cells, and
/// the two-way mapping between a character offset — a caret, an end of a
/// selection — and a row and a column.
///
/// `Text` wraps for display (``TextWrapping``): it drops the space it breaks
/// at, and leaves a word too long for its line to be truncated. Text being
/// edited cannot lose a character, so here every character of the text is on
/// exactly one row, and every caret offset has a cell to be drawn on. The rules
/// are the macOS text system's, measured on a vertical `TextField` (macOS
/// 15.8):
///
/// - A newline ends a row, and is itself drawn nowhere. Text ending in a
///   newline has an empty last row, where the caret after it sits.
/// - A row may break after a run of spaces. The run stays at the end of the row
///   it breaks, hanging past the wrap width rather than starting the next row
///   with a space (`"aaa bbb ccc "` then `"ddd"`).
/// - A word too long for a row is broken between characters.
/// - A row may also break before or after a wide character, as ``TextWrapping``
///   allows, so a line of CJK with no spaces wraps rather than breaking
///   wherever it overflows.
///
/// **The last cell of the width is a margin.** Text wraps one cell short of the
/// width, so the caret after the last character of a full row — at a newline,
/// or at the end of the text — has a cell to sit on, as does the first space
/// hanging off a row. A caret further into a hanging run sits on the margin
/// too; the macOS text system clamps it to the edge the same way.
///
/// An offset where a row was soft-wrapped is both the end of that row and the
/// start of the next. Which one the caret is drawn at is its affinity:
/// ``TextSelectionAffinity/upstream`` draws it at the end of the earlier row,
/// and anything else at the start of the later one, which is where the macOS
/// text system draws an insertion point after typing.
///
/// Shared rather than the vertical field's own because it is the half of soft
/// wrapping that ``TextEditor`` would need too; see
/// `Documentation/SwiftUI-API-completion-decisions-W06b.md`.
struct SoftWrapLayout: Equatable {
    /// One row: the characters it draws, and how it ends.
    struct Row: Equatable {
        /// The offset of the row's first character.
        let start: Int

        /// The offset one past the row's last character, its newline excluded.
        let end: Int

        /// Whether a newline or the end of the text follows the row. A row that
        /// does not was soft-wrapped, and the offset at its end is also the
        /// start of the next row.
        let endsParagraph: Bool
    }

    /// The rows, top to bottom. Never empty: an empty text is one empty row.
    let rows: [Row]

    /// Each character's width in cells, by offset; a newline's is 0.
    let cellWidths: [Int]

    /// The cells a row may draw on. Text wraps at one fewer (the margin).
    let width: Int

    /// The number of characters laid out — the largest caret offset.
    var characterCount: Int { cellWidths.count }

    /// Lays out `characters` in rows `width` cells wide.
    ///
    /// - Parameters:
    ///   - characters: The text, as characters.
    ///   - width: The cells a row may draw on, the margin included.
    ///   - cellWidth: A character's width in cells. Called for every character
    ///     that is not a newline.
    init(_ characters: [Character], width: Int, cellWidth: (Character) -> Int) {
        let width = max(1, width)
        let widths = characters.map { $0.isNewline ? 0 : cellWidth($0) }
        let budget = max(1, width - 1)
        var rows: [Row] = []
        var start = 0
        for (offset, character) in characters.enumerated() where character.isNewline {
            Self.wrap(characters, from: start, to: offset, budget: budget, widths: widths, into: &rows)
            start = offset + 1
        }
        Self.wrap(characters, from: start, to: characters.count, budget: budget, widths: widths, into: &rows)
        (self.rows, cellWidths, self.width) = (rows, widths, width)
    }

    /// Whether a row may break after `character`, hanging it past the margin.
    private static func hangs(_ character: Character) -> Bool {
        character == " " || character == "\t"
    }

    /// Lays one paragraph, `start..<end`, into rows of `budget` cells, the last
    /// of which ends the paragraph.
    private static func wrap(
        _ characters: [Character], from start: Int, to end: Int, budget: Int, widths: [Int],
        into rows: inout [Row]
    ) {
        var rowStart = start
        while true {
            let rowEnd = rowBreak(characters, from: rowStart, to: end, budget: budget, widths: widths)
            guard rowEnd < end else {
                rows.append(Row(start: rowStart, end: end, endsParagraph: true))
                return
            }
            rows.append(Row(start: rowStart, end: rowEnd, endsParagraph: false))
            rowStart = rowEnd
        }
    }

    /// Where the row starting at `start` ends: `end` when the rest of the
    /// paragraph fits, else the last place it may break.
    private static func rowBreak(
        _ characters: [Character], from start: Int, to end: Int, budget: Int, widths: [Int]
    ) -> Int {
        var cells = 0  // the row's cells, not counting a run of spaces at its end
        var hanging = 0  // that run's cells
        var lastBreak: Int?  // the latest offset the row may end at
        var offset = start
        while offset < end {
            let width = widths[offset]
            if hangs(characters[offset]) {
                hanging += width
                offset += 1
                lastBreak = offset
                continue
            }
            if width >= 2, offset > start { lastBreak = offset }
            guard cells + hanging + width <= budget else {
                if let lastBreak, lastBreak > start { return lastBreak }
                // One character wider than the whole row still goes on it.
                return offset > start ? offset : offset + 1
            }
            cells += hanging + width
            hanging = 0
            offset += 1
            if width >= 2 { lastBreak = offset }
        }
        return end
    }

    // MARK: - Offsets and rows

    /// The row the caret at `offset` is drawn on.
    func row(of offset: Int, affinity: TextSelectionAffinity) -> Int {
        let offset = min(max(0, offset), characterCount)
        // The last row starting at or before the offset.
        var low = 0
        var high = rows.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if rows[middle].start <= offset { low = middle } else { high = middle - 1 }
        }
        if affinity == .upstream, low > 0, rows[low].start == offset, !rows[low - 1].endsParagraph {
            return low - 1
        }
        return low
    }

    /// The cells `row`'s characters before `offset` take.
    func cells(inRow row: Int, before offset: Int) -> Int {
        let row = rows[row]
        let upper = min(max(row.start, offset), row.end)
        return cellWidths[row.start..<upper].reduce(0, +)
    }

    /// The column the caret at `offset` is drawn at on `row`: the cells before
    /// it, held to the last cell.
    func column(of offset: Int, inRow row: Int) -> Int {
        min(cells(inRow: row, before: offset), width - 1)
    }

    /// The largest offset on `row` whose caret is drawn there: the row's end
    /// where it ends a paragraph, or under `.upstream`; otherwise the offset
    /// before its last character, since the end is drawn on the next row.
    func lastCaretOffset(inRow row: Int, affinity: TextSelectionAffinity) -> Int {
        let row = rows[row]
        guard !row.endsParagraph, affinity != .upstream else { return row.end }
        return max(row.start, row.end - 1)
    }

    /// The caret offset on `row` nearest `column`: before the character whose
    /// cells hold the column, or the row's last caret offset past its text.
    func offset(inRow row: Int, atColumn column: Int, affinity: TextSelectionAffinity) -> Int {
        let last = lastCaretOffset(inRow: row, affinity: affinity)
        var cellX = 0
        for offset in rows[row].start..<rows[row].end {
            let next = cellX + cellWidths[offset]
            if column < next { return min(offset, last) }
            cellX = next
        }
        return last
    }
}
