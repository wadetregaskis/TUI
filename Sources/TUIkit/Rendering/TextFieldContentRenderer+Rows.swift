//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextFieldContentRenderer+Rows.swift
//
//  A vertical text field's rows: each one a field line, drawn by the same
//  builders a field on one line uses, from the rows its text wraps into.
//
//  Created by Wade Tregaskis
//  License: MIT

extension TextFieldContentRenderer {
    /// What a vertical field shows: the rows its text — or, while the text is
    /// empty, its prompt — wraps into, the window of them it draws, and where
    /// the caret and selection are.
    struct Rows {
        /// The text or prompt, laid out at ``width``.
        let layout: SoftWrapLayout

        /// The characters ``layout`` laid out.
        let characters: [Character]

        /// Whether ``characters`` are the prompt's, drawn as a placeholder.
        let isPrompt: Bool

        /// The caret's character offset.
        let caret: Int

        /// The selected character offsets, if anything is selected.
        let selection: Range<Int>?

        /// Which row an offset where a row wrapped is drawn on.
        let affinity: TextSelectionAffinity

        /// The first row drawn.
        let firstRow: Int

        /// How many rows are drawn — past the text's last, blank ones.
        let count: Int

        /// The cells each row is drawn in.
        var width: Int { layout.width }
    }

    /// The prompt's text, paragraph by paragraph, for a field that draws it over
    /// several rows — or `""` for none.
    static func promptParagraphs(_ prompt: Text?) -> String {
        guard let prompt else { return "" }
        let buffer = TUIkit.renderToBuffer(
            prompt, context: RenderContext(availableWidth: 4096, availableHeight: 4096))
        return buffer.lines.map(\.stripped).joined(separator: "\n")
    }

    /// Each drawn row of a vertical field, every one exactly the rows' width:
    /// its line, its caret's run when the caret is on it, and its claims, all
    /// in the row's own frame — the caller knows where the row goes.
    ///
    /// A row is a field line, built by the very builders a field on one line
    /// uses: an unfocused row as unfocused text, a focused one with its part of
    /// the selection and, on the caret's row, the caret. So a selection, a
    /// caret and a faded palette draw in a vertical field exactly as they do
    /// in a single line.
    func buildRows(
        _ rows: Rows, isFocused: Bool, palette: any Palette, cursorStyle: TextCursorStyle,
        cursorTimer: CursorTimer?, cursorTiming: IndicatorCycleTiming?
    ) -> [FieldContent] {
        let layout = rows.layout
        let caretRow = isFocused ? layout.row(of: rows.caret, affinity: rows.affinity) : nil
        return (rows.firstRow..<(rows.firstRow + rows.count)).map { index in
            guard index < layout.rows.count else {
                return buildTextContent(text: "", palette: palette, background: surface, width: rows.width)
            }
            let row = layout.rows[index]
            let text = String(rows.characters[row.start..<row.end])
            if rows.isPrompt {
                guard index == caretRow else {
                    return buildPromptContent(palette: palette, background: surface, width: rows.width, text: text)
                }
                return buildTextWithCursor(
                    text: text, cursorPosition: 0, selectionRange: nil, palette: palette,
                    cursorStyle: cursorStyle, cursorTimer: cursorTimer, cursorTiming: cursorTiming,
                    background: surface, width: rows.width,
                    foregroundOverride: Self.promptColor(palette: palette, on: surface),
                    displayOverride: { $0 })
            }
            guard isFocused else {
                return buildTextContent(text: text, palette: palette, background: surface, width: rows.width)
            }
            return buildTextWithCursor(
                text: text,
                cursorPosition: index == caretRow ? Self.caretOnRow(index, of: rows) : nil,
                selectionRange: rows.selection.flatMap { Self.selection($0, onRow: row) },
                palette: palette, cursorStyle: cursorStyle, cursorTimer: cursorTimer,
                cursorTiming: cursorTiming, background: surface, width: rows.width)
        }
    }

    /// The caret's offset within `row`, moved back until it is drawn inside the
    /// width: a caret further into a run of hanging spaces than the margin is
    /// drawn on the margin, as ``SoftWrapLayout`` describes.
    private static func caretOnRow(_ row: Int, of rows: Rows) -> Int {
        let layout = rows.layout
        let start = layout.rows[row].start
        var offset = min(max(start, rows.caret), layout.rows[row].end)
        while offset > start, layout.cells(inRow: row, before: offset) > layout.width - 1 {
            offset -= 1
        }
        return offset - start
    }

    /// The part of `selection` on `row`, as offsets within the row.
    private static func selection(_ selection: Range<Int>, onRow row: SoftWrapLayout.Row) -> Range<Int>? {
        let lower = max(selection.lowerBound, row.start)
        let upper = min(selection.upperBound, row.end)
        return lower < upper ? (lower - row.start)..<(upper - row.start) : nil
    }
}
