//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScreenSelection+Addresses.swift
//
//  A double-click on a web address selects the address, not a word of it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension ScreenSelection {
    /// The web address around `column`, if the run of non-blank cells it is
    /// in holds one there: what a double-click selects instead of a word, so
    /// that a link's address — in a link's popover, in a page's text — is
    /// selected whole rather than as the letters between two of its slashes.
    ///
    /// An address starts at a scheme and `://` (`https://`, `ssh://`) or at
    /// `www.`, so a bracket or a quote before it is left out, and runs to the
    /// next blank, less the marks a sentence puts after one: a full stop, a
    /// comma, a closing quote, or a closing bracket the address did not open
    /// (`(see https://swift.org).` selects `https://swift.org`, while
    /// `…/Swift_(programming_language)` keeps its own). `nil` where there is
    /// none, or the click is on the run outside it.
    static func urlBounds(at column: Int, in cells: [Character?], clip: Rect) -> Range<Int>? {
        let lower = clip.x
        let upper = min(clip.x + clip.width, cells.count)
        func character(_ index: Int) -> Character? {
            // A wide character's second cell is the character's.
            var index = index
            while index > lower, cells[index] == nil { index -= 1 }
            return cells[index]
        }
        func isBlank(_ index: Int) -> Bool { character(index)?.isWhitespace ?? true }
        guard column >= lower, column < upper, !isBlank(column) else { return nil }
        var runStart = column
        while runStart > lower, !isBlank(runStart - 1) { runStart -= 1 }
        var runEnd = column + 1
        while runEnd < upper, !isBlank(runEnd) { runEnd += 1 }
        // The run's characters, each with the cell it starts at.
        let run: [(cell: Int, character: Character)] = (runStart..<runEnd).compactMap { cell in
            cells[cell].map { (cell, $0) }
        }
        let text = run.map(\.character)
        guard let first = Self.addressStart(in: text) else { return nil }
        var characters = Array(text[first...])
        var opened = 0
        for character in characters {
            if character == "(" { opened += 1 } else if character == ")" { opened -= 1 }
        }
        while let last = characters.last {
            if last == ")", opened < 0 {
                opened += 1
            } else if !".,;:!?'\"]}>".contains(last) {
                break
            }
            characters.removeLast()
        }
        guard !characters.isEmpty else { return nil }
        let startCell = run[first].cell
        let lastIndex = first + characters.count - 1
        let endCell = lastIndex + 1 < run.count ? run[lastIndex + 1].cell : runEnd
        guard (startCell..<endCell).contains(column) else { return nil }
        return startCell..<endCell
    }

    /// Where an address starts in `text`: at its scheme, letters followed by
    /// `://`, or at `www.`, whatever its case.
    static func addressStart(in text: [Character]) -> Int? {
        func matches(_ word: String, at index: Int) -> Bool {
            let word = Array(word)
            guard index + word.count <= text.count else { return false }
            return (0..<word.count).allSatisfy { text[index + $0].lowercased() == String(word[$0]) }
        }
        if let separator = text.indices.first(where: { matches("://", at: $0) }) {
            var start = separator
            while start > 0 {
                let before = text[start - 1]
                guard before.isLetter || before.isNumber || "+.-".contains(before) else { break }
                start -= 1
            }
            // The scheme starts with a letter.
            while start < separator, !text[start].isLetter { start += 1 }
            return start < separator ? start : nil
        }
        return text.indices.first { matches("www.", at: $0) }
    }
}
