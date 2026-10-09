//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextFieldHandler+Vertical.swift
//
//  The keys of a vertical text field — `TextField(…, axis: .vertical)` —
//  where they differ from a field on one line: moving by a row, the newline
//  keys, and the commands about the line the caret is on.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// A vertical field is a text field that wraps, and keeps a text field's keys:
// SwiftUI's is the same AppKit field editor as a field on one line, measured on
// macOS 15.8 — Return and Shift-Return submit, and the Emacs chords follow
// the text field's table. So it is built on this handler, with its character
// offsets, rather than on the editor's lines and columns. What changes is what
// a field on one line has no use for:
//
// | Key | Action in a vertical field |
// |-----|----------------------------|
// | Up / Down, Ctrl-P / Ctrl-N | Move a row, keeping the column; from the first row Up goes to the start, from the last Down to the end |
// | Shift+Up / Shift+Down | Extend the selection a row |
// | Option+Return | Insert a newline (macOS's `insertNewlineIgnoringFieldEditor:`) |
// | Ctrl-O | Insert a newline in front of the caret (Cocoa's open line) |
// | Ctrl-A / Ctrl-E | The start / end of the caret's line |
// | Ctrl-K | Kill to the end of the line, or the newline at its end |
// | A paste | Keeps its line breaks |
//
// Option+Return needs a terminal that sends Option as Meta (ESC before the
// key); without it the terminal sends a plain Return, which submits. Ctrl-O
// arrives on every terminal. macOS's Ctrl-Return, which inserts a line
// separator, arrives as a plain Return from every terminal that does not
// speak an extended keyboard protocol, so it submits.

extension TextFieldHandler {
    /// Whether the field is vertical: its text wraps over rows.
    var isVertical: Bool { wrapWidth != nil }

    /// What a vertical field draws for `character`: a tab as one space, since a
    /// raw tab would move the terminal's cursor to its next tab stop.
    nonisolated static func verticalDisplayCharacter(_ character: Character) -> Character {
        character == "\t" ? " " : character
    }

    /// The cells a vertical field gives `character`, at least one.
    nonisolated static func verticalCellWidth(_ character: Character) -> Int {
        max(1, verticalDisplayCharacter(character).terminalWidth)
    }

    /// The field's text laid out in rows at its wrap width, from the live text,
    /// or `nil` for a field on one line.
    ///
    /// Laid out afresh rather than kept from the last render: a key can arrive
    /// before the frame that would draw the text the last key typed.
    func softWrapLayout() -> SoftWrapLayout? {
        guard let wrapWidth else { return nil }
        return SoftWrapLayout(Array(text.wrappedValue), width: wrapWidth, cellWidth: Self.verticalCellWidth)
    }

    /// Whether the caret is on the field's last row — always, on one line.
    var isCaretOnLastRow: Bool {
        guard let layout = softWrapLayout() else { return true }
        return layout.row(of: cursorPosition, affinity: caretAffinity) == layout.rows.count - 1
    }

    /// The affinity the caret's row is read by: the field's, except for a
    /// selection's head the pointer put on a wrapped row's first character
    /// (``rowStartHead``), which is read on that row.
    var caretAffinity: TextSelectionAffinity {
        rowStartHead == cursorPosition ? .downstream : selectionAffinity
    }

    /// Ends ``rowStartHead``'s reading once a key has moved the head off
    /// the row start the pointer put it on, or left it the end of no
    /// selection — Backspace deleting a backward selection leaves the caret
    /// on its head: an offset the keys come back to is read by the caret
    /// rule, and so is a plain caret, by the field's affinity like every
    /// other.
    func forgetMovedRowStartHead() {
        if rowStartHead != cursorPosition || !hasSelection { rowStartHead = nil }
    }

    /// Moves a selection's head — a drag's, a Shift-click's end — to
    /// `offset`, which the pointer found on `row`, and reads it on that row.
    /// Under `.upstream` that can be a wrapped row's first character, which
    /// the caret rule reads on the row before: the head is kept as
    /// ``rowStartHead`` while it stays there.
    func placeSelectionHead(at offset: Int, onRow row: Int) {
        cursorPosition = offset
        rowStartHead = nil
        guard let layout = softWrapLayout(), layout.row(of: offset, affinity: selectionAffinity) != row,
            layout.row(of: offset, affinity: .downstream) == row
        else { return }
        rowStartHead = offset
    }

    /// `text` with every line break — CRLF, a lone CR or LF — as one newline.
    nonisolated static func normalizingLineBreaks(_ text: String) -> String {
        var normalized = ""
        normalized.reserveCapacity(text.count)
        for character in text {
            normalized.append(character == "\r\n" || character == "\r" ? "\n" : character)
        }
        return normalized
    }

    // MARK: - Keys

    /// A vertical field's own keys, or `nil` for a key it handles as a field
    /// on one line does.
    func handleVerticalKeyEvent(_ event: KeyEvent) -> Bool? {
        guard let layout = softWrapLayout() else { return nil }
        switch event.key {
        case .up:
            moveRow(by: -1, extending: event.shift, in: layout)
        case .down:
            moveRow(by: 1, extending: event.shift, in: layout)
        case .enter where event.alt:
            insertCharacter("\n")
        default:
            return nil
        }
        return true
    }

    /// A vertical field's own reading of a command about lines, or `nil` where
    /// the field is on one line or the command is not one: Ctrl-A, Ctrl-E and
    /// Ctrl-K on the caret's line, Ctrl-P and Ctrl-N a row up and down, and
    /// Ctrl-O opening a line. Paging down stays the page's.
    func performOnLines(_ command: TextEditingCommand) -> Bool? {
        guard let layout = softWrapLayout() else { return nil }
        switch command {
        case .moveToStartOfLine: moveToParagraphStart()
        case .moveToEndOfLine: moveToParagraphEnd()
        case .killToEndOfLine: killToEnd(at: lineKillEnd())
        case .moveToPreviousLine: moveRow(by: -1, extending: false, in: layout)
        case .moveToNextLine: moveRow(by: 1, extending: false, in: layout)
        case .openLine: openLine()
        default: return nil
        }
        return true
    }

    /// Moves the caret `delta` rows, to the column the caret was at — or, in a
    /// run of Up and Down presses, the one the run started from. Past the
    /// first row the caret goes to the start of the text, and past the last
    /// to its end, as macOS's does.
    func moveRow(by delta: Int, extending: Bool, in layout: SoftWrapLayout) {
        if extending { startOrExtendSelection() } else { clearSelection() }
        let row = layout.row(of: cursorPosition, affinity: caretAffinity)
        let column =
            verticalAnchor.flatMap { $0.caret == cursorPosition ? $0.column : nil }
            ?? layout.column(of: cursorPosition, inRow: row)
        let target = row + delta
        if target < 0 {
            cursorPosition = 0
        } else if target >= layout.rows.count {
            cursorPosition = layout.characterCount
        } else {
            cursorPosition = layout.offset(inRow: target, atColumn: column, affinity: selectionAffinity)
        }
        verticalAnchor = (column, cursorPosition)
    }

    /// Ctrl-O: inserts a newline and leaves the caret in front of it, opening
    /// the rest of the line onto a new one below.
    func openLine() {
        guard textContentType?.isAllowed("\n") ?? true else { return }
        // Where the newline goes: the caret, or the start of the selection it
        // replaces.
        let start = selectionRange?.lowerBound ?? cursorPosition
        insertCharacter("\n")
        cursorPosition = start
    }

    // MARK: - Lines

    /// The offset where the caret's line starts: just after the newline before
    /// the caret, or the start of the text.
    private func lineStart() -> Int {
        let characters = Array(text.wrappedValue)
        var offset = min(cursorPosition, characters.count)
        while offset > 0, !characters[offset - 1].isNewline { offset -= 1 }
        return offset
    }

    /// The offset where the caret's line ends: at the newline after the caret,
    /// or the end of the text.
    private func lineEnd() -> Int {
        let characters = Array(text.wrappedValue)
        var offset = min(cursorPosition, characters.count)
        while offset < characters.count, !characters[offset].isNewline { offset += 1 }
        return offset
    }

    /// Ctrl-A in a vertical field: the start of the caret's line.
    func moveToParagraphStart() {
        clearSelection()
        cursorPosition = lineStart()
    }

    /// Ctrl-E in a vertical field: the end of the caret's line.
    func moveToParagraphEnd() {
        clearSelection()
        cursorPosition = lineEnd()
    }

    /// Where Ctrl-K stops: the end of the caret's line, or, with the caret
    /// already there, just past the newline that ends it.
    func lineKillEnd() -> Int {
        let end = lineEnd()
        return end == cursorPosition && end < text.wrappedValue.count ? end + 1 : end
    }
}
