//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextFieldHandler+MultiClick.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Multi-click selection

/// What a double- or triple-click in a text input selects, and what a drag
/// after it extends by.
enum TextSelectionGranularity {
    /// A double-click's: the word, the run of blanks, or the marks clicked.
    case word
    /// A triple-click's: the paragraph clicked, with the line break that ends
    /// it — a field's whole text unless it holds line breaks, an editor's line.
    case paragraph

    /// The granularity of a press's click count, or `nil` for a single click.
    init?(clickCount: Int) {
        switch clickCount {
        case ..<2: return nil
        case 2: self = .word
        default: self = .paragraph
        }
    }
}

extension TextFieldHandler {
    /// The run of `granularity` around the character at `offset`.
    ///
    /// Measured against AppKit on macOS 15.8 (`NSTextView`'s
    /// `selectionRange(forProposedRange:granularity:)` on a field's editor):
    /// a word is the run of one kind of character, a run of blanks included;
    /// past the end it is the last run; a paragraph includes the line break
    /// that ends it; and a `SecureField` selects all of its text for a word,
    /// as `NSSecureTextField` does, which shows no word breaks. AppKit's word
    /// also joins letters across a full stop (`abc.def`); TUIkit's word is
    /// ``WordBoundary``'s, which Option-arrows already use.
    func range(of granularity: TextSelectionGranularity, around offset: Int) -> Range<Int> {
        let characters = Array(text.wrappedValue)
        switch granularity {
        case .word where isSecure:
            return 0..<characters.count
        case .word:
            return WordBoundary.run(in: characters, around: offset)
        case .paragraph:
            let offset = min(max(0, offset), characters.count)
            let start = characters[..<offset].lastIndex(of: "\n").map { $0 + 1 } ?? 0
            let end = characters[offset...].firstIndex(of: "\n").map { $0 + 1 } ?? characters.count
            return start..<end
        }
    }

    /// Selects the run of `granularity` around `offset`, a multi-click's, and
    /// remembers it for a drag that follows to extend from.
    func selectRun(_ granularity: TextSelectionGranularity, around offset: Int) {
        let range = range(of: granularity, around: offset)
        multiClickRun = (granularity, range)
        selectionAnchor = range.lowerBound
        cursorPosition = range.upperBound
        rowStartHead = nil
        pressAnchor = nil
    }

    /// Extends a multi-click's selection by its runs to the one around
    /// `offset`, keeping the run first clicked selected whichever way the
    /// drag goes. Returns `false`, changing nothing, when the press was not a
    /// multi-click.
    func extendRun(to offset: Int) -> Bool {
        guard let (granularity, clicked) = multiClickRun else { return false }
        let range = range(of: granularity, around: offset)
        if range.lowerBound < clicked.lowerBound {
            selectionAnchor = clicked.upperBound
            cursorPosition = range.lowerBound
        } else {
            selectionAnchor = clicked.lowerBound
            cursorPosition = max(range.upperBound, clicked.upperBound)
        }
        rowStartHead = nil
        return true
    }
}
