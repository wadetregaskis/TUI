//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditingCommand.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// An editing command that an Emacs chord names in a text control: a letter
/// held with Control, or B or F held with Option.
///
/// The macOS text system handles a key in two halves. Cocoa's
/// `StandardKeyBinding.dict` maps the chord to a command (Ctrl-F to
/// `moveForward:`, Ctrl-Y to `yank:`), and each text view carries the command
/// out on its own storage. This type is the first half, kept in one place so
/// that every text control reads a chord the same way. It holds the Control
/// letters of that dictionary, and readline's two Option letters, Meta-B and
/// Meta-F, the word motions macOS Terminal sends for Option-Left and
/// Option-Right as well.
///
/// What a command *does* stays with the control, because it depends on the
/// control's shape. Ctrl-K at the end of a line in a `TextEditor` kills the line
/// break and joins the next line up, and a single-line field has no break to
/// kill. A control may also decline a command, and then its chord propagates as
/// one nothing binds would: a field has no line to open for Ctrl-O.
///
/// Ctrl-H, Ctrl-I and Ctrl-M are missing on purpose. A terminal sends those bytes
/// for Backspace, Tab and Return, and `KeyEvent.parse` reads them that way.
enum TextEditingCommand: Equatable {
    /// Ctrl-A: to the start of the line.
    case moveToStartOfLine
    /// Ctrl-E: to the end of the line.
    case moveToEndOfLine
    /// Ctrl-B: back one character.
    case moveBackward
    /// Ctrl-F: forward one character.
    case moveForward
    /// Ctrl-P: up a line.
    case moveToPreviousLine
    /// Ctrl-N: down a line.
    case moveToNextLine
    /// Ctrl-D: delete the character after the caret.
    case deleteForward
    /// Ctrl-K: kill from the caret to the end of the line, for Ctrl-Y to yank.
    case killToEndOfLine
    /// Ctrl-Y: insert the most recent kill at the caret.
    case yank
    /// Ctrl-T: swap the characters on either side of the caret.
    case transpose
    /// Ctrl-O: break the line after the caret and leave the caret where it is.
    case openLine
    /// Option-Ctrl-A: select everything.
    case selectAll
    /// Option-B: back to the previous word boundary.
    case moveWordBackward
    /// Option-F: forward to the next word boundary.
    case moveWordForward
    /// Option-Shift-B: back to the previous word boundary, extending the
    /// selection there.
    case moveWordBackwardAndModifySelection
    /// Option-Shift-F: forward to the next word boundary, extending the
    /// selection there.
    case moveWordForwardAndModifySelection

    /// The command a Control chord names, or `nil` when the chord has none and
    /// should propagate.
    ///
    /// - Parameters:
    ///   - character: The letter the chord arrived as. A terminal only ever
    ///     delivers lower case, but both cases are accepted, as
    ///     `TextFieldHandler` has always accepted them.
    ///   - alt: Whether Option was held as well. Only A reads it.
    init?(control character: Character, alt: Bool) {
        switch character {
        // Option-Ctrl-A selects everything. Plain Ctrl-A goes to the start of
        // the line, as it does in readline. Cmd-A cannot reach a terminal app,
        // so select-all needs some other chord, and this is the closest one
        // that does not take a motion key away.
        case "a", "A": self = alt ? .selectAll : .moveToStartOfLine
        case "e", "E": self = .moveToEndOfLine
        case "b", "B": self = .moveBackward
        case "f", "F": self = .moveForward
        case "p", "P": self = .moveToPreviousLine
        case "n", "N": self = .moveToNextLine
        case "d", "D": self = .deleteForward
        case "k", "K": self = .killToEndOfLine
        case "y", "Y": self = .yank
        case "t", "T": self = .transpose
        case "o", "O": self = .openLine
        default: return nil
        }
    }

    /// The command a letter held with Option names: readline's word motions,
    /// B and F, or `nil` for any other letter.
    ///
    /// - Parameters:
    ///   - character: The letter. A shifted letter arrives in upper case with
    ///     `shift` set, so both cases are accepted.
    ///   - shift: Whether Shift was held, which extends the selection instead
    ///     of dropping it.
    init?(option character: Character, shift: Bool) {
        switch character {
        case "b", "B": self = shift ? .moveWordBackwardAndModifySelection : .moveWordBackward
        case "f", "F": self = shift ? .moveWordForwardAndModifySelection : .moveWordForward
        default: return nil
        }
    }
}

// MARK: - Keyboard Shortcuts

extension TextEditingCommand {
    /// Whether an app's keyboard shortcut on the same chord takes the key from
    /// the focused text control, which then does nothing.
    ///
    /// A focused text control is offered a key before the app's shortcuts are
    /// (`InputHandler`, layer 0 before layer 3.5). Under the default
    /// `.commandKey(.control)` a SwiftUI ⌘ shortcut arrives as a Control chord,
    /// so ⌘F, "Find", is Ctrl-F, the chord for forward a character, and ⌘D is
    /// Ctrl-D; under `.commandKey(.option)` ⌘B and ⌘F arrive as Option-B and
    /// Option-F, the word motions. The owner's rule (2026-09-23) is that the
    /// Emacs chords are a bonus: whatever one does can be done some other way,
    /// with another key or by selecting and typing, so the app's shortcut wins
    /// it.
    ///
    /// Where a chord *is* the only way, it keeps the key:
    ///
    /// - Option-Ctrl-A, select-all, everywhere. ⌘A cannot reach a terminal
    ///   app, and no other key selects everything.
    /// - Ctrl-A and Ctrl-E where Home and End do not go to the ends of the
    ///   line. In a field they do, so there the pair gives way like the rest.
    ///   In the editor Home and End go to the ends of the document, which
    ///   leaves Ctrl-A and Ctrl-E the only keys for the ends of a line.
    ///
    /// The chords that stand in for the Command-key ones, for the clipboard
    /// and undo (``StandInEditingCommand``), are not in this table and keep
    /// the key: they are what the app's ⌘ shortcut would ask the focused text
    /// for anyway. Copy and cut keep it only while there is a selection to act
    /// on; with none the control declines them, and the chord goes on to the
    /// app as one the control does not bind would. Ctrl-U, in the same table,
    /// keeps the key as well: it is the terminal's own kill to the start of
    /// the line, which every shell prompt answers, not an Emacs bonus — so an
    /// app's ⌘U, which arrives as Ctrl-U, does not reach past a focused text
    /// control.
    ///
    /// - Parameter homeAndEndReachLineEnds: Whether the control's Home and End
    ///   keys go to the ends of the line the caret is on.
    func givesWayToKeyboardShortcuts(homeAndEndReachLineEnds: Bool) -> Bool {
        switch self {
        case .selectAll:
            false
        case .moveToStartOfLine, .moveToEndOfLine:
            homeAndEndReachLineEnds
        case .moveBackward, .moveForward, .moveToPreviousLine, .moveToNextLine, .deleteForward,
            .killToEndOfLine, .yank, .transpose, .openLine, .moveWordBackward,
            .moveWordForward, .moveWordBackwardAndModifySelection, .moveWordForwardAndModifySelection:
            true
        }
    }
}

// MARK: - Transpose

extension TextEditingCommand {
    /// Ctrl-T on one line of text: swaps the two characters on either side of
    /// `column`, and returns the column the caret moves to, which is one step
    /// on. At the end of the line there is no character after the caret, so
    /// the last two characters are swapped and the caret stays at the end.
    ///
    /// Returns `nil` and leaves `line` alone when there is nothing to swap: the
    /// line is shorter than two characters, or the caret is at its start.
    ///
    /// This is a plain function of a character array and an index, like
    /// ``WordBoundary``, so it belongs to no one control: the editor passes one
    /// line, and a single-line field's whole text is a line too.
    static func transpose(in line: inout [Character], at column: Int) -> Int? {
        guard line.count >= 2, column > 0 else { return nil }
        if column >= line.count {
            line.swapAt(line.count - 2, line.count - 1)
            return line.count
        }
        line.swapAt(column - 1, column)
        return column + 1
    }
}

// MARK: - Word rubout

extension StandInEditingCommand {
    /// Where Ctrl-W's kill starts on one line of text with the caret at
    /// `column`: back over the blanks just before the caret, then over the
    /// run of non-blank characters before them — readline's
    /// `unix-word-rubout`, whose words are whatever lies between blanks, so a
    /// path or a URL goes in one kill where ⌥⌫'s word deletion stops at each
    /// punctuation mark. Never before `lineStart`: as Ctrl-U, Ctrl-W stays on
    /// the caret's line.
    ///
    /// A plain function of a character array and an index, like
    /// ``TextEditingCommand/transpose(in:at:)``: the editor passes one line,
    /// and a field passes its text.
    static func wordRuboutStart(in line: [Character], before column: Int, lineStart: Int = 0) -> Int {
        var start = min(column, line.count)
        while start > lineStart, line[start - 1].isWhitespace { start -= 1 }
        while start > lineStart, !line[start - 1].isWhitespace { start -= 1 }
        return start
    }
}

// MARK: - Command-Key Stand-Ins

/// An editing command that a text control binds to a Control chord in place
/// of the Command-key chord a terminal app never receives: ⌘C, ⌘X, ⌘V, ⌘Z and
/// ⇧⌘Z are Ctrl-C, X, V, Z and Shift-Z here, and Ctrl-U and Ctrl-W erase.
///
/// A separate table from ``TextEditingCommand``, because the two disagree
/// about V: here it is paste, and in the Emacs table it is page down. A
/// control reads this one first for the letters it binds from it.
enum StandInEditingCommand: Equatable {
    /// Ctrl-C: copy the selection.
    case copy
    /// Ctrl-X: cut the selection.
    case cut
    /// Ctrl-V: paste.
    case paste
    /// Ctrl-Z: undo.
    case undo
    /// Ctrl-Shift-Z: redo, where the terminal tells it from Ctrl-Z (the kitty
    /// keyboard protocol); in a legacy encoding it arrives as Ctrl-Z.
    case redo
    /// Ctrl-U: kills from the caret to the start of its line, as readline's
    /// `unix-line-discard` does in a shell at a terminal — and as ⌘⌫, the
    /// macOS text system's `deleteToBeginningOfLine:`, deletes. Cocoa binds
    /// no Ctrl-U, so the terminal's convention is the one to follow. One
    /// undoable edit, kept for Ctrl-Y as Ctrl-K's kill is; a ``SecureField``
    /// deletes the same text and keeps none of it. In a field on one line the
    /// line is the whole text before the caret; in a vertical field and in
    /// ``TextEditor``, the caret's logical line, so Ctrl-U at the start of a
    /// line kills nothing and never crosses a line break.
    case killToStartOfLine
    /// Ctrl-W: kills the word before the caret, as readline's
    /// `unix-word-rubout` does in a shell at a terminal (``wordRuboutStart(in:before:lineStart:)``):
    /// one undoable edit, kept for Ctrl-Y; a ``SecureField`` deletes and keeps
    /// nothing. Like Ctrl-U it keeps the key from an app's shortcut on it, an
    /// app's ⌘W among them (owner ruling O9, 2026-10-26: a text field's ⌃W
    /// comes first), and stays on the caret's line.
    case killWordBackward

    /// The command a Control chord names, or `nil` when it names none here.
    /// Option held as well changes nothing; Shift changes Z from undo to redo.
    init?(control character: Character, shift: Bool = false) {
        switch character {
        case "c", "C": self = .copy
        case "x", "X": self = .cut
        case "v", "V": self = .paste
        case "z", "Z": self = shift ? .redo : .undo
        case "u", "U": self = .killToStartOfLine
        case "w", "W": self = .killWordBackward
        default: return nil
        }
    }
}
