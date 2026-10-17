//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextEditor+Rows.swift
//
//  The rows a TextEditor draws: a wrapping editor's slices of its lines, a
//  sideways editor's scrolled lines, and the one row renderer both use, with
//  the caret's and the selection's cells. Split from `TextEditor.swift`, which
//  had reached the file-length limit.
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitFoundation

extension _TextEditorCore {
    /// Every visible row of a wrapping editor: each a slice of its line, from
    /// its row's first character — tab stops counted from there — drawn by
    /// the same row renderer the sideways editor uses, with nothing scrolled.
    ///
    /// A run of spaces may hang past the last cell; what starts past it is not
    /// drawn, and a caret in such a run sits on the last cell
    /// (``SoftWrapLayout/column(of:inRow:)``).
    func renderWrappedRows(
        _ rows: WrappedRows, lines: [[Character]], handler: TextEditorHandler, height: Int,
        tabWidth: TabWidth, caret: RowCaret?, styling: RowStyling
    ) -> (lines: [String], claims: [OpacityRegion], caret: AnimatedCellRun?) {
        var output: [String] = []
        var claims: [OpacityRegion] = []
        var caretRun: AnimatedCellRun?
        output.reserveCapacity(height)
        let top = handler.topRow(in: rows)
        let caretRow = handler.caretRow(in: rows)
        var (line, rowInLine) = rows.location(ofRow: top)
        for screenRow in 0..<height {
            let rendered: RenderedRow
            if top + screenRow < rows.rowCount {
                let layout = rows.lines[line]
                let span = layout.rows[rowInLine]
                // Only what starts inside the row: a hanging run may run on.
                var (end, cell) = (span.start, 0)
                while end < span.end, cell < rows.width {
                    cell += layout.cellWidths[end]
                    end += 1
                }
                let selection: Range<Int>? =
                    caret == nil
                    ? nil
                    : handler.selectedColumns(inLine: line, lineLength: lines[line].count).flatMap { selected in
                        let lower = max(selected.lowerBound, span.start)
                        let upper = min(selected.upperBound, end)
                        guard lower < upper else { return nil }
                        return layout.cells(inRow: rowInLine, before: lower)
                            ..< layout.cells(inRow: rowInLine, before: upper)
                    }
                rendered = styledRow(
                    Array(lines[line][span.start..<end]), tabWidth: tabWidth, scrollColumn: 0, width: rows.width,
                    caret: top + screenRow == caretRow && handler.selectionRange == nil ? caret : nil,
                    selection: selection, styling: styling)
                // On to the next row: the rest of this line's, then the next line's.
                if rowInLine + 1 < layout.rows.count {
                    rowInLine += 1
                } else {
                    (line, rowInLine) = (line + 1, 0)
                }
            } else {
                rendered = emptyRow(width: rows.width, background: styling.background)
            }
            output.append(rendered.line)
            for claim in rendered.claims { claims.appendCoalescing(claim.shifted(byX: 0, y: screenRow)) }
            caretRun = caretRun ?? rendered.caret?.shifted(byX: 0, y: screenRow)
        }
        return (output, claims, caretRun)
    }

    /// Every visible row: its line, the claims its colours owe — already in the
    /// buffer's rows — and the caret's run, if it landed on one. `caret` is non-nil
    /// exactly when the editor is focused: the caret and the selection show only then.
    ///
    /// Its own function for the reason `appendScrollbar` is: `renderToBuffer` sits at
    /// the body-length limit, and this block reads the handler's window and writes
    /// nothing back.
    func renderRows(
        _ displayLines: [[Character]], handler: TextEditorHandler, width: Int, height: Int,
        tabWidth: TabWidth, caret: RowCaret?, styling: RowStyling
    ) -> (lines: [String], claims: [OpacityRegion], caret: AnimatedCellRun?) {
        var lines: [String] = []
        var claims: [OpacityRegion] = []
        var caretRun: AnimatedCellRun?
        lines.reserveCapacity(height)
        for row in 0..<height {
            let lineIndex = handler.scrollLine + row
            let rendered: RenderedRow
            if lineIndex < displayLines.count {
                let lineChars = displayLines[lineIndex]
                // The handler's selection is character-indexed; the row is painted
                // in display cells, so convert the bounds (a char range maps to a
                // contiguous display range — expansion is monotonic — and a
                // selected tab highlights its whole span, as in any editor).
                let selection: Range<Int>? =
                    caret == nil
                    ? nil
                    : handler.selectedColumns(inLine: lineIndex, lineLength: lineChars.count).map {
                        TabLayout.displayColumn(ofCharIndex: $0.lowerBound, in: lineChars, tabWidth: tabWidth)
                            ..< TabLayout.displayColumn(ofCharIndex: $0.upperBound, in: lineChars, tabWidth: tabWidth)
                    }
                rendered = styledRow(
                    lineChars, tabWidth: tabWidth, scrollColumn: handler.scrollColumn, width: width,
                    // No caret while text is selected, as on a Mac: the
                    // selection is what typing replaces (see the field's
                    // `buildTextWithCursor`).
                    caret: lineIndex == handler.cursorLine && handler.selectionRange == nil ? caret : nil,
                    selection: selection, styling: styling)
            } else {
                rendered = emptyRow(width: width, background: styling.background)
            }
            lines.append(rendered.line)
            // A row states its claims, and its caret, in its own frame: only the loop
            // knows which row it is — the VIEWPORT row, not the line index. The
            // downward merge stacks a plain editor's identical rows into one rectangle.
            for claim in rendered.claims { claims.appendCoalescing(claim.shifted(byX: 0, y: row)) }
            caretRun = caretRun ?? rendered.caret?.shifted(byX: 0, y: row)
        }
        return (lines, claims, caretRun)
    }

    /// A blank row filled to `width`, painted with the field background, and owing
    /// that field's alpha — a claim with no ink, since nothing is drawn here.
    ///
    /// Through `ClaimingRow` rather than the row's accumulator: a blank row is one run
    /// with no caret, which is that type's shape, and the accumulator would have to
    /// state an ink — and emit a foreground code — just to open.
    func emptyRow(width: Int, background: Color?) -> RenderedRow {
        guard let background else { return RenderedRow(line: String(asciiSpaces(width))) }
        var row = ClaimingRow()
        row.append(String(asciiSpaces(width)), cells: width, ink: nil, field: background)
        return RenderedRow(line: row.text, claims: row.claims)
    }

    // MARK: - Helpers

    /// Renders one visible row: the line clipped to the cell window
    /// `[scrollColumn, +width)`, padded to exactly `width` cells. Selected
    /// spans (display columns in `selection`) get a palette highlight and the
    /// cursor cell a caret — both set explicit palette colours rather than
    /// SGR 7 reverse-video (which inverts the terminal's *default* colours
    /// and collapses to dark-on-dark on a mid-tone palette). Consecutive
    /// cells that share a colour coalesce into one ANSI run, and each run states
    /// the claim its colours owe.
    ///
    /// The walk is in terminal CELLS over the line's characters — the same
    /// model as ``TextFieldContentRenderer``: a tab spans to its stop, a wide
    /// character (emoji, CJK) spans its real width, and an element straddling
    /// either window edge renders as spaces for its visible cells (it can't
    /// be shown half), so the row is always exactly `width` cells.
    /// The caret as one row sees it: its display column plus every frame of
    /// its animation. `nil` for rows the caret isn't on.
    struct RowCaret {
        let column: Int
        let cycle: Cycle

        /// The shape and the whole animation, resolved once per render and
        /// shared by every row (only one of which ever uses it).
        struct Cycle {
            let shape: TextCursorStyle.Shape
            let cursor: TextFieldContentRenderer.CursorCycle
            /// What the frames paint with, from `caretSetup`: every ink is spent, so
            /// the caret's cells owe no ink claim in any frame.
            let colors: TextFieldContentRenderer.CaretColors
        }
    }

    /// A row's line, the caret run it left behind, and the claims its colours owe —
    /// what ``TextFieldContentRenderer/FieldContent`` carries, for the same reason:
    /// the row knows where in itself its cells are, and only its caller knows where
    /// the row is.
    struct RenderedRow {
        let line: String
        let caret: AnimatedCellRun?
        /// The cells owing a blend, in the ROW's frame — row 0, column 0 the first
        /// content cell — shifted into the buffer by the caller, as the caret is.
        let claims: [OpacityRegion]

        init(line: String, caret: AnimatedCellRun? = nil, claims: [OpacityRegion] = []) {
            (self.line, self.caret, self.claims) = (line, caret, claims)
        }
    }

    /// The frame-level colours every row paints with — the well, the text, and the
    /// selection's pair — derived once per render: the pair used to be re-derived for
    /// every row, contrast floor and all.
    ///
    /// Resolved here because the bytes no longer pass through
    /// `TextStyle.resolved(with:)`: `RunAccumulator` hands its colours to `colorize`
    /// as they are, and a custom palette may state a slot semantically.
    struct RowStyling {
        let background: Color?
        let text: Color
        let selection: FieldSelectionStyle

        @MainActor
        init(palette: any Palette, isDisabled: Bool, background: Color?) {
            self.background = background
            // A disabled editor's text CLAIMS its tint's alpha, as a disabled
            // TextField's does — not §31.3's spend, which is the slider's own
            // dimming composite; the editor has no composite to spend through.
            let ink = (isDisabled ? palette.foregroundTertiary : palette.foreground)
                .resolve(with: palette)
            text = ink
            // The row's own ink goes with the question: a selection whose highlight
            // cannot be measured reverses the CELL rather than tinting it (§87).
            selection = TextFieldContentRenderer.selectionColors(
                palette: palette, background: background, ink: ink
            ).resolved(with: palette)
        }
    }

    func styledRow(
        _ chars: [Character], tabWidth: TabWidth, scrollColumn: Int, width: Int,
        caret: RowCaret?, selection: Range<Int>?, styling: RowStyling
    ) -> RenderedRow {
        let background = styling.background
        let textForeground = styling.text
        // Not `selection`, which is this row's selected COLUMNS.
        let selectionStyle = styling.selection
        let windowStart = scrollColumn
        let windowEnd = scrollColumn + width

        // Walks the line in cell space, clipping each element against the
        // window: fully inside → emitted whole; straddling an edge → spaces
        // for its visible cells; outside → skipped.
        var cellX = 0
        var outputCells = 0
        // A run's bytes and its claim, written together — the accumulator a focused
        // TextField's content uses, for §30.1's reason: a row's cells genuinely
        // differ (the highlight's field is opaque; the well's and the text's are the
        // palette's), and run boundaries already are colour boundaries. Its column
        // is `outputCells`, which holds the next cell's column wherever a run opens
        // or flushes — mid-straddle included, where `outputCells` advances after.
        var runs = TextFieldContentRenderer.RunAccumulator(ink: textForeground, field: background)
        func emit(_ character: Character, foreground: Color, background: Color?, reversed: Bool = false) {
            runs.append(character, ink: foreground, field: background, reversed: reversed, atColumn: outputCells)
        }
        func emitClipped(_ character: Character, cells: Int, foreground: Color, background: Color?, reversed: Bool = false) {
            let start = cellX
            let end = cellX + cells
            cellX = end
            guard end > windowStart, start < windowEnd else { return }
            if start >= windowStart, end <= windowEnd {
                emit(character, foreground: foreground, background: background, reversed: reversed)
                outputCells += cells
            } else {
                let visible = min(end, windowEnd) - max(start, windowStart)
                for _ in 0..<visible {
                    emit(" ", foreground: foreground, background: background, reversed: reversed)
                }
                outputCells += visible
            }
        }

        // The caret's cells are drawn by the very code TextField's are
        // (`TextFieldContentRenderer.caretFrames`), so one `.textCursor(_:)`
        // setting cannot mean two things — and every frame is built, not just
        // this tick's, so the cells can be handed to the run loop.
        //
        // They are emitted as their own self-contained styled chunk, including
        // on a blink-OFF frame where they used to coalesce with their
        // neighbours: a frame spliced in later would otherwise take its colour
        // from whatever escape happened to precede it in the line. Costs one
        // escape pair; buys the whole cheap animation path. See
        // ``AnimatedCellRun``.
        var caretRun: AnimatedCellRun?

        func emitCaret(
            _ underlying: Character, cells: Int, cycle: RowCaret.Cycle, isSelected: Bool
        ) {
            // A caret straddling the window edge falls back to the ordinary
            // clipped character rather than leaving a run describing cells that
            // are not on screen — `followCursor` keeps it inside, and a run
            // that outlived its cells would repaint over whatever took them.
            guard cellX >= windowStart, cellX + cells <= windowEnd else {
                emitClipped(
                    underlying, cells: cells, foreground: isSelected ? selectionStyle.foreground : textForeground,
                    background: isSelected ? selectionStyle.background : background,
                    reversed: isSelected && selectionStyle.isReversed)
                return
            }
            let drawn = TextFieldContentRenderer.caretFrames(
                cycle.cursor, shape: cycle.shape, cells: cells,
                underlying: underlying, isSelected: isSelected, colors: cycle.colors)
            // Out of band, and claiming its FIELD per frame. Every frame's ink is spent,
            // so "no ink claim" is true of them all; the field is not — a blink-off
            // frame shows the well and a block frame shows the caret's own opaque
            // colour — so it rides on the run, one statement per frame (§61.2).
            runs.flush(atColumn: outputCells)
            runs.appendVerbatim(drawn.frames[drawn.drawnIndex])
            if cycle.cursor.isAnimating {
                caretRun = AnimatedCellRun(
                    offsetX: outputCells, offsetY: 0, width: cells, frames: drawn.frames,
                    frameTicks: cycle.cursor.timing.frameTicks,
                    clock: cycle.cursor.timing.clock, alpha: drawn.alpha)
            }
            cellX += cells
            outputCells += cells
        }

        for character in chars {
            let cells = TabLayout.advance(from: cellX, over: character, tabWidth: tabWidth) - cellX
            let isSelected = selection.map { $0.contains(cellX) } ?? false
            // The caret sits at a character's start cell (its column is
            // derived from a character index), so at most one element matches.
            // A blink-OFF frame comes through here too — it is a frame of the
            // cycle showing the character unadorned, not an absent caret.
            if let caret, caret.column == cellX {
                if character == "\t" {
                    // Caret on a tab: the caret occupies the stop run's first
                    // cell, and the rest of the run pads — cell by cell, as an
                    // uncareted tab's run does. `emitClipped` draws ONE character
                    // however many cells it is told, which is right for a wide
                    // glyph and was wrong here: the rest of a tab three or more
                    // cells wide came out as one space, so the row ran short and
                    // whatever was drawn after it, a scroll bar included, landed
                    // early.
                    emitCaret(" ", cells: 1, cycle: caret.cycle, isSelected: isSelected)
                    for _ in 0..<max(0, cells - 1) {
                        emitClipped(
                            " ", cells: 1, foreground: isSelected ? selectionStyle.foreground : textForeground,
                            background: isSelected ? selectionStyle.background : background,
                            reversed: isSelected && selectionStyle.isReversed)
                    }
                } else {
                    emitCaret(character, cells: cells, cycle: caret.cycle, isSelected: isSelected)
                }
                continue
            }
            let foreground = isSelected ? selectionStyle.foreground : textForeground
            let cellBackground = isSelected ? selectionStyle.background : background
            let reversed = isSelected && selectionStyle.isReversed
            if character == "\t" {
                // A tab is its stop run of spaces — emitted cell by cell so
                // the window clips it naturally (and a selected tab
                // highlights its whole span, as in any editor).
                for _ in 0..<cells {
                    emitClipped(" ", cells: 1, foreground: foreground, background: cellBackground, reversed: reversed)
                }
            } else {
                emitClipped(character, cells: cells, foreground: foreground, background: cellBackground, reversed: reversed)
            }
        }
        // The caret past the last character sits on its own cell.
        if let caret, caret.column == cellX {
            emitCaret(" ", cells: 1, cycle: caret.cycle, isSelected: false)
        }
        // Pad to exactly `width` cells.
        while outputCells < width {
            emit(" ", foreground: textForeground, background: background)
            outputCells += 1
        }
        runs.flush(atColumn: outputCells)
        return RenderedRow(line: runs.line, caret: caretRun, claims: runs.claims)
    }
}
