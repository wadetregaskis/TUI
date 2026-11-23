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
        guard let channel = selectionChannel, let wanted = channel.read(WalkedCharacterOffsets(), text.wrappedValue),
            wanted != exchangedSelection
        else { return }
        let count = text.wrappedValue.count
        let lower = min(max(0, wanted.lowerBound), count)
        let upper = min(max(lower, wanted.upperBound), count)
        selectionAnchor = lower == upper ? nil : lower
        cursorPosition = upper
        // As the macOS text system leans a selection set from outside it.
        caretLean = .upstream
        exchangedSelection = lower..<upper
    }

    /// Writes the caret and selection to the app, if they moved since the last
    /// exchange. Called after every key and pointer event.
    func publishSelection() {
        guard let channel = selectionChannel else { return }
        let current = selectionOffsets
        guard current != exchangedSelection else { return }
        exchangedSelection = current
        channel.write(current, text.wrappedValue, selectionAffinity, WalkedCharacterOffsets())
    }
}

extension TextEditorHandler {
    /// The caret and selection as character offsets, found from where the
    /// layout's lines start (``EditorLayout/characterOffset(of:)``).
    var selectionOffsets: Range<Int> {
        let layout = layout()
        let caret = layout.characterOffset(of: TextEditorPosition(line: cursorLine, column: cursorColumn))
        guard let anchor = selectionAnchor.map({ layout.characterOffset(of: $0) }) else { return caret..<caret }
        return min(anchor, caret)..<max(anchor, caret)
    }

    /// Adopts a selection the app wrote, if it changed since the last exchange.
    func adoptSelectionFromApp() {
        let layout = layout()
        guard let channel = selectionChannel, let wanted = channel.read(layout, layout.text), wanted != exchangedSelection
        else { return }
        let caret = layout.position(ofCharacter: wanted.upperBound)
        selectionAnchor = wanted.isEmpty ? nil : layout.position(ofCharacter: wanted.lowerBound)
        cursorLine = caret.line
        cursorColumn = caret.column
        syncDesiredColumn(EditedLines(layout.lines))
        // As the macOS text system leans a selection set from outside it.
        caretLean = .upstream
        exchangedSelection = wanted
    }

    /// Writes the caret and selection to the app, if they moved since the last
    /// exchange.
    func publishSelection() {
        guard let channel = selectionChannel else { return }
        let current = selectionOffsets
        guard current != exchangedSelection else { return }
        exchangedSelection = current
        channel.write(current, text.wrappedValue, selectionAffinity, layout())
    }
}
