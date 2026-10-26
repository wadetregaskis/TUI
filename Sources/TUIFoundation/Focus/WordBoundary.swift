//  🖥️ TUI — A Terminal UI framework for Swift
//  WordBoundary.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// Where a word starts and ends, for word-wise cursor motion and word deletion.
///
/// One definition, because there were two and they disagreed. `TextField`
/// counted `_` as part of a word — "the readline convention", said its comment
/// — and `TextEditor` did not, so Option-Left over `foo_bar` reached the start
/// of the token in a single-line field and stopped in the middle of it in the
/// multi-line one. Nothing about a control's line count should change what a
/// word is, and the underscore reading is the one that wins: `_` inside an
/// identifier is not a word break to anyone who typed it, and the editor is the
/// control more likely to hold code.
///
/// The scans are pure functions of a character array and an index, which is
/// what lets both controls share them: a `TextField` walks its whole text, a
/// `TextEditor` walks one line, and neither cares which it is.
///
/// It lives in TUIFoundation, below the text inputs, because the screen
/// selection's double-click selects a word by the same rule
/// (`ScreenSelection.wordBounds(at:in:clip:)`), and TUIFoundation cannot
/// see a module built on it (the module split plan's K5).
package enum WordBoundary {

    /// Whether `character` is part of a word — letters, digits and underscore.
    /// Everything else separates words.
    static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    /// The kinds of character a double-click's run is one of.
    package enum Kind {
        /// A word's: ``isWordCharacter(_:)``.
        case word
        /// A blank: a space, a tab.
        case blank
        /// Anything else: punctuation, symbols.
        case mark
    }

    /// Which ``Kind`` `character` is.
    package static func kind(of character: Character) -> Kind {
        if isWordCharacter(character) { return .word }
        return character.isWhitespace ? .blank : .mark
    }

    /// The run of one ``Kind`` around the character at `index` — a word, the
    /// blanks between words, or a run of marks: what a double-click in a text
    /// input selects. At the end of the text it is the run before, as a
    /// double-click past the last word selects that word; a line break is a
    /// run of its own, as `NSTextView` selects one alone (macOS 15.8).
    package static func run(in characters: [Character], around index: Int) -> Range<Int> {
        guard !characters.isEmpty else { return 0..<0 }
        let index = min(max(0, index), characters.count - 1)
        guard !characters[index].isNewline else { return index..<(index + 1) }
        let wanted = kind(of: characters[index])
        func extends(_ character: Character) -> Bool {
            !character.isNewline && kind(of: character) == wanted
        }
        var start = index
        while start > 0, extends(characters[start - 1]) { start -= 1 }
        var end = index + 1
        while end < characters.count, extends(characters[end]) { end += 1 }
        return start..<end
    }

    /// The index of the start of the word at or before `index`: skip any
    /// separator run, then the word run.
    ///
    /// From the start of a word this lands on the start of the PREVIOUS word,
    /// which is what makes repeated Option-Left walk backwards a word at a time.
    package static func previous(in characters: [Character], from index: Int) -> Int {
        var position = min(index, characters.count)
        while position > 0, !isWordCharacter(characters[position - 1]) { position -= 1 }
        while position > 0, isWordCharacter(characters[position - 1]) { position -= 1 }
        return position
    }

    /// The index of the end of the word at or after `index`: skip any separator
    /// run, then the word run.
    package static func next(in characters: [Character], from index: Int) -> Int {
        var position = max(0, index)
        while position < characters.count, !isWordCharacter(characters[position]) {
            position += 1
        }
        while position < characters.count, isWordCharacter(characters[position]) {
            position += 1
        }
        return position
    }
}
