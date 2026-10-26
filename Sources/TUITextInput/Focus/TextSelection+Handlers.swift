//  🖥️ TUI — A Terminal UI framework for Swift
//  TextSelection+Handlers.swift
//
//  A text field's and a text editor's caret and selection exchanged with the
//  app's `TextSelection` binding: the app's writes move the caret, and the
//  caret's moves are written back.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension TextFieldHandler {
    /// The caret and selection as character offsets: the selected range, or
    /// the empty range at the caret.
    var selectionOffsets: Range<Int> {
        selectionRange ?? cursorPosition..<cursorPosition
    }

    /// Adopts a selection the app wrote, if it changed since the last exchange.
    /// Called at render, before the field draws.
    func adoptSelectionFromApp() {
        guard let channel = selectionChannel, let wanted = channel.read(), wanted != exchangedSelection
        else { return }
        let count = text.wrappedValue.count
        let lower = min(max(0, wanted.lowerBound), count)
        let upper = min(max(lower, wanted.upperBound), count)
        selectionAnchor = lower == upper ? nil : lower
        cursorPosition = upper
        exchangedSelection = lower..<upper
    }

    /// Writes the caret and selection to the app, if they moved since the last
    /// exchange. Called after every key and pointer event.
    func publishSelection() {
        guard let channel = selectionChannel else { return }
        let current = selectionOffsets
        guard current != exchangedSelection else { return }
        exchangedSelection = current
        channel.write(current, text.wrappedValue, selectionAffinity)
    }
}

extension TextEditorHandler {
    /// `position` as a character offset into the text, newlines counted.
    private func offset(of position: TextEditorPosition, in lines: [[Character]]) -> Int {
        guard !lines.isEmpty else { return 0 }
        let line = min(max(0, position.line), lines.count - 1)
        let before = lines[..<line].reduce(0) { $0 + $1.count + 1 }
        return before + min(max(0, position.column), lines[line].count)
    }

    /// The line and column a character offset falls at.
    private func position(of offset: Int, in lines: [[Character]]) -> TextEditorPosition {
        var remaining = max(0, offset)
        for (index, line) in lines.enumerated() {
            if remaining <= line.count { return TextEditorPosition(line: index, column: remaining) }
            remaining -= line.count + 1
        }
        let last = max(0, lines.count - 1)
        return TextEditorPosition(line: last, column: lines.isEmpty ? 0 : lines[last].count)
    }

    /// The caret and selection as character offsets.
    var selectionOffsets: Range<Int> {
        let lines = readLines()
        let caret = offset(of: TextEditorPosition(line: cursorLine, column: cursorColumn), in: lines)
        guard let anchor = selectionAnchor.map({ offset(of: $0, in: lines) }) else { return caret..<caret }
        return min(anchor, caret)..<max(anchor, caret)
    }

    /// Adopts a selection the app wrote, if it changed since the last exchange.
    func adoptSelectionFromApp() {
        guard let channel = selectionChannel, let wanted = channel.read(), wanted != exchangedSelection
        else { return }
        let lines = readLines()
        let caret = position(of: wanted.upperBound, in: lines)
        selectionAnchor = wanted.isEmpty ? nil : position(of: wanted.lowerBound, in: lines)
        cursorLine = caret.line
        cursorColumn = caret.column
        syncDesiredColumn(lines)
        exchangedSelection = wanted
    }

    /// Writes the caret and selection to the app, if they moved since the last
    /// exchange.
    func publishSelection() {
        guard let channel = selectionChannel else { return }
        let current = selectionOffsets
        guard current != exchangedSelection else { return }
        exchangedSelection = current
        channel.write(current, text.wrappedValue, selectionAffinity)
    }
}
