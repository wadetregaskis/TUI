//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHandler+Find.swift
//
//  The editor's side of its find bar (decisions B81): a match selected, as
//  the app's selection is, and matches replaced as the editor's own edit.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension TextEditorHandler {
    /// Selects the characters `range`, as character offsets, as a selection
    /// the app writes is taken (``adoptSelectionFromApp()``), and hands it to
    /// the app's selection binding, whichever kind it is: what the find bar
    /// shows a match by. The bar used to swap the editor's selection channel
    /// for its own, which an attributed editor's binding lives outside of,
    /// and so cut it off from the moment the bar came up (TEXTIN-3).
    @MainActor
    func select(characters range: Range<Int>) {
        let layout = layout()
        let caret = layout.position(ofCharacter: range.upperBound)
        selectionAnchor = range.isEmpty ? nil : layout.position(ofCharacter: range.lowerBound)
        (cursorLine, cursorColumn) = (caret.line, caret.column)
        block = nil
        syncDesiredColumn(EditedLines(layout.lines))
        // As the macOS text system leans a selection set from outside it.
        caretLean = .upstream
        publishSelection()
    }

    /// Replaces each of `matches`, UTF-8 offsets into the text in order and
    /// apart, with `replacement`, as one edit: Replace All's, or Replace's of
    /// one match. Each is a replacement of its own (``writeReplacing(_:beforeWriting:)``),
    /// so an attributed editor gives each the attributes of the match it
    /// replaces rather than everything from the first match to the last one
    /// set (TEXTIN-5), and the edit costs the lines it touches, not the
    /// document laid out again. A selection is dropped, and the caret kept
    /// where it can be.
    @MainActor
    func replace(_ matches: [Range<Int>], with replacement: String) {
        guard !matches.isEmpty else { return }
        let positions = layout().positions(ofUTF8: matches.flatMap { [$0.lowerBound, $0.upperBound] })
        let inserted = replacement.split(omittingEmptySubsequences: false) {
            $0 == "\n" || $0 == "\r\n" || $0 == "\r"
        }.map { EditorLayout.segmented(Array($0)) }
        let replacements = stride(from: matches.count - 1, through: 0, by: -1).map { index in
            TextEditorReplacement(from: positions[index * 2], to: positions[index * 2 + 1], with: inserted)
        }
        let lines = writeReplacing(replacements) { lines in
            selectionAnchor = nil
            block = nil
            cursorLine = min(cursorLine, lines.count - 1)
            cursorColumn = min(cursorColumn, lines[cursorLine].count)
        }
        syncDesiredColumn(lines)
    }
}
