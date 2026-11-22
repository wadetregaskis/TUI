//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditor+Pulled.swift
//
//  SCROLL-FIT's pull (design P4), for a `TextEditor` in a scroll view's
//  content: an editor that a column pulls where it stands is its text's
//  height — its
//  rows at the width it is given, wrapped or not — and draws only the rows
//  the scroll view shows. It is a lines leaf (B-SCROLLFIT-12): its rows are
//  its own, laid out already (the layout keeps them at each width), so where
//  each falls is arithmetic, and the band is read as `List`'s one-line rows
//  are (`PulledBand.swift`). It draws no bar and takes no wheel tick, the
//  scroll view around it scrolling it; and it marks its caret's row
//  (`FrameBuffer.markPulledControl`), so that the scroll view keeps the caret
//  in sight as it moves and as text is typed.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension _TextEditorCore {
    /// The editor's rows when a column pulls it, at `width`, or `nil` when it
    /// is drawn as before: outside scroll content, given a
    /// height, or below a container that does not pull.
    private func pulledRowCount(width: Int, context: RenderContext) -> Int? {
        guard isPulled(context: context) else { return nil }
        return contentRowCount(width: width, context: context)
    }

    /// Whether the editor is pulled, filing it as a view that bands its own
    /// rows if so — so the column above hands it a request — and withdrawing
    /// it if not. Its measure is then its rows' height.
    func notePulled(context: RenderContext) -> Bool {
        let pulled = isPulled(context: context)
        context.notePulledBand(pulled)
        return pulled
    }

    /// Whether the editor, not pulled, is asked how tall it would be with
    /// nothing to stop it — no height proposed, offered the natural-extent
    /// ladder's budget, given none: `.fixedSize` outside a scroll view, or
    /// scroll content below a container that does not pull. It is then its
    /// rows' height, drawn whole, where it was the budget or the height it was
    /// offered, whichever was less: 4,096 lines in a scroll view, 23 under
    /// `.fixedSize` on a 24-line screen (SCROLL-FIT P7).
    func answersNaturalHeight(proposal: ProposedViewSize, context: RenderContext) -> Bool {
        proposal.height == nil && !context.hasExplicitHeight
            && isNaturalExtentBudget(context.availableHeight)
    }

    /// Whether a column pulls the editor (in scroll content,
    /// given no height, every container above it a column).
    private func isPulled(context: RenderContext) -> Bool {
        context.scrollContentOriginDepth != 0
            && !context.hasExplicitHeight && context.isPulledWhereItStands
    }

    /// The band of a pulled editor's rows a request asks for, drawn as the
    /// editor draws itself framed to those rows from the first of them, and
    /// answered back; with no request, its top, no further than a viewport;
    /// measured by drawing, a footprint of its rows' height. `nil` when the
    /// editor is not pulled.
    func renderPulled(context: RenderContext) -> FrameBuffer? {
        let width = max(1, context.availableWidth)
        guard let total = pulledRowCount(width: width, context: context) else { return nil }
        // Filed from the render too: a container that measures by drawing (a
        // context menu's) never asks the editor's measure.
        context.notePulledBand(true)
        // Measured by drawing, its size is all a measure reads: its rows'
        // height, none of them drawn.
        if context.isMeasuring { return FrameBuffer(footprintWidth: width, height: total) }
        let handler = existingHandler(context: context)
        let request = context.pulledBandRequest()
        let band = request?.band(total: total) { seek in
            // A focus reveal: the caret's row. A key names nothing in an
            // editor.
            guard seek.focusID != nil, let handler else { return nil }
            return (caretRow(handler, width: width, context: context), 1)
        }
        let lines: Range<Int>
        if let band {
            lines = band.lines
        } else {
            let reach = context.environment.scrollViewportSize?.height ?? context.availableHeight
            lines = 0..<max(1, min(total, reach))
        }
        var editor = self
        editor.pulledTop = lines.lowerBound
        var framed = context
        framed.availableHeight = lines.count
        var buffer = editor.renderToBuffer(context: framed)
        if let handler = existingHandler(context: context), !context.isMeasuring {
            // Its caret's row, where the band misses it, for the scroll view
            // to reveal as the caret moves.
            buffer.markPulledControl(
                focusID: handler.focusID, band: lines, total: total,
                cursorLine: caretRow(handler, width: width, context: context))
            // Page Up and Page Down move by the scroll view's viewport, not
            // the band's rows (B-SCROLLFIT-5).
            if let request { handler.viewportHeight = max(1, request.viewportHeight) }
        }
        if let band { request?.answer(band) }
        return buffer
    }

    /// The window a pulled editor draws from: its rows from `top`, at the
    /// whole width (it draws no bar), the caret followed across but not down
    /// — the scroll view follows it down.
    func pulledWindow(
        _ handler: TextEditorHandler, top: Int, lines: [TextCharacters], width: Int, height: Int, tabWidth: TabWidth,
        wraps: Bool, follows: Bool
    ) -> Window {
        guard wraps else {
            let lineIndex = min(handler.cursorLine, max(0, lines.count - 1))
            let line = lines.isEmpty ? [] : lines[lineIndex]
            let caretColumn = TabLayout.displayColumn(ofCharIndex: handler.cursorColumn, in: line, tabWidth: tabWidth)
            if follows {
                handler.wrapWidth = nil
                handler.sidewaysWidth = width
                let caretCells =
                    handler.cursorColumn >= 0 && handler.cursorColumn < line.count
                    ? (line[handler.cursorColumn] == "\t" ? 1 : max(1, line[handler.cursorColumn].terminalWidth)) : 1
                followCursor(
                    handler, cursorDisplayColumn: caretColumn, caretCells: caretCells, width: width, height: height)
                let spaced = handler.sidewaysRows()
                handler.scrollSideways(toRow: min(top, max(0, spaced.rowCount - 1)), in: spaced)
            }
            return Window(
                contentWidth: width, hasVerticalOverflow: false, extent: handler.sidewaysRows().rowCount, offset: top,
                caretColumn: caretColumn, rows: nil)
        }
        let rows = handler.wrappedRows(width: width, tabWidth: tabWidth)
        if follows {
            handler.wrapWidth = width
            handler.sidewaysWidth = nil
            handler.scroll(toRow: min(top, max(0, rows.rowCount - 1)), in: rows)
            handler.scrollColumn = 0
        }
        return Window(
            contentWidth: width, hasVerticalOverflow: false, extent: rows.rowCount, offset: top,
            caretColumn: handler.caretColumnInRow(in: rows), rows: rows)
    }

    /// The row the caret is on, among the editor's rows at `width`.
    private func caretRow(_ handler: TextEditorHandler, width: Int, context: RenderContext) -> Int {
        guard context.environment.textEditorWrapsLines else {
            return handler.sidewaysRows().row(ofLine: handler.cursorLine)
        }
        return handler.caretRow(in: handler.wrappedRows(width: width, tabWidth: context.environment.tabWidth))
    }

    /// The editor's rows at `width`, for a measure: its lines, or where it
    /// wraps its rows, a paragraph's line height's blank rows among them —
    /// read from the value itself before a render has made the handler that
    /// keeps them. With a `limit`, at least that many where the editor has as
    /// many lines, a line being a row at least, and none wrapped to say so.
    func contentRowCount(width: Int, context: RenderContext, upTo limit: Int? = nil) -> Int {
        let layout = layout(context: context)
        if let limit, layout.lines.count >= limit { return layout.lines.count }
        var gaps: [Int]?
        if let handler = existingHandler(context: context) {
            gaps = handler.lineGaps(for: layout)
        } else if let value = attributed?.text.wrappedValue, Self.hidingGlyph(in: context) == nil {
            // Before a render has made the handler: the lines the first screen
            // can show, as the handler reads them (``TextEditorHandler/lineGaps(for:)``).
            let shown = 0..<min(layout.lines.count, max(1, min(context.availableHeight, 1024)) + 1)
            let rows = shown.map {
                TextEditorHandler.lineRows(
                    ofLine: $0, in: value, characterStarts: layout.characterStarts, reading: { $0.drawnLineRows })
            }
            if rows.contains(where: { $0 > 1 }) {
                gaps = Array(repeating: 0, count: layout.lines.count)
                for (line, count) in zip(shown, rows) { gaps?[line] = count - 1 }
            }
        }
        guard context.environment.textEditorWrapsLines, width > 0 else {
            return SidewaysRows(lineCount: layout.lines.count, gaps: gaps).rowCount
        }
        return max(1, layout.wrapped(width: width, tabWidth: context.environment.tabWidth, gaps: gaps).rowCount)
    }

    /// The editor's handler, when it has one.
    private func existingHandler(context: RenderContext) -> TextEditorHandler? {
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: Self.handlerStateIndex)
        let box: StateBox<TextEditorHandler>? = context.stateStorage?.existingStorage(for: key)
        return box?.value
    }
}
