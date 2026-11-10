//  🖥️ TUI — A Terminal UI framework for Swift
//  TextWrapping+CharacterBreaks.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

extension TextWrapping {
    /// A word no line can hold, broken between its characters: as much as
    /// fits `firstBudget`, then pieces of `width`. SwiftUI's `Text` does the
    /// same, where Core Text's word wrapping falls back to characters for a
    /// word longer than the line; cutting it at the edge lost the rest of the
    /// word with rows to spare.
    ///
    /// Characters, not scalars, so a combining mark stays with its letter.
    /// `nil` when there is nothing to break — a single character — or when
    /// the word holds an escape sequence, which a character walk would split;
    /// the word is then placed whole, as before, and the caller truncates it.
    static func brokenAtCharacters(_ word: String, firstBudget: Int, width: Int) -> Wrapped? {
        guard word.count > 1, !word.utf8.contains(0x1B) else { return nil }
        var lines: [String] = []
        var piece = ""
        var pieceWidth = 0
        var budget = firstBudget
        for character in word {
            let characterWidth = character.terminalWidth
            if !piece.isEmpty, pieceWidth + characterWidth > budget {
                lines.append(piece)
                piece = ""
                pieceWidth = 0
                budget = width
            }
            piece.append(character)
            pieceWidth += characterWidth
        }
        lines.append(piece)
        // Measured as a line is, so each width is its line's `strippedLength`
        // (`Wrapped`'s invariant) whatever a cluster's width claim says.
        return Wrapped(lines: lines, widths: lines.map(\.strippedLength))
    }
}
