//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHandler+AppEdit.swift
//
//  A TextEditor's caret, selection and block carried through an edit the app
//  made to its text — a log appended to, another user's change synced in —
//  as NSTextView carries its own (owner ruling O-28 (a), 2026-11-22).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension TextEditorHandler {
    /// Carries the caret, the selection and a block through the edit the app
    /// has made to the text since the editor last saw it (``AppTextEdit``),
    /// if it has: called wherever the text can have changed from outside, the
    /// render and the start of each key, before anything is clamped.
    ///
    /// The editor's own edits are not the app's: each tells
    /// ``selectionText`` what it wrote (``write(_:)``), so a key's echo
    /// through the binding finds nothing to carry, and costs one comparison
    /// of a string with itself. A binding that keeps something else than it
    /// was handed (one that upper-cases) is an edit of the app's, from the
    /// text the editor wrote, where its caret is.
    ///
    /// A selection the app writes in the same update (`TextEditor(text:selection:)`)
    /// is taken after this (``adoptSelectionFromApp()``), and wins.
    func followAppEdit() {
        let current = text.wrappedValue
        let seen = selectionText
        guard !TextEdit.sameBytes(seen, current) else { return }
        // The layout of the text the caret is in: the one drawn last — kept
        // aside where a measure has laid the new text out, else still the
        // handler's — unless the editor wrote a text the binding did not keep.
        let drawn = [layoutBeforeAppEdit, cachedLayout].lazy.compactMap(\.self).first {
            TextEdit.sameBytes($0.text, seen)
        }
        layoutBeforeAppEdit = nil
        selectionText = current
        guard let edit = AppTextEdit(from: seen, to: current) else { return }
        let before = drawn ?? EditorLayout(text: seen)
        let after = layout()
        // Read before the caret moves: whether the app's selection is still
        // the one last exchanged with it, so it has not written one of its own.
        let untouched = selectionChannel.map { $0.read(before, seen) == exchangedSelection } ?? false
        carry(through: edit, from: before, to: after)
        if untouched, let selectionChannel {
            // What its binding reads as now, which the editor's carried
            // selection stands in for until the next key writes it back.
            exchangedSelection = selectionChannel.read(after, current)
        }
    }

    /// Carries every holder of a place in the text through `edit`, from the
    /// text `before` laid out to `after`.
    private func carry(through edit: AppTextEdit, from before: EditorLayout, to after: EditorLayout) {
        let caret = before.utf8Offset(of: cursor)
        let anchor = selectionAnchor.map { before.utf8Offset(of: $0) }
        let span = min(caret, anchor ?? caret)..<max(caret, anchor ?? caret)
        let blockSpan = block.flatMap { blockBytes($0, in: before) }
        let placed = edit.placed(around: blockSpan?.bytes ?? span)
        var newCaret: Int
        var newAnchor: Int?
        switch placed.carry(span) {
        case .moved(let moved):
            let delta = moved.lowerBound - span.lowerBound
            (newCaret, newAnchor) = (caret + delta, anchor.map { $0 + delta })
        case .collapsed(let end):
            (newCaret, newAnchor) = (end, nil)
        }
        if let block, let blockSpan {
            switch carry(block, spanning: blockSpan, through: placed, from: before, to: after) {
            case .some(let carried): self.block = carried
            case .none:
                self.block = nil
                newCaret = placed.change.newEnd
            }
        }
        let carriedCaret = after.positions(ofUTF8: [newCaret])[0]
        let caretMoved = carriedCaret != cursor
        cursor = carriedCaret
        selectionAnchor = newAnchor.map { after.positions(ofUTF8: [$0])[0] }
        // The pointer's gestures in progress: carried where the edit leaves
        // their text be, dropped where it took it.
        textDrag = textDrag.flatMap { drag in
            carried(drag.span.start, drag.span.end, through: placed, from: before, to: after).map {
                TextDrag(span: (start: $0.0, end: $0.1), moved: drag.moved)
            }
        }
        multiClickRun = multiClickRun.flatMap { run in
            carried(run.start, run.end, through: placed, from: before, to: after).map {
                (run.granularity, $0.0, $0.1)
            }
        }
        pressAnchor = pressAnchor.map { press in
            switch placed.carry(before.utf8Offset(of: press)..<before.utf8Offset(of: press)) {
            case .moved(let moved): after.positions(ofUTF8: [moved.lowerBound])[0]
            case .collapsed(let end): after.positions(ofUTF8: [end])[0]
            }
        }
        rowStartHead = nil
        if caretMoved { syncDesiredColumn(EditedLines(after.lines)) }
    }

    /// `start` and `end`, a span of `before`, carried through `placed` into
    /// `after`, or `nil` where the edit touched it.
    private func carried(
        _ start: TextEditorPosition, _ end: TextEditorPosition, through placed: AppTextEdit.Placed,
        from before: EditorLayout, to after: EditorLayout
    ) -> (TextEditorPosition, TextEditorPosition)? {
        let span = before.utf8Offset(of: start)..<before.utf8Offset(of: end)
        guard case .moved(let moved) = placed.carry(span) else { return nil }
        let positions = after.positions(ofUTF8: [moved.lowerBound, moved.upperBound])
        return (positions[0], positions[1])
    }

    /// The bytes of `before` a block's lines hold, from its first line's start
    /// to its last line's end, and those lines; `nil` where the editor's rows
    /// cannot be told without the text's styles (``blockGrid(of:)``).
    private func blockBytes(_ block: TextEditorBlock, in before: EditorLayout) -> (bytes: Range<Int>, lines: ClosedRange<Int>)? {
        guard let grid = blockGrid(of: before) else { return nil }
        let last = before.lines.count - 1
        let top = min(grid.line(ofRow: block.rows.lowerBound), last)
        let bottom = min(max(top, grid.line(ofRow: block.rows.upperBound)), last)
        let end = before.utf8Offset(of: TextEditorPosition(line: bottom, column: before.lines[bottom].count))
        return (before.utf8Offset(of: TextEditorPosition(line: top, column: 0))..<end, top...bottom)
    }

    /// `block` carried through `placed`: left where the edit is after its
    /// lines, moved by the rows the edit added or took above them, and `nil`
    /// where it touched them — or changed a line of them, which moves the
    /// columns its rows wrap at.
    private func carry(
        _ block: TextEditorBlock, spanning span: (bytes: Range<Int>, lines: ClosedRange<Int>),
        through placed: AppTextEdit.Placed, from before: EditorLayout, to after: EditorLayout
    ) -> TextEditorBlock? {
        guard case .moved(let moved) = placed.carry(span.bytes) else { return nil }
        // Where its first line starts now: the lines it spans moved by as many
        // as the edit put in or took away above them.
        let shift = after.line(containingUTF8Offset: moved.lowerBound) - span.lines.lowerBound
        let lines = (span.lines.lowerBound + shift)...(span.lines.upperBound + shift)
        guard lines.lowerBound >= 0, lines.upperBound < after.lines.count,
            zip(span.lines, lines).allSatisfy({ after.lines[$1].hasSameBytes(as: before.lines[$0]) }),
            let oldGrid = blockGrid(of: before), let newGrid = blockGrid(of: after)
        else { return nil }
        let rows = newGrid.firstRow(ofLine: lines.lowerBound) - oldGrid.firstRow(ofLine: span.lines.lowerBound)
        var carried = block
        carried.anchor.y += rows
        carried.head.y += rows
        return carried
    }

    /// The grid a block's corners are cells of (``TextEditorBlock``) for
    /// `layout`'s text: its rows as drawn, wrapped or a line each. `nil` in
    /// an editor bound to an `AttributedString`, whose paragraphs' line
    /// heights add rows read from the value, which by now is the edit's.
    private func blockGrid(of layout: EditorLayout) -> BlockGrid? {
        guard attributedSource == nil else { return nil }
        guard let wrapWidth else { return .lines }
        let drawn = hidingGlyph.map { glyph in
            TextEdit.sameBytes(layout.text, text.wrappedValue)
                ? displayLayout() : EditorLayout(text: Self.hiding(layout.text, with: glyph))
        } ?? layout
        return .wrapped(drawn.wrapped(width: wrapWidth, tabWidth: tabWidth))
    }
}

/// The rows of a ``TextEditorBlock``'s grid: an editor's wrapped rows, or,
/// where it scrolls sideways, its lines.
private enum BlockGrid {
    case wrapped(WrappedRows)
    case lines

    func line(ofRow row: Int) -> Int {
        switch self {
        case .wrapped(let rows): rows.location(ofRow: min(max(0, row), max(0, rows.rowCount - 1))).line
        case .lines: max(0, row)
        }
    }

    func firstRow(ofLine line: Int) -> Int {
        switch self {
        case .wrapped(let rows): rows.row(line: line, rowInLine: 0)
        case .lines: line
        }
    }
}
