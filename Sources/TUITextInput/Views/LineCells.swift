//  🖥️ TUI — A Terminal UI framework for Swift
//  LineCells.swift
//
//  Where a line's characters start in cells, sampled every few characters, so
//  that an editor that scrolls sideways draws a row from the first character
//  its window shows rather than the line's first (H-88, TEXTIN-7).
//
//  Created by Wade Tregaskis
//  License: MIT

/// The cells one line's characters start at, sampled every ``stride``
/// characters, for one ``TabWidth``: what lets an editor that scrolls sideways
/// find the character a cell column falls in, or the column a character starts
/// at, by stepping over at most ``stride`` characters, not every one before it.
///
/// A row of a line far longer than the editor used to be walked from the
/// line's first character, each character's width looked up, to find where
/// the window starts, and on past its end to the line's: 20 lines of 10,000
/// characters cost 200,000 steps a frame to draw 80 columns of each (H-88).
/// Made once for a line on screen, with a walk of the line, and kept by its
/// ``EditorLayout`` until an edit replaces the line
/// (``EditorLayout/cells(ofLine:tabWidth:)``).
///
/// A walk may start at a sample because a character's cells depend only on
/// the column it starts at: a tab reaches its stop from there, anything else
/// takes its own width (``TabLayout/advance(from:over:tabWidth:)``).
struct LineCells {
    /// Characters between two samples: a walk to any column steps over fewer
    /// than this many before the character it wants. 64 keeps a line's
    /// samples an eighth of a byte a character, and a sought column a short
    /// walk from its sample.
    static let stride = 64

    /// The tab stops the cells were counted with.
    let tabWidth: TabWidth

    /// The line's characters.
    let count: Int

    /// The cells the whole line takes.
    let total: Int

    /// The cell character `k * stride` starts at, for each `k` while that is
    /// a character of the line; `nil` where every character is one cell and
    /// none a tab, so a character's index is its column.
    private let samples: [Int]?

    /// `line`'s cells with tab stops at `tabWidth`: one walk of it.
    init(_ line: TextCharacters, tabWidth: TabWidth) {
        let count = line.count
        (self.tabWidth, self.count) = (tabWidth, count)
        var samples: [Int] = []
        samples.reserveCapacity(count / Self.stride + 1)
        // A line is plain where no character steps more than a cell: a tab
        // that does not (a stop every cell) is a cell like any other.
        var (column, isPlain) = (0, true)
        // An ASCII line from its bytes, as a wrap reads it (`SoftWrapLayout`).
        let readBytes: Void? = unsafe line.withASCIIBytes { bytes in
            for unsafe (index, byte) in unsafe bytes.enumerated() {
                if index.isMultiple(of: Self.stride) { samples.append(column) }
                let next = TabLayout.advance(from: column, overASCII: byte, tabWidth: tabWidth)
                if next != column + 1 { isPlain = false }
                column = next
            }
        }
        if readBytes == nil {
            for index in 0..<count {
                if index.isMultiple(of: Self.stride) { samples.append(column) }
                let next = TabLayout.advance(from: column, at: index, of: line, tabWidth: tabWidth)
                if next != column + 1 { isPlain = false }
                column = next
            }
        }
        TabLayout.reportWalk(count)
        total = column
        self.samples = isPlain ? nil : samples
    }

    /// The cell the character at `index` of `line` starts at: ``total`` for
    /// `index == count`. `line` is the one these cells were made from.
    func column(of index: Int, in line: TextCharacters) -> Int {
        let index = min(max(0, index), count)
        guard let samples else { return index }
        guard index < count else { return total }
        var (at, column) = (index / Self.stride * Self.stride, samples[index / Self.stride])
        let walked = index - at
        while at < index {
            column = TabLayout.advance(from: column, at: at, of: line, tabWidth: tabWidth)
            at += 1
        }
        TabLayout.reportWalk(walked)
        return column
    }

    /// A character at or before the one cell `column` falls in, and the cell
    /// it starts at: where a walk that must reach `column` may start. The
    /// first character for a column before the line; past its end, a
    /// character fewer than ``stride`` from the last.
    func start(atOrBefore column: Int) -> (index: Int, column: Int) {
        guard column > 0 else { return (0, 0) }
        guard let samples else {
            let index = min(column, count)
            return (index, index)
        }
        // The last sample at or before `column`: the first is 0, so there is one.
        var (low, high) = (0, samples.count)
        while high - low > 1 {
            let middle = (low + high) / 2
            if samples[middle] <= column { low = middle } else { high = middle }
        }
        return (low * Self.stride, samples[low])
    }

    /// The character whose cells hold `column`, as
    /// ``TabLayout/charIndex(forDisplayColumn:in:tabWidth:)`` finds it: the
    /// end-of-line insertion point (`count`) at or past the line's end.
    func index(atColumn column: Int, in line: TextCharacters) -> Int {
        guard samples != nil else { return min(max(0, column), count) }
        guard column < total else { return count }
        var (index, at) = start(atOrBefore: column)
        var walked = 0
        defer { TabLayout.reportWalk(walked) }
        while index < count {
            let next = TabLayout.advance(from: at, at: index, of: line, tabWidth: tabWidth)
            walked += 1
            if column < next { return index }
            (index, at) = (index + 1, next)
        }
        return count
    }
}

// MARK: - Kept by a layout

extension EditorLayout {
    /// The cells of `line` with tab stops at `tabWidth`: those kept for it,
    /// or made now and kept, until an edit replaces the line or the line goes
    /// a frame undrawn (``endFrame()``).
    func cells(ofLine line: Int, tabWidth: TabWidth) -> LineCells {
        if let kept = lineCells[line], kept.cells.tabWidth == tabWidth {
            lineCells[line]?.frame = frame
            return kept.cells
        }
        let made = LineCells(lines[line], tabWidth: tabWidth)
        lineCells[line] = (made, frame)
        return made
    }

    /// The kept cells of the lines `edit` left as they were, each under its
    /// line's index after the edit: those of the lines it replaced dropped.
    func cellsKept(through edit: Edit) -> [Int: (cells: LineCells, frame: UInt)] {
        let shift = edit.replacement.count - edit.replaced.count
        var kept: [Int: (cells: LineCells, frame: UInt)] = [:]
        for (line, entry) in lineCells where !edit.replaced.contains(line) {
            kept[line < edit.replaced.lowerBound ? line : line + shift] = entry
        }
        return kept
    }
}
