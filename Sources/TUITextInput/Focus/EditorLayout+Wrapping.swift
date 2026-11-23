//  🖥️ TUI — A Terminal UI framework for Swift
//  EditorLayout+Wrapping.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// A document's lines wrapped into rows at one width: each line's
/// ``SoftWrapLayout``, and where each line's rows start among all of them.
///
/// An attributed editor's paragraph may take more rows a line (its
/// `lineHeight`, the owner's ruling A-ATTRED-13): ``gaps`` blank rows after
/// each of its rows, which are rows here like any other, so the scroll, the
/// scroll bar and the screen count them, but which hold no text. A blank row
/// belongs to the text row above it (``location(ofRow:)``), the caret is never
/// on one (``row(ofLine:column:affinity:)``), and none follows the document's
/// last row (``rowCount``).
struct WrappedRows {
    /// The cells a row may draw on.
    let width: Int

    /// Each line's layout, by line.
    private(set) var lines: [SoftWrapLayout]

    /// The first row of each line, and one past the last row at the end — so
    /// `rowStarts[line + 1] - rowStarts[line]` is a line's row count, its
    /// blank rows included.
    private(set) var rowStarts: [Int]

    /// The blank rows after each row of each line, by line, or `nil` where no
    /// line has any (``spaced(by:)``).
    private(set) var gaps: [Int]?

    /// Every row of the document: none after its last text row.
    var rowCount: Int { (rowStarts.last ?? 0) - gap(ofLine: lines.count - 1) }

    /// The blank rows after each of `line`'s rows.
    func gap(ofLine line: Int) -> Int {
        guard let gaps, line >= 0, line < gaps.count else { return 0 }
        return gaps[line]
    }

    /// Wraps `lines` at `width`, tabs reaching their stops from each row's
    /// start.
    init(lines: [TextCharacters], width: Int, tabWidth: TabWidth) {
        self.width = max(1, width)
        var layouts: [SoftWrapLayout] = []
        layouts.reserveCapacity(lines.count)
        var starts: [Int] = [0]
        starts.reserveCapacity(lines.count + 1)
        for line in lines {
            let layout = Self.layout(of: line, width: self.width, tabWidth: tabWidth)
            layouts.append(layout)
            starts.append(starts[starts.count - 1] + layout.rows.count)
        }
        (self.lines, rowStarts) = (layouts, starts)
    }

    /// One line wrapped at `width`, tabs reaching their stops from each row's
    /// start.
    private static func layout(of line: TextCharacters, width: Int, tabWidth: TabWidth) -> SoftWrapLayout {
        SoftWrapLayout(line, width: width, tabWidth: tabWidth)
    }

    /// These rows with `gaps[line]` blank rows after each of `line`'s
    /// (`nil` for none): the rows' starts made again, one pass over the
    /// lines, the wrapping kept.
    func spaced(by gaps: [Int]?) -> Self {
        guard gaps != nil || self.gaps != nil else { return self }
        var spaced = self
        spaced.gaps = gaps
        var next = 0
        for line in lines.indices {
            spaced.rowStarts[line] = next
            next += lines[line].rows.count * (1 + spaced.gap(ofLine: line))
        }
        spaced.rowStarts[lines.count] = next
        return spaced
    }

    /// Replaces the lines `replaced` with `newLines`, wrapped, and moves the
    /// rows of the lines after them by as many rows as that adds or takes
    /// away: an edit's lines wrapped again, and no other
    /// (``EditorLayout/laidOut(_:reusingStorage:)``). In place, where the rows
    /// are this value's alone.
    mutating func replaceLines(_ replaced: Range<Int>, with newLines: ArraySlice<TextCharacters>, tabWidth: TabWidth) {
        // Only an unspaced wrapping is kept across an edit: its spaced rows
        // are made again from it (``spaced(by:)``).
        assert(gaps == nil, "an edit replaces the lines of unspaced rows")
        let layouts = newLines.map { Self.layout(of: $0, width: width, tabWidth: tabWidth) }
        var ends: [Int] = []
        ends.reserveCapacity(layouts.count)
        var next = rowStarts[replaced.lowerBound]
        for layout in layouts {
            next += layout.rows.count
            ends.append(next)
        }
        let shift = next - rowStarts[replaced.upperBound]
        lines.replaceSubrange(replaced, with: layouts)
        // A line's row ends are the next line's starts: those of the lines
        // replaced give way to the new lines', and the rest move.
        rowStarts.replaceSubrange((replaced.lowerBound + 1)..<(replaced.upperBound + 1), with: ends)
        if shift != 0 {
            for index in (replaced.lowerBound + 1 + ends.count)..<rowStarts.count { rowStarts[index] += shift }
        }
    }

    /// The row a line's `rowInLine` is, among all of them.
    func row(line: Int, rowInLine: Int) -> Int {
        let line = min(max(0, line), lines.count - 1)
        return rowStarts[line] + min(max(0, rowInLine), lines[line].rows.count - 1) * (1 + gap(ofLine: line))
    }

    /// The line `row` belongs to, and which of its rows it is: a blank row's
    /// is the text row above it.
    func location(ofRow row: Int) -> (line: Int, rowInLine: Int) {
        let place = placement(ofRow: row)
        return (place.line, place.rowInLine)
    }

    /// The line `row` belongs to, which of its rows it is, and how many rows
    /// below that row's text it is (0 for the text row itself, more for a
    /// blank row after it).
    func placement(ofRow row: Int) -> RowPlacement {
        let row = min(max(0, row), max(0, rowCount - 1))
        // The last line starting at or before `row`.
        var low = 0
        var high = lines.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if rowStarts[middle] <= row { low = middle } else { high = middle - 1 }
        }
        let (rowInLine, blank) = (row - rowStarts[low]).quotientAndRemainder(dividingBy: 1 + gap(ofLine: low))
        return RowPlacement(line: low, rowInLine: rowInLine, blank: blank)
    }

    /// The row after `place`: its next blank row, its line's next row, or the
    /// next line's first.
    func placement(after place: RowPlacement) -> RowPlacement {
        if place.blank < gap(ofLine: place.line) {
            return RowPlacement(line: place.line, rowInLine: place.rowInLine, blank: place.blank + 1)
        }
        if place.rowInLine + 1 < lines[place.line].rows.count {
            return RowPlacement(line: place.line, rowInLine: place.rowInLine + 1, blank: 0)
        }
        return RowPlacement(line: place.line + 1, rowInLine: 0, blank: 0)
    }

    /// `row` if it holds text, else the first row after it that does: where a
    /// motion down that lands among blank rows stops.
    func textRow(atOrAfter row: Int) -> Int {
        let place = placement(ofRow: row)
        guard place.blank > 0 else { return row }
        return min(row - place.blank + 1 + gap(ofLine: place.line), max(0, rowCount - 1))
    }

    /// The row the caret at `column` of `line` is drawn on, among all of them:
    /// always a text row.
    func row(ofLine line: Int, column: Int, affinity: TextSelectionAffinity) -> Int {
        let line = min(max(0, line), lines.count - 1)
        return rowStarts[line] + lines[line].row(of: column, affinity: affinity) * (1 + gap(ofLine: line))
    }
}

/// Where a row of ``WrappedRows`` is: its line, which of the line's rows, and
/// how many blank rows below that row's text (0 for the text row itself).
struct RowPlacement: Equatable {
    var line: Int
    var rowInLine: Int
    var blank: Int
}

extension EditorLayout {
    /// The most wrappings kept at once: a bound on memory, not the rule. Each
    /// is the whole document laid out.
    static let wrappingLimit = 8

    /// The document wrapped at `width`, kept for the text this layout is of.
    ///
    /// Every width a frame asks for is kept until a frame asks for none of it
    /// (``endFrame()``), not a fixed number of the latest: an editor is laid
    /// out at as many widths a frame as its container measures it at. One
    /// whose text overflows wraps at its whole width and again a cell
    /// narrower, for the scroll bar's column; in an `HStack` it is measured
    /// first at the full width, then at the width it is given, so that is
    /// three widths a frame, and two kept meant the whole document wrapped
    /// three times on every idle frame.
    func wrapped(width: Int, tabWidth: TabWidth) -> WrappedRows {
        wrappings[wrappingIndex(width: width, tabWidth: tabWidth)].rows
    }

    /// The document wrapped at `width` with `gaps[line]` blank rows after each
    /// of `line`'s rows (an attributed editor's line heights;
    /// ``WrappedRows/spaced(by:)``), kept beside the wrapping while the gaps are
    /// the same: compared as arrays, which answer from their storage when they
    /// are the one array, as the handler hands the one it keeps.
    func wrapped(width: Int, tabWidth: TabWidth, gaps: [Int]?) -> WrappedRows {
        let index = wrappingIndex(width: width, tabWidth: tabWidth)
        guard let gaps else { return wrappings[index].rows }
        if let spaced = wrappings[index].spaced, spaced.gaps == gaps { return spaced.rows }
        let rows = wrappings[index].rows.spaced(by: gaps)
        wrappings[index].spaced = (gaps, rows)
        return rows
    }

    /// The index in ``wrappings`` of the document wrapped at `width`, wrapped
    /// now if no frame asked for it, and stamped as this frame's.
    private func wrappingIndex(width: Int, tabWidth: TabWidth) -> Int {
        let width = max(1, width)
        if let index = wrappings.firstIndex(where: { $0.rows.width == width && $0.tabWidth == tabWidth }) {
            wrappings[index].frame = frame
            return index
        }
        let rows = WrappedRows(lines: lines, width: width, tabWidth: tabWidth)
        wrapsMade += 1
        if wrappings.count >= Self.wrappingLimit {
            // The one asked for longest ago.
            if let stalest = wrappings.indices.min(by: { wrappings[$0].frame < wrappings[$1].frame }) {
                wrappings.remove(at: stalest)
            }
        }
        wrappings.append((rows, tabWidth, frame, nil))
        return wrappings.count - 1
    }

    /// Ends a drawn frame: forgets the widths it did not ask for, and stamps
    /// what the next frame asks for as the next frame's.
    ///
    /// Called by the editor at the end of its render — after this frame's
    /// measures and its own wraps, which are what the next frame will ask for
    /// again.
    func endFrame() {
        wrappings.removeAll { $0.frame != frame }
        frame &+= 1
    }
}
