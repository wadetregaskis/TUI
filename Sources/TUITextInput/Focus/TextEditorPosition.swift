//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorPosition.swift
//
//  A place in a `TextEditor`'s text, by line and column.
//
//  Created by Wade Tregaskis
//  License: MIT

/// A position in a ``TextEditor``: a line and a character column, ordered
/// top-to-bottom then left-to-right.
struct TextEditorPosition: Comparable {
    var line: Int
    var column: Int

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.line != rhs.line ? lhs.line < rhs.line : lhs.column < rhs.column
    }
}
