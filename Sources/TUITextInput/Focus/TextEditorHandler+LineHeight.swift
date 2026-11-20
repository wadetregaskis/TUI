//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHandler+LineHeight.swift
//
//  An attributed editor's paragraph line heights (G3 L4, the owner's rulings
//  A-ATTRED-3 of 2026-11-17 and A-ATTRED-13 (b) of 2026-11-19): the blank rows
//  each line's rows are followed by, which an editor's rows count
//  (`WrappedRows`, `SidewaysRows`), read for the lines a frame shows.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

extension TextEditorHandler {
    /// The blank rows after each of each line's rows, by line, for the
    /// value's characters laid out as `layout`, or `nil` where no line read so
    /// far takes more than a row a line, the editor is bound to a `String`, or
    /// its text is hidden.
    ///
    /// Read a line at a time, as its styles and its alignment are
    /// (B-ATTRED-2): the lines a frame shows from the top, and the caret's,
    /// each once, kept until an edit changes it or a value is taken whole. A
    /// line never shown is never read, and counts as one row a line, so a
    /// replaced value costs nothing until it is drawn. Not the whole value at
    /// once: Foundation's runs of one key (`runs[\.lineHeight]`) take time
    /// growing with the square of the runs on macOS 15.8 (3.9 s for 40,000,
    /// 18.9 s for 80,000; `bigtext-rich`'s 640,003 would be hours), and even
    /// one character of each paragraph is about 0.65 µs a line, 26 ms for
    /// `bigtext`, against 1 ms for the rest of taking a value.
    ///
    /// So the rows below the screen are provisional: a paragraph of more than
    /// one row a line that has not been shown yet adds its blank rows when it
    /// is, and the scroll bar's extent grows by them then. What is on screen,
    /// the caret's row and the keys' steps over the blank rows are exact.
    func lineGaps(for layout: EditorLayout) -> [Int]? {
        guard let source = attributedSource, !isSecure else { return nil }
        let count = layout.lines.count
        let top = min(max(0, scrollLine), count - 1)
        for line in top..<min(count, top + max(1, viewportHeight) + 1) { readLineRows(line, in: layout, of: source) }
        if cursorLine >= 0, cursorLine < count { readLineRows(cursorLine, in: layout, of: source) }
        if let kept = keptLineGaps, kept.count == count { return kept.gaps }
        let gaps = lineStyleCache.gaps(lineCount: count)
        keptLineGaps = (count, gaps)
        return gaps
    }

    /// ``lineGaps(for:)`` of the text's layout.
    func lineGaps() -> [Int]? {
        guard attributedSource != nil, !isSecure else { return nil }
        return lineGaps(for: layout())
    }

    /// Reads `line`'s rows a line, unless it has been: its paragraph's, from
    /// its first character (its line break, where it is empty), as its
    /// alignment is. A line of more than one row a line has the gaps made
    /// again.
    private func readLineRows(_ line: Int, in layout: EditorLayout, of source: AttributedTextSource) {
        let read = lineStyleCache.readLineRows(ofLine: line) { line in
            Self.lineRows(ofLine: line, in: source.value, characterStarts: layout.characterStarts, reading: lineRowsOfRun)
        }
        if read { keptLineGaps = nil }
    }

    /// The rows each line of `line`'s paragraph takes, read from its first
    /// character by `rowsOfRun`; one for a line past the text's last
    /// character. The character is read as a substring, not through `runs`,
    /// which a program on Windows cannot link (`Documentation/Windows
    /// port.md`, "Toolchain").
    static func lineRows(
        ofLine line: Int, in value: AttributedString, characterStarts: [Int],
        reading rowsOfRun: (AttributedSubstring) -> Int
    ) -> Int {
        guard line < characterStarts.count,
            let index = value.characters.index(value.startIndex, offsetBy: characterStarts[line], limitedBy: value.endIndex),
            index < value.endIndex
        else { return 1 }
        return rowsOfRun(value[index..<value.characters.index(after: index)])
    }

    /// Puts the top of the view at `row` of `rows`, a blank one too: kept as
    /// its line, the line's row and the blank rows below it, so a change of
    /// width keeps the top paragraph where it was.
    func scroll(toRow row: Int, in rows: WrappedRows) {
        let place = rows.placement(ofRow: row)
        (scrollLine, scrollRowInLine, scrollBlankRows) = (place.line, place.rowInLine, place.blank)
    }

    /// The rows of an editor that scrolls sideways, its paragraphs' blank rows
    /// among them, kept while the lines and their gaps are the same.
    func sidewaysRows() -> SidewaysRows {
        let layout = displayLayout()
        let gaps = lineGaps(for: layout)
        guard gaps != nil else { return SidewaysRows(lineCount: layout.lines.count, gaps: nil) }
        if let kept = keptSidewaysRows, kept.lineCount == layout.lines.count, kept.gaps == gaps { return kept }
        let rows = SidewaysRows(lineCount: layout.lines.count, gaps: gaps)
        keptSidewaysRows = rows
        return rows
    }

    /// The top row on screen of an editor that scrolls sideways: a blank one
    /// too.
    func sidewaysTopRow(in rows: SidewaysRows) -> Int {
        min(rows.row(ofLine: scrollLine) + min(scrollBlankRows, rows.gap(ofLine: scrollLine)), max(0, rows.rowCount - 1))
    }

    /// Puts the top of an editor that scrolls sideways at `row`: kept as its
    /// line and the blank rows below it.
    func scrollSideways(toRow row: Int, in rows: SidewaysRows) {
        (scrollLine, scrollBlankRows) = rows.placement(ofRow: row)
    }
}

/// Where the lines of an editor that scrolls sideways are drawn: each line one
/// row, followed by its paragraph's blank rows (``TextEditorHandler/lineGaps(for:)``),
/// none after the last line. With no gaps every line is its own row, and each
/// answer is the line's index.
struct SidewaysRows {
    let lineCount: Int
    let gaps: [Int]?
    /// The first row of each line, and one past the last line's rows; empty
    /// with no gaps.
    private let starts: [Int]

    init(lineCount: Int, gaps: [Int]?) {
        self.lineCount = max(1, lineCount)
        self.gaps = gaps
        guard let gaps else {
            starts = []
            return
        }
        var starts = [0]
        starts.reserveCapacity(self.lineCount + 1)
        for line in 0..<self.lineCount { starts.append(starts[line] + 1 + (line < gaps.count ? gaps[line] : 0)) }
        self.starts = starts
    }

    /// The blank rows after `line`.
    func gap(ofLine line: Int) -> Int {
        guard let gaps, line >= 0, line < gaps.count else { return 0 }
        return gaps[line]
    }

    /// Every row: none after the last line's.
    var rowCount: Int { starts.isEmpty ? lineCount : starts[lineCount] - gap(ofLine: lineCount - 1) }

    /// The row `line` is drawn on.
    func row(ofLine line: Int) -> Int {
        let line = min(max(0, line), lineCount - 1)
        return starts.isEmpty ? line : starts[line]
    }

    /// The line `row` is drawn by, and how many rows below the line's it is
    /// (0 for the line's own row, more for a blank row after it).
    func placement(ofRow row: Int) -> (line: Int, blank: Int) {
        let row = min(max(0, row), max(0, rowCount - 1))
        guard !starts.isEmpty else { return (row, 0) }
        var (low, high) = (0, lineCount - 1)
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= row { low = middle } else { high = middle - 1 }
        }
        return (low, row - starts[low])
    }
}
