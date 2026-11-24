//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorRowReference.swift
//
//  The row walk a TextEditor drew every row with before H-88 (main at
//  4cfb53cd4), kept as it was, as the oracle the rows drawn from a line's
//  sampled cells are compared with (`TextEditorSidewaysRowTests`): from the
//  line's first character to its last, whatever the window.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
@testable import TUIFoundation
@testable import TUITextInput

extension _TextEditorCore {
    /// `styledRow` as it was before H-88: every character of `chars` walked,
    /// from the first, those outside the window skipped only as they are
    /// drawn. A frozen copy, not a call: what the rows drawn now must match.
    /// Change it only with a deliberate change to what a row draws.
    func referenceStyledRow(
        _ chars: Slice<TextCharacters>, tabWidth: TabWidth, scrollColumn: Int, leadingCells: Int = 0, width: Int,
        caret: RowCaret?, selection: Range<Int>?, matches: [Range<Int>] = [], styles: [EditorStyledRun] = [],
        styling: RowStyling
    ) -> RenderedRow {
        // Disabled, the runs fade with the rest (``RowStyling/RunFade``).
        let styles = styling.runFade.map { fade in styles.map { fade($0) } } ?? styles
        // `selectionStyle`, not `selection`, which is this row's selected COLUMNS.
        let (background, textForeground, selectionStyle) = (styling.background, styling.text, styling.selection)
        // In the line's own cells: an aligned line starts `leadingCells` in.
        let (windowStart, windowEnd) = (scrollColumn - leadingCells, scrollColumn - leadingCells + width)

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
        var runs = TextFieldContentRenderer.RunAccumulator(ink: textForeground, field: background, introducers: styling.introducers)
        // The decoration of the character being drawn, for every cell it takes.
        var decoration: CellDecoration?
        func emit(_ character: Character, foreground: Color, background: Color?, reversed: Bool = false) {
            runs.append(character, ink: foreground, field: background, reversed: reversed, decoration: decoration, atColumn: outputCells)
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
                cycle.cursor, shape: cycle.shape, cells: cells, underlying: underlying, colors: cycle.colors)
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

        // The blank cells in front of an aligned line, as far as they show.
        let padding = min(width, max(0, -windowStart))
        for _ in 0..<padding { emit(" ", foreground: textForeground, background: background) }
        outputCells += padding

        // The style run of the character being drawn, found in one pass.
        var styleCursor = 0
        let line = chars.base
        for (index, position) in chars.indices.enumerated() {
            let (cells, shown, isTab) = Self.glyph(at: position, of: line, column: cellX, tabWidth: tabWidth)
            let isSelected = selection.map { $0.contains(cellX) } ?? false
            let styled = styles.isEmpty ? nil : EditorStyledRun.run(at: index, in: styles, cursor: &styleCursor)
            decoration = styled?.decoration
            // The caret sits at a character's start cell (its column is
            // derived from a character index), so at most one element matches.
            // A blink-OFF frame comes through here too — it is a frame of the
            // cycle showing the character unadorned, not an absent caret.
            if let caret, caret.column == cellX {
                if isTab {
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
                    emitCaret(shown, cells: cells, cycle: caret.cycle, isSelected: isSelected)
                }
                continue
            }
            let foreground = isSelected ? selectionStyle.foreground : styled?.foreground ?? textForeground
            // A find match the selection is not on is tinted (decisions B81).
            let isMatched = !isSelected && styling.match != nil && matches.contains { $0.contains(cellX) }
            let cellBackground =
                isSelected ? selectionStyle.background : isMatched ? styling.match : styled?.background ?? background
            let reversed = isSelected && selectionStyle.isReversed
            if isTab {
                // A tab is its stop run of spaces — emitted cell by cell so
                // the window clips it naturally (and a selected tab
                // highlights its whole span, as in any editor).
                for _ in 0..<cells {
                    emitClipped(" ", cells: 1, foreground: foreground, background: cellBackground, reversed: reversed)
                }
            } else {
                // A control character the text holds — an app's binding can
                // hold anything, past what a paste lets in — is drawn as U+FFFD,
                // as a field draws it: an ESC sent as it is would be obeyed, a
                // log's \u{1B}[2J clearing the screen. So is a character with no
                // width of its own (a ZWSP, a BOM): it was counted one cell, and
                // written raw the terminal gave it none (H-48).
                emitClipped(shown, cells: cells, foreground: foreground, background: cellBackground, reversed: reversed)
            }
        }
        decoration = nil
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
