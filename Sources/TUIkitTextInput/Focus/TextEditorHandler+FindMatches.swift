//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextEditorHandler+FindMatches.swift
//
//  The find bar's matches, as the columns of each line they cover, for the rows
//  to tint (decisions B81).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension TextEditorHandler {
    /// Notes the find bar's state for this frame: whether the editor has a bar
    /// for Ctrl-F to open (``yieldsControlFToFind``), and its matches.
    func noteFind(opensOnControlF: Bool, matches: [Range<Int>], in lines: [[Character]]) {
        yieldsControlFToFind = opensOnControlF
        noteFindMatches(matches, in: lines)
    }

    /// Whether `event` is a Control chord on one of `letters` that the editor
    /// leaves to its find bar: Ctrl-F, which opens it, and Ctrl-G, which
    /// steps through its matches — where it has a bar (decisions B81).
    func isFindChord(_ event: KeyEvent, on letters: Set<Character>) -> Bool {
        guard yieldsControlFToFind, event.ctrl, !event.alt, case .character(let letter) = event.key else { return false }
        return letters.contains(letter)
    }

    /// Notes `matches`, character offsets into the text in order, as the
    /// columns of each line they cover: one walk of the lines beside the
    /// matches, so a text with many is not walked once for each.
    ///
    /// A match across a newline covers the end of one line and the start of
    /// the next.
    func noteFindMatches(_ matches: [Range<Int>], in lines: [[Character]]) {
        var byLine: [Int: [Range<Int>]] = [:]
        var lineIndex = 0
        var lineStart = 0
        for match in matches where !match.isEmpty {
            // On to the line the match starts on: the matches come in order.
            while lineIndex < lines.count, match.lowerBound > lineStart + lines[lineIndex].count {
                lineStart += lines[lineIndex].count + 1
                lineIndex += 1
            }
            var start = match.lowerBound
            while lineIndex < lines.count {
                let lineEnd = lineStart + lines[lineIndex].count
                let end = min(match.upperBound, lineEnd)
                if start < end { byLine[lineIndex, default: []].append((start - lineStart)..<(end - lineStart)) }
                guard match.upperBound > lineEnd + 1 else { break }
                lineStart = lineEnd + 1
                lineIndex += 1
                start = lineStart
            }
        }
        matchedColumnsByLine = byLine
    }
}
