//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EditorLayout+Wrapping.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// A document's lines wrapped into rows at one width: each line's
/// ``SoftWrapLayout``, and where each line's rows start among all of them.
struct WrappedRows {
    /// The cells a row may draw on.
    let width: Int

    /// Each line's layout, by line.
    let lines: [SoftWrapLayout]

    /// The first row of each line, and one past the last row at the end — so
    /// `rowStarts[line + 1] - rowStarts[line]` is a line's row count.
    let rowStarts: [Int]

    /// Every row of the document.
    var rowCount: Int { rowStarts.last ?? 0 }

    /// Wraps `lines` at `width`, tabs reaching their stops from each row's
    /// start.
    init(lines: [[Character]], width: Int, tabWidth: TabWidth) {
        self.width = max(1, width)
        var layouts: [SoftWrapLayout] = []
        layouts.reserveCapacity(lines.count)
        var starts: [Int] = [0]
        starts.reserveCapacity(lines.count + 1)
        for line in lines {
            let layout = SoftWrapLayout(line, width: self.width) { character, column in
                TabLayout.advance(from: column, over: character, tabWidth: tabWidth)
            }
            layouts.append(layout)
            starts.append(starts[starts.count - 1] + layout.rows.count)
        }
        (self.lines, rowStarts) = (layouts, starts)
    }

    /// The row a line's `rowInLine` is, among all of them.
    func row(line: Int, rowInLine: Int) -> Int {
        let line = min(max(0, line), lines.count - 1)
        return rowStarts[line] + min(max(0, rowInLine), lines[line].rows.count - 1)
    }

    /// The line `row` belongs to, and which of its rows it is.
    func location(ofRow row: Int) -> (line: Int, rowInLine: Int) {
        let row = min(max(0, row), max(0, rowCount - 1))
        // The last line starting at or before `row`.
        var low = 0
        var high = lines.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if rowStarts[middle] <= row { low = middle } else { high = middle - 1 }
        }
        return (low, row - rowStarts[low])
    }

    /// The row the caret at `column` of `line` is drawn on, among all of them.
    func row(ofLine line: Int, column: Int, affinity: TextSelectionAffinity) -> Int {
        let line = min(max(0, line), lines.count - 1)
        return rowStarts[line] + lines[line].row(of: column, affinity: affinity)
    }
}

extension EditorLayout {
    /// The document wrapped at `width`, kept for the text this layout is of.
    ///
    /// Two widths are kept, not one: an editor whose text overflows lays its
    /// text out once at its whole width and again a cell narrower, for the
    /// scroll bar's column, and both are asked for again every frame.
    func wrapped(width: Int, tabWidth: TabWidth) -> WrappedRows {
        if let kept = wrappings.first(where: { $0.rows.width == max(1, width) && $0.tabWidth == tabWidth }) {
            return kept.rows
        }
        let rows = WrappedRows(lines: lines, width: width, tabWidth: tabWidth)
        if wrappings.count >= 2 { wrappings.removeFirst() }
        wrappings.append((rows, tabWidth))
        return rows
    }
}
