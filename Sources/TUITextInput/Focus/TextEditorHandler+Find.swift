//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHandler+Find.swift
//
//  The editor's side of its find bar (decisions B81): matches replaced as
//  the editor's own edit.
//
//  Created by Wade Tregaskis
//  License: MIT

extension TextEditorHandler {
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
