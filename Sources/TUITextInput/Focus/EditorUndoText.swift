//  🖥️ TUI — A Terminal UI framework for Swift
//  EditorUndoText.swift
//
//  What a TextEditor's undo keeps of its text: the String, or the
//  AttributedString of an editor bound to one (G3 L4).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// The text a ``TextEditor``'s undo history keeps: its `String`, kept as byte
/// edits (``TextEdit``), or the `AttributedString` of an editor bound to one,
/// whose steps give back its attributes with its characters (G3 L4).
///
/// An attributed step keeps the values before and after it whole. That is not
/// the copy a `String`'s whole text would be (owner ruling B-PASTE-1-EDITOR):
/// an `AttributedString` is a tree, and a value edited in place shares every
/// part of it the edit did not touch with the value before.
enum EditorUndoText: UndoableText {
    case plain(String)
    case attributed(AttributedString)

    typealias UndoEdit = EditorUndoEdit

    /// Two `String`s byte for byte; two `AttributedString`s by their
    /// characters, byte for byte, so a value the app recoloured is still the
    /// text the history's edits left.
    static func sameContent(_ a: Self, _ b: Self) -> Bool {
        switch (a, b) {
        case (.plain(let a), .plain(let b)): String.sameContent(a, b)
        case (.attributed(let a), .attributed(let b)):
            AttributedTextSource.isIdentical(a, b)
                || TextEdit.sameBytes(AttributedTextSource.characters(of: a), AttributedTextSource.characters(of: b))
        default: false
        }
    }

    /// An attributed value shares its storage with the text, and is counted
    /// as nothing.
    var undoKeptBytes: Int {
        switch self {
        case .plain(let text): text.undoKeptBytes
        case .attributed: 0
        }
    }
}

/// The edit between two of an editor's texts (``EditorUndoText``).
enum EditorUndoEdit: UndoableTextEdit {
    case plain(TextEdit)
    case attributed(before: AttributedString, after: AttributedString)
    /// Between a `String` and an `AttributedString`, which no editor makes:
    /// neither undone nor redone.
    case none

    init(from before: EditorUndoText, to after: EditorUndoText) {
        switch (before, after) {
        case (.plain(let before), .plain(let after)): self = .plain(TextEdit(from: before, to: after))
        case (.attributed(let before), .attributed(let after)): self = .attributed(before: before, after: after)
        default: self = .none
        }
    }

    func reverted(_ after: EditorUndoText) -> EditorUndoText? {
        switch (self, after) {
        case (.plain(let edit), .plain(let text)): edit.reverted(text).map { .plain($0) }
        case (.attributed(let before, let left), .attributed):
            EditorUndoText.sameContent(.attributed(left), after) ? .attributed(before) : nil
        default: nil
        }
    }

    func applied(_ before: EditorUndoText) -> EditorUndoText? {
        switch (self, before) {
        case (.plain(let edit), .plain(let text)): edit.applied(text).map { .plain($0) }
        case (.attributed(let from, let after), .attributed):
            EditorUndoText.sameContent(.attributed(from), before) ? .attributed(after) : nil
        default: nil
        }
    }

    var reversed: Self {
        switch self {
        case .plain(let edit): .plain(edit.reversed)
        case .attributed(let before, let after): .attributed(before: after, after: before)
        case .none: .none
        }
    }

    var changesNothing: Bool {
        switch self {
        case .plain(let edit): edit.changesNothing
        case .attributed(let before, let after): EditorUndoText.sameContent(.attributed(before), .attributed(after))
        case .none: false
        }
    }

    var keptBytes: Int {
        switch self {
        case .plain(let edit): edit.keptBytes
        case .attributed, .none: 0
        }
    }
}
