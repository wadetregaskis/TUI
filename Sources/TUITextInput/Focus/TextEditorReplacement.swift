//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorReplacement.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// One edit a ``TextEditor`` makes to its text, as a range replaced: the
/// characters from ``start`` to ``end`` of the lines as they are when it is
/// made give way to ``replacement``.
///
/// Every edit the editor makes is one or more of these
/// (``TextEditorHandler/writeReplacing(_:)``), rather than whole lines built
/// and written, so an editor bound to an `AttributedString` can make the same
/// edit in its value and keep the attributes of everything around it (G3,
/// B-ATTRED-1). Typing replaces an empty range at the caret; a deletion
/// replaces its range with nothing; Ctrl-T replaces the two characters it
/// swaps with them swapped.
struct TextEditorReplacement: Equatable {
    /// Where the replaced characters start.
    let start: TextEditorPosition
    /// Where they end: `start` for an insertion.
    let end: TextEditorPosition
    /// What takes their place, as lines: one more than it has line breaks,
    /// so never empty, and `[[]]` for a deletion.
    let replacement: [TextCharacters]

    init(from start: TextEditorPosition, to end: TextEditorPosition, with replacement: [TextCharacters] = [[]]) {
        self.start = start
        self.end = end
        self.replacement = replacement.isEmpty ? [[]] : replacement
    }

    /// Replaces the characters from `start` to `end` of one line with
    /// `characters`.
    init(line: Int, columns: Range<Int>, with characters: TextCharacters = []) {
        self.init(
            from: TextEditorPosition(line: line, column: columns.lowerBound),
            to: TextEditorPosition(line: line, column: columns.upperBound), with: [characters])
    }

    /// Whether `replacements` are more than one, each before the one listed
    /// before it, none reaching into another: what Replace All and a block's
    /// deletion make, last first, so each is placed in the text before any
    /// of them as well as in the lines the ones before it left.
    static func areDescending(_ replacements: [Self]) -> Bool {
        guard replacements.count > 1 else { return false }
        return zip(replacements, replacements.dropFirst()).allSatisfy { later, earlier in
            earlier.start <= earlier.end && earlier.end <= later.start
        }
    }

    /// Makes the replacement in `lines`: the text before ``start`` on its
    /// line, then the replacement's lines, then the text after ``end`` on
    /// its line. The lines it does not reach keep their storage, which is
    /// how ``EditorLayout/replacing(_:)`` tells them unchanged at once.
    func apply(to lines: inout [TextCharacters]) {
        var spliced = replacement
        spliced[0] = lines[start.line].characters(in: 0..<start.column) + spliced[0]
        spliced[spliced.count - 1] += lines[end.line][end.column...]
        lines.replaceSubrange(start.line...end.line, with: spliced)
    }
}
