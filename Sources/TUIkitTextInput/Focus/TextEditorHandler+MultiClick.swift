//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextEditorHandler+MultiClick.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Multi-click selection

extension TextEditorHandler {
    /// The run of `granularity` around the character at `position`: a word
    /// as a field's (``TextFieldHandler/range(of:around:)``), or the line,
    /// with its line break.
    ///
    /// Measured against `NSTextView` on macOS 15.8: a word at a line's end —
    /// the line break — or on an empty line is the line break alone, while
    /// past the last line's text it is the last run.
    func range(
        of granularity: TextSelectionGranularity, around position: TextEditorPosition
    ) -> (start: TextEditorPosition, end: TextEditorPosition) {
        let lines = readLines()
        let line = min(max(0, position.line), lines.count - 1)
        let column = min(max(0, position.column), lines[line].count)
        let lineBreak = line + 1 < lines.count
        let lineEnd = TextEditorPosition(line: line, column: lines[line].count)
        let paragraphEnd = lineBreak ? TextEditorPosition(line: line + 1, column: 0) : lineEnd
        switch granularity {
        case .word where column == lines[line].count && lineBreak:
            return (lineEnd, paragraphEnd)
        case .word:
            let run = WordBoundary.run(in: lines[line], around: column)
            return (
                TextEditorPosition(line: line, column: run.lowerBound),
                TextEditorPosition(line: line, column: run.upperBound)
            )
        case .paragraph:
            return (TextEditorPosition(line: line, column: 0), paragraphEnd)
        }
    }

    /// Selects the run of `granularity` around `position`, a multi-click's,
    /// and remembers it for a drag that follows to extend from.
    func selectRun(_ granularity: TextSelectionGranularity, around position: TextEditorPosition) {
        let run = range(of: granularity, around: position)
        multiClickRun = (granularity, run.start, run.end)
        selectionAnchor = run.start
        moveCursor(toLine: run.end.line, column: run.end.column)
        rowStartHead = nil
        pressAnchor = nil
    }

    /// Extends a multi-click's selection by its runs to the one around
    /// `position`, keeping the run first clicked selected whichever way the
    /// drag goes. Returns `false`, changing nothing, when the press was not a
    /// multi-click.
    func extendRun(to position: TextEditorPosition) -> Bool {
        guard let clicked = multiClickRun else { return false }
        let run = range(of: clicked.granularity, around: position)
        let head: TextEditorPosition
        if run.start < clicked.start {
            selectionAnchor = clicked.end
            head = run.start
        } else {
            selectionAnchor = clicked.start
            head = max(run.end, clicked.end)
        }
        moveCursor(toLine: head.line, column: head.column)
        rowStartHead = nil
        return true
    }
}
