//  🖥️ TUI — A Terminal UI framework for Swift
//  TextFieldHandler+AppEdit.swift
//
//  A TextField's (and a SecureField's) caret and selection carried through an
//  edit the app made to its text, as NSTextView carries its own (owner ruling
//  O-28 (a), 2026-11-22).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension TextFieldHandler {
    /// Carries the caret and the selection through the edit the app has made
    /// to the text since the field last saw it (``AppTextEdit``), if it has:
    /// called wherever the text can have changed from outside, the render and
    /// the start of each key, before anything is clamped.
    ///
    /// The field's own edits are not the app's: each tells ``selectionText``
    /// what it wrote (``write(_:)``), so a key's echo through the binding
    /// finds nothing to carry. A binding that keeps something else than it
    /// was handed (one that formats a number as it is typed) is an edit of
    /// the app's, from the text the field wrote, where its caret is.
    ///
    /// A selection the app writes in the same update (`TextField(text:selection:)`)
    /// is taken after this (``adoptSelectionFromApp()``), and wins.
    func followAppEdit() {
        let current = text.wrappedValue
        let seen = selectionText
        guard !TextEdit.sameBytes(seen, current) else { return }
        selectionText = current
        guard let edit = AppTextEdit(from: seen, to: current) else { return }
        let untouched = selectionChannel.map { $0.read(WalkedCharacterOffsets(), seen) == exchangedSelection } ?? false
        let caret = Self.utf8Offset(ofCharacter: cursorPosition, in: seen)
        let anchor = selectionAnchor.map { Self.utf8Offset(ofCharacter: $0, in: seen) }
        let span = min(caret, anchor ?? caret)..<max(caret, anchor ?? caret)
        let placed = edit.placed(around: span)
        switch placed.carry(span) {
        case .moved(let moved):
            let delta = moved.lowerBound - span.lowerBound
            cursorPosition = Self.characterOffset(ofUTF8: caret + delta, in: current)
            selectionAnchor = anchor.map { Self.characterOffset(ofUTF8: $0 + delta, in: current) }
        case .collapsed(let end):
            cursorPosition = Self.characterOffset(ofUTF8: end, in: current)
            selectionAnchor = nil
        }
        // The pointer's gestures in progress: carried where the edit leaves
        // their text be, dropped where it took it.
        multiClickRun = multiClickRun.flatMap { run in
            let bytes = Self.utf8Offset(ofCharacter: run.range.lowerBound, in: seen)..<Self.utf8Offset(
                ofCharacter: run.range.upperBound, in: seen)
            guard case .moved(let moved) = placed.carry(bytes) else { return nil }
            let lower = Self.characterOffset(ofUTF8: moved.lowerBound, in: current)
            return (run.granularity, lower..<max(lower, Self.characterOffset(ofUTF8: moved.upperBound, in: current)))
        }
        pressAnchor = pressAnchor.map { press in
            let byte = Self.utf8Offset(ofCharacter: press, in: seen)
            switch placed.carry(byte..<byte) {
            case .moved(let moved): return Self.characterOffset(ofUTF8: moved.lowerBound, in: current)
            case .collapsed(let end): return Self.characterOffset(ofUTF8: end, in: current)
            }
        }
        (rowStartHead, verticalAnchor) = (nil, nil)
        if untouched, let selectionChannel {
            // What its binding reads as now, which the field's carried
            // selection stands in for until the next key writes it back.
            exchangedSelection = selectionChannel.read(WalkedCharacterOffsets(), current)
        }
    }

    /// The UTF-8 offset in `text` of the character `offset` characters in,
    /// or of its end.
    static func utf8Offset(ofCharacter offset: Int, in text: String) -> Int {
        let index = WalkedCharacterOffsets().index(atOffset: offset, in: text)
        return text.utf8.distance(from: text.utf8.startIndex, to: index)
    }

    /// The character offset of the UTF-8 offset `offset` in `text`: the edge
    /// of the character it is in that follows it, where it is inside one (an
    /// edit can end between a letter and the accent it put on it).
    static func characterOffset(ofUTF8 offset: Int, in text: String) -> Int {
        let utf8 = text.utf8
        guard offset > 0 else { return 0 }
        guard let byte = utf8.index(utf8.startIndex, offsetBy: offset, limitedBy: utf8.endIndex), byte < utf8.endIndex
        else { return text.count }
        // Onto the start of the character the byte is in, then past it if the
        // byte was inside it.
        var index = text.index(byte, offsetBy: 0)
        if index < byte { index = text.index(after: index) }
        return text.distance(from: text.startIndex, to: index)
    }
}
