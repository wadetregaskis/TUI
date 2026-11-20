//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHandler+LineHeight.swift
//
//  An attributed editor's paragraph line heights (G3 L4, the owner's rulings
//  A-ATTRED-3 of 2026-11-17 and A-ATTRED-13 (b) of 2026-11-19): the blank rows
//  each line's rows are followed by, which a wrapping editor's rows count
//  (`WrappedRows`), read for every line, since each moves every row after it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

/// What an editor knows of its lines' line heights: nothing yet, or the blank
/// rows after each of each line's rows, by line (`nil` inside where no line
/// has any).
enum EditorLineGaps {
    case unread
    case read([Int]?)
}

/// The stretches of a text that state a line height of more than one row a
/// line, and how many rows (``ParagraphLineRows``).
typealias LineRowRuns = (AttributedSubstring) -> [(range: Range<AttributedString.Index>, rows: Int)]

extension TextEditorHandler {
    /// The blank rows after each of each line's rows, by line, for the
    /// value's characters laid out as `layout`, or `nil` where no paragraph
    /// takes more than a row a line, the editor is bound to a `String`, or its
    /// text is hidden. Read whole once for each value taken, and for the lines
    /// an edit changes after it (``replaceLineGaps(_:with:in:)``): a
    /// paragraph's blank rows move every row after it, so the rows need every
    /// line's.
    func lineGaps(for layout: EditorLayout) -> [Int]? {
        guard let source = attributedSource, !isSecure else { return nil }
        if case .read(let gaps) = keptLineGaps, gaps.map({ $0.count == layout.lines.count }) ?? true { return gaps }
        let gaps = Self.lineGaps(
            in: source.value, lines: layout.lines.indices, characterStarts: layout.characterStarts,
            reading: lineRowRuns)
        let kept = gaps.contains { $0 > 0 } ? gaps : nil
        keptLineGaps = .read(kept)
        return kept
    }

    /// ``lineGaps(for:)`` of the text's layout.
    func lineGaps() -> [Int]? {
        guard attributedSource != nil, !isSecure else { return nil }
        return lineGaps(for: layout())
    }

    /// An edit replaced the lines `replaced` with those of `layout` in
    /// `replacement`, and the value is the one it made: the lines it put in
    /// are read, those before keep theirs, and those after move with them.
    func replaceLineGaps(_ replaced: Range<Int>, with replacement: Range<Int>, in layout: EditorLayout) {
        guard case .read(let kept) = keptLineGaps, let source = attributedSource else { return }
        let fresh = Self.lineGaps(
            in: source.value, lines: replacement, characterStarts: layout.characterStarts, reading: lineRowRuns)
        guard kept != nil || fresh.contains(where: { $0 > 0 }) else { return }
        var gaps = kept ?? Array(repeating: 0, count: layout.lines.count - replacement.count + replaced.count)
        gaps.replaceSubrange(replaced, with: fresh)
        keptLineGaps = .read(gaps.contains { $0 > 0 } ? gaps : nil)
    }

    /// The blank rows after each of the rows of each of `lines`, the lines of
    /// `value` that start at `characterStarts`: its paragraph's rows a line
    /// less one, read from the line's first character (its line break, where
    /// it is empty), as its alignment is.
    static func lineGaps(
        in value: AttributedString, lines: Range<Int>, characterStarts: [Int], reading lineRowRuns: LineRowRuns
    ) -> [Int] {
        var gaps = [Int](repeating: 0, count: lines.count)
        let characters = value.characters
        guard !lines.isEmpty,
            let lower = characters.index(
                value.startIndex, offsetBy: characterStarts[lines.lowerBound], limitedBy: value.endIndex)
        else { return gaps }
        let upper =
            lines.upperBound < characterStarts.count
            ? characters.index(value.startIndex, offsetBy: characterStarts[lines.upperBound], limitedBy: value.endIndex)
                ?? value.endIndex
            : value.endIndex
        for (range, rows) in lineRowRuns(value[lower..<upper]) where rows > 1 {
            let start = characters.distance(from: value.startIndex, to: range.lowerBound)
            let end = characters.distance(from: value.startIndex, to: range.upperBound)
            // The first of `lines` starting in the run, then each after it that does.
            var (low, high) = (lines.lowerBound, lines.upperBound)
            while low < high {
                let middle = (low + high) / 2
                if characterStarts[middle] < start { low = middle + 1 } else { high = middle }
            }
            while low < lines.upperBound, characterStarts[low] < end {
                gaps[low - lines.lowerBound] = rows - 1
                low += 1
            }
        }
        return gaps
    }

    /// The stretches of `text` whose paragraphs state a line height
    /// (`lineHeight`), and the rows each of their lines takes: none on a Mac
    /// before macOS 26, which has no line height (as SwiftUI's has none).
    static func statedLineRows(in text: AttributedSubstring) -> [(range: Range<AttributedString.Index>, rows: Int)] {
        #if canImport(CoreText)
            guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return [] }
        #endif
        return text.runs[AttributeScopes.CoreTextAttributes.LineHeightAttribute.self].compactMap { height, range in
            guard let rows = height?.drawnRows, rows > 1 else { return nil }
            return (range, rows)
        }
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
