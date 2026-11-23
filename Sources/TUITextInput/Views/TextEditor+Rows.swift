//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditor+Rows.swift
//
//  The rows a TextEditor draws: a wrapping editor's slices of its lines, a
//  sideways editor's scrolled lines, and the one row renderer both use, with
//  the caret's and the selection's cells. Split from `TextEditor.swift`, which
//  had reached the file-length limit.
//
//  Created by LAYERED.work
//  License: MIT

import TUIFoundation

extension _TextEditorCore {
    /// Every visible row of a wrapping editor: each a slice of its line, from
    /// its row's first character — tab stops counted from there — drawn by
    /// the same row renderer the sideways editor uses, with nothing scrolled.
    ///
    /// A run of spaces may hang past the last cell; what starts past it is not
    /// drawn, and a caret in such a run sits on the last cell
    /// (``SoftWrapLayout/column(of:inRow:)``). A paragraph's line height's
    /// blank rows (``WrappedRows``) are drawn empty, in the well's field.
    func renderWrappedRows(
        _ rows: WrappedRows, lines: [TextCharacters], handler: TextEditorHandler, height: Int,
        tabWidth: TabWidth, caret: RowCaret?, styling: RowStyling
    ) -> (lines: [String], claims: [OpacityRegion], caret: AnimatedCellRun?) {
        var output: [String] = []
        var claims: [OpacityRegion] = []
        var caretRun: AnimatedCellRun?
        output.reserveCapacity(height)
        let top = handler.topRow(in: rows)
        let caretRow = handler.caretRow(in: rows)
        let showsSelection = Self.showsSelection(caret: caret, handler: handler)
        var place = rows.placement(ofRow: top)
        for screenRow in 0..<height {
            let rendered: RenderedRow
            let (line, rowInLine) = (place.line, place.rowInLine)
            if top + screenRow < rows.rowCount, place.blank > 0 {
                rendered = emptyRow(width: rows.width, background: styling.background)
                place = rows.placement(after: place)
            } else if top + screenRow < rows.rowCount {
                let layout = rows.lines[line]
                let span = layout.rows[rowInLine]
                // Only what starts inside the row: a hanging run may run on.
                var (end, cell) = (span.start, 0)
                while end < span.end, cell < rows.width {
                    cell += layout.cellWidth(at: end)
                    end += 1
                }
                // The blank cells its paragraph's alignment puts in front.
                let aligned = handler.alignmentCells(line: line, rowInLine: rowInLine, in: rows)
                // A block's columns are the grid's, this row's cells after them.
                let selection: Range<Int>? =
                    !showsSelection
                    ? nil
                    : handler.blockCells(onRow: top + screenRow).map { ($0.lowerBound - aligned)..<($0.upperBound - aligned) }
                        ?? handler.selectedColumns(inLine: line, lineLength: lines[line].count).flatMap { selected in
                            let lower = max(selected.lowerBound, span.start)
                            let upper = min(selected.upperBound, end)
                            guard lower < upper else { return nil }
                            return layout.cells(inRow: rowInLine, before: lower)
                                ..< layout.cells(inRow: rowInLine, before: upper)
                        }
                // The find bar's matches on this row, as its cells.
                let matches = handler.findColumns(ofLine: line).compactMap { matched -> Range<Int>? in
                    let lower = max(matched.lowerBound, span.start)
                    let upper = min(matched.upperBound, end)
                    guard lower < upper else { return nil }
                    return layout.cells(inRow: rowInLine, before: lower) ..< layout.cells(inRow: rowInLine, before: upper)
                }
                // The line's styles, in this row's columns.
                let styles = EditorStyledRun.clipping(handler.styles(ofLine: line), toColumns: span.start, end)
                rendered = styledRow(
                    lines[line][span.start..<end], tabWidth: tabWidth, scrollColumn: 0, leadingCells: aligned,
                    width: rows.width,
                    caret: top + screenRow == caretRow && handler.selectionRange == nil && handler.block == nil
                        ? caret : nil,
                    selection: selection, matches: matches, styles: styles, styling: styling)
                // On to the next row: this one's blank rows, the rest of this
                // line's, then the next line's.
                place = rows.placement(after: place)
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
    /// exactly when the editor is focused: the caret shows only then, and the
    /// selection too unless the find bar is up (``showsSelection(caret:handler:)``).
    ///
    /// Its own function for the reason `appendScrollbar` is: `renderToBuffer` sits at
    /// the body-length limit, and this block reads the handler's window and writes
    /// nothing back.
    /// Whether the rows draw the selection: while the editor is focused, and
    /// while the find bar has matches up, whose current one is the selection —
    /// the bar has the focus then, and macOS's editor keeps its selection drawn
    /// under its find bar the same way.
    static func showsSelection(caret: RowCaret?, handler: TextEditorHandler) -> Bool {
        caret != nil || handler.marks.hasFindMatches
    }

    func renderRows(
        _ displayLines: [TextCharacters], handler: TextEditorHandler, width: Int, height: Int,
        tabWidth: TabWidth, caret: RowCaret?, styling: RowStyling
    ) -> (lines: [String], claims: [OpacityRegion], caret: AnimatedCellRun?) {
        var lines: [String] = []
        var claims: [OpacityRegion] = []
        var caretRun: AnimatedCellRun?
        lines.reserveCapacity(height)
        let showsSelection = Self.showsSelection(caret: caret, handler: handler)
        // Each line one row, a paragraph's line height's blank rows after it.
        let spaced = handler.sidewaysRows()
        let top = handler.sidewaysTopRow(in: spaced)
        for row in 0..<height {
            let (lineIndex, blank) = spaced.placement(ofRow: top + row)
            let rendered: RenderedRow
            if top + row < spaced.rowCount, blank > 0 {
                rendered = emptyRow(width: width, background: styling.background)
            } else if top + row < spaced.rowCount, lineIndex < displayLines.count {
                let lineChars = displayLines[lineIndex]
                // The blank cells its paragraph's alignment puts in front.
                let aligned = handler.alignmentCells(ofLine: lineIndex, characters: lineChars)
                // The handler's selection is character-indexed; the row is painted
                // in display cells, so convert the bounds (a char range maps to a
                // contiguous display range — expansion is monotonic — and a
                // selected tab highlights its whole span, as in any editor).
                // A block's columns are the grid's, this line's after them.
                let selection: Range<Int>? =
                    !showsSelection
                    ? nil
                    : handler.blockCells(onRow: top + row).map { ($0.lowerBound - aligned)..<($0.upperBound - aligned) }
                        ?? handler.selectedColumns(inLine: lineIndex, lineLength: lineChars.count).map {
                            TabLayout.displayColumn(ofCharIndex: $0.lowerBound, in: lineChars, tabWidth: tabWidth)
                                ..< TabLayout.displayColumn(ofCharIndex: $0.upperBound, in: lineChars, tabWidth: tabWidth)
                        }
                let matches = handler.findColumns(ofLine: lineIndex).map {
                    TabLayout.displayColumn(ofCharIndex: $0.lowerBound, in: lineChars, tabWidth: tabWidth)
                        ..< TabLayout.displayColumn(ofCharIndex: $0.upperBound, in: lineChars, tabWidth: tabWidth)
                }
                rendered = styledRow(
                    lineChars[...], tabWidth: tabWidth, scrollColumn: handler.scrollColumn, leadingCells: aligned,
                    width: width,
                    // No caret while text is selected, as on a Mac: the
                    // selection is what typing replaces (see the field's
                    // `buildTextWithCursor`).
                    caret: lineIndex == handler.cursorLine && handler.selectionRange == nil && handler.block == nil
                        ? caret : nil,
                    selection: selection, matches: matches, styles: handler.styles(ofLine: lineIndex),
                    styling: styling)
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
        /// The ink stated for the text, enabled, or `nil` for the palette's.
        let stated: Color?
        let selection: FieldSelectionStyle
        /// The field a find match is tinted with: the selection's, a third of the
        /// way over the well — a match that is not the current one, marked
        /// fainter than the selection, as macOS's find bar marks them. `nil`
        /// where the selection is a reversal, which has no colour to fade.
        let match: Color?
        /// How a disabled editor fades its lines' own styles, or `nil` while it
        /// is enabled, where the runs are drawn as they are and cost nothing more.
        let runFade: RunFade?
        /// Each look's introducer, derived once for the frame's runs
        /// (B-ATTRED-44).
        let introducers = RunIntroducers()

        /// A disabled editor fades everything it draws, its runs' colours too
        /// (the owner's ruling A-DISED-1, 2026-11-19, a deliberate deviation:
        /// SwiftUI's disabled TextEditor fades nothing). Its plain text is in
        /// the tertiary tier; a run keeps its hue, faded toward the page by
        /// ``ViewConstants/disabledForeground`` — the expression a disabled
        /// slider fades its accent track by, and how macOS's disabled
        /// TextField fades a stated red to a paler red rather than a grey. So
        /// highlighted code stays legible as code, and no run reads as live.
        ///
        /// Where a 16- or 256-colour terminal rounds a run's faded colour to
        /// the entry it draws that colour in enabled, the fade says nothing and
        /// the run would look live: the fade notes it (``drawsAsLive``) and the
        /// whole editor is drawn faint, as where its tertiary tier rounds to its
        /// enabled ink (`FrameBuffer.fadedTextInput(if:text:runsDrawAsLive:context:)`).
        /// A class so that every row a frame draws through the one fade can say
        /// so; a new one each frame, and none while enabled.
        @MainActor
        final class RunFade {
            /// What the runs fade toward: the page a disabled editor, which
            /// draws no well, is drawn on.
            let ground: Color
            let palette: any Palette
            /// Whether a colour of a run faded this frame draws, at the
            /// terminal's depth, as it does enabled
            /// (`Color.disabledFadeDrawsAsItself(over:)`).
            private(set) var drawsAsLive = false

            init(ground: Color, palette: any Palette) {
                (self.ground, self.palette) = (ground, palette)
            }

            /// `run` with its ink, its field and its lines' colours faded.
            func callAsFunction(_ run: EditorStyledRun) -> EditorStyledRun {
                run.mappingColors {
                    let stated = $0.resolve(with: palette)
                    if !drawsAsLive, stated.disabledFadeDrawsAsItself(over: ground) { drawsAsLive = true }
                    return stated.opacity(ViewConstants.disabledForeground, over: ground)
                }
            }
        }

        /// The colours an editor drawn in `environment` paints with.
        ///
        /// The text takes the `.foregroundStyle(_:)` in force, as SwiftUI's
        /// TextEditor's does: one colour, a ramp's representative (a ramp is not
        /// laid across an editor's rows). A run's own colour, in an attributed
        /// editor, wins over it, as in a `Text` of the value; the selection, the
        /// caret and a find match derive from it as a TextField's do from its
        /// entered text's ink. Disabled, the runs fade too (``RunFade``).
        @MainActor
        init(in environment: EnvironmentValues, isDisabled: Bool, background: Color?) {
            self.init(
                palette: environment.palette, isDisabled: isDisabled, background: background,
                stated: environment.statedForegroundStyle?.representative)
        }

        /// - Parameter stated: The ink stated for the text, or `nil` for the
        ///   palette's.
        @MainActor
        init(palette: any Palette, isDisabled: Bool, background: Color?, stated: Color? = nil) {
            self.background = background
            self.stated = stated
            runFade =
                isDisabled
                ? RunFade(ground: (background ?? palette.background).resolve(with: palette), palette: palette) : nil
            // A disabled editor's text CLAIMS its tint's alpha, as a disabled
            // TextField's does — not §31.3's spend, which is the slider's own
            // dimming composite; the editor has no composite to spend through.
            // Disabled, the tertiary tier wins over a stated ink, as a disabled
            // TextField's entered text does.
            let ink = (isDisabled ? palette.foregroundTertiary : stated ?? palette.foreground)
                .resolve(with: palette)
            text = ink
            // The row's own ink goes with the question: a selection whose highlight
            // cannot be measured reverses the CELL rather than tinting it (§87).
            selection = TextFieldContentRenderer.selectionColors(
                palette: palette, background: background, ink: ink
            ).resolved(with: palette)
            match =
                selection.isReversed
                ? nil
                : selection.background.opacity(0.35, over: (background ?? palette.background).resolve(with: palette))
        }
    }

    /// The cells the character at `position` of `line` takes from `column`,
    /// the glyph a row draws for it, and whether it is a tab. A character of
    /// one ASCII byte — a tab is one — is told from its byte, without the
    /// character compared or its properties looked up, which were most of a
    /// row's cost to draw (EDMEM-2).
    static func glyph(
        at position: Int, of line: TextCharacters, column: Int, tabWidth: TabWidth
    ) -> (cells: Int, shown: Character, isTab: Bool) {
        if let byte = line.asciiByte(at: position) {
            return (
                TabLayout.advance(from: column, overASCII: byte, tabWidth: tabWidth) - column,
                TextFieldHandler.displayCharacter(ascii: byte), byte == 0x09
            )
        }
        let character = line[position]
        return (
            TabLayout.advance(from: column, over: character, tabWidth: tabWidth) - column,
            TextFieldHandler.displayCharacter(character), false
        )
    }

    /// `styles` are the line's own (``EditorStyledRun``), with any
    /// highlighting already drawn over them
    /// (``TextEditorHandler/highlightedStyles(ofLine:in:)``), in the columns of
    /// `chars`, ascending: a run's colours give way to the selection's, and
    /// its field to a find match's; its decoration is drawn under both. So the
    /// order is B-ATTRED-8's: the selection, the find bar's tint,
    /// highlighting, the line's own attributes, the editor's style.
    ///
    /// `leadingCells` are blank cells the line is drawn after, its
    /// paragraph's alignment (A-ATTRED-3): scrolled with it, in the well's
    /// field. The caret's, the selection's and the matches' columns stay the
    /// line's own, and so do its tab stops.
    func styledRow(
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
                // log's \u{1B}[2J clearing the screen.
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
