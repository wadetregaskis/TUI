//  🖥️ TUI — A Terminal UI framework for Swift
//  EditorLayout+CharacterOffsets.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - Character offsets

extension EditorLayout: TextCharacterOffsets {
    /// The line the character `offset` is on, and its column there.
    func position(ofCharacter offset: Int) -> TextEditorPosition {
        let offset = max(0, offset)
        let line = Self.lastIndex(in: characterStarts, atOrBefore: offset)
        return TextEditorPosition(line: line, column: min(offset - characterStarts[line], lines[line].count))
    }

    /// `position` as a character offset into the text, line breaks counted.
    func characterOffset(of position: TextEditorPosition) -> Int {
        let line = min(max(0, position.line), lines.count - 1)
        return characterStarts[line] + min(max(0, position.column), lines[line].count)
    }

    func offset(of index: String.Index, in text: String) -> Int {
        guard index > text.startIndex else { return 0 }
        guard index < text.endIndex else {
            // Typed in steps: as one expression it exceeded the type-check guard.
            let last: Int = lines.count - 1
            let lastStart: Int = characterStarts[last]
            return lastStart + lines[last].count
        }
        // Onto the character the index is in, as the editor's characters are.
        let index = text.index(index, offsetBy: 0)
        let byte = text.utf8.distance(from: text.utf8.startIndex, to: index)
        let line = Self.lastIndex(in: lineStarts, atOrBefore: byte)
        let start = text.utf8.index(text.utf8.startIndex, offsetBy: lineStarts[line])
        return characterStarts[line] + min(text[start..<index].count, lines[line].count)
    }

    func index(atOffset offset: Int, in text: String) -> String.Index {
        let position = position(ofCharacter: offset)
        guard offset <= characterOffset(of: TextEditorPosition(line: lines.count - 1, column: .max)) else {
            return text.endIndex
        }
        let bytes = lines[position.line].utf8Offset(of: position.column)
        return text.utf8.index(text.utf8.startIndex, offsetBy: lineStarts[position.line] + bytes)
    }

    /// Each of `offsets`, UTF-8 offsets into the text in ascending order, on
    /// a character's edge, as a line and a column: in one walk of each line
    /// as far as its last, however many fall in it.
    func positions(ofUTF8 offsets: [Int]) -> [TextEditorPosition] {
        var positions: [TextEditorPosition] = []
        positions.reserveCapacity(offsets.count)
        var (line, column, byte) = (-1, 0, 0)
        for offset in offsets {
            let found = self.line(containingUTF8Offset: offset)
            if found != line { (line, column, byte) = (found, 0, lineStarts[found]) }
            let characters = lines[line]
            while column < characters.count, byte < offset {
                byte += characters.utf8Length(of: column)
                column += 1
            }
            positions.append(TextEditorPosition(line: line, column: column))
        }
        return positions
    }

    /// The line the byte at `offset` is in, a line's break counted as its
    /// own: the last line for an offset past the text.
    func line(containingUTF8Offset offset: Int) -> Int {
        Self.lastIndex(in: lineStarts, atOrBefore: offset)
    }

    /// The last index of `starts`, ascending from 0, whose value is at most
    /// `value`.
    private static func lastIndex(in starts: [Int], atOrBefore value: Int) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= value { low = middle } else { high = middle - 1 }
        }
        return low
    }
}
