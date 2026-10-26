//  🖥️ TUI — A Terminal UI framework for Swift
//  EditorLayout+Wrapping.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

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
        let width = max(1, width)
        if let index = wrappings.firstIndex(where: { $0.rows.width == width && $0.tabWidth == tabWidth }) {
            wrappings[index].frame = frame
            return wrappings[index].rows
        }
        let rows = WrappedRows(lines: lines, width: width, tabWidth: tabWidth)
        wrapsMade += 1
        if wrappings.count >= Self.wrappingLimit {
            // The one asked for longest ago.
            if let stalest = wrappings.indices.min(by: { wrappings[$0].frame < wrappings[$1].frame }) {
                wrappings.remove(at: stalest)
            }
        }
        wrappings.append((rows, tabWidth, frame))
        return rows
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
