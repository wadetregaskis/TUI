//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Text+Concatenation.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore
import TUIkitStyling

// MARK: - Runs

extension Text {
    /// One differently-styled fragment of a ``Text``: a Markdown span of its
    /// key, a run of its attributed string, or an interpolated `Text`'s.
    ///
    /// A run carries only the attributes that fragment set for **itself**. The
    /// enclosing `Text`'s own style is the base beneath it, and the environment
    /// cascade beneath that — so `Text("\(Text("a").bold())b").italic()` makes
    /// both italic and only the first bold, which is what the same expression
    /// does in SwiftUI.
    package struct Run: Equatable, Sendable {
        /// The fragment's text — for a live fragment, as it read when built.
        let text: String

        /// Only what this fragment set explicitly.
        let style: TextStyle

        /// What the fragment reads at the frame being drawn, when its words
        /// are a function of the clock (`Text(date, style: .relative)` and
        /// the other live texts); `nil` for the words in ``text``.
        var live: LiveTextBox?

        /// Where the fragment links — an attributed string's `link`, or a
        /// Markdown link in a key — or `nil`. See `Text+Links.swift`.
        var link: URL?
    }
}

extension Text {
    /// This text with `prefix` in front of it, plain, as one text: its own
    /// words keep their runs (or its one style, folded into a run), and the
    /// prefix is a run of no style. For the framework's own chrome in front of
    /// an app's text — an outline table's disclosure triangle before a styled
    /// cell — where an app joins texts by interpolating them.
    package func prefixed(with prefix: String) -> Text {
        let ownRuns = runs?.map { $0.rebased(on: style) } ?? [Run(text: content, style: style)]
        var joined = Text(verbatim: prefix + content)
        joined.runs = [Run(text: prefix, style: TextStyle())] + ownRuns
        return joined
    }
}

extension Text.Run {
    /// This run with `base` beneath it: the run's own attributes win, the
    /// base fills anything it left unset.
    func rebased(on base: TextStyle) -> Self {
        Self(text: text, style: style.merged(over: base), live: live, link: link)
    }
}

// MARK: - Style merging

extension TextStyle {
    /// This style with `base` beneath it — every attribute set here wins, and
    /// anything unset falls through.
    ///
    /// "Unset" means `nil` — including for the five emphasis flags, which is
    /// what lets a run state an attribute OFF over a base that had it on. The
    /// two flags with no cascade behind them (``TextStyle/isBlink``,
    /// ``TextStyle/isInverted``) stay one-way: nothing can state them false, so
    /// an OR is all that is available and all that is needed.
    ///
    /// The font's `??` unwraps only the OUTER optional, which is the whole
    /// reason it has two: a fragment that said `.font(nil)` keeps its `nil`
    /// instead of falling through to the base's font.
    func merged(over base: TextStyle) -> TextStyle {
        var result = self
        result.foregroundColor = foregroundColor ?? base.foregroundColor
        result.backgroundColor = backgroundColor ?? base.backgroundColor
        result.font = font ?? base.font
        result.isBold = isBold ?? base.isBold
        result.isItalic = isItalic ?? base.isItalic
        result.underline = underline ?? base.underline
        result.strikethrough = strikethrough ?? base.strikethrough
        result.isDim = isDim ?? base.isDim
        result.isBlink = isBlink || base.isBlink
        result.isInverted = isInverted || base.isInverted
        result.truncationMode = truncationMode ?? base.truncationMode
        result.truncatesAtWordBoundary = truncatesAtWordBoundary || base.truncatesAtWordBoundary
        result.lineLimit = lineLimit ?? base.lineLimit
        return result
    }
}

// MARK: - Re-attributing wrapped lines

/// Maps the lines a wrap produced back onto the runs they came from.
///
/// Wrapping happens on the plain concatenation — it has to, or a break would be
/// chosen without seeing the words either side of a fragment boundary — so the
/// styling has to be put back afterwards. That is only possible because the
/// wrap **preserves every non-whitespace character, in order**: it chooses
/// break points and drops whitespace at them, and never reorders, substitutes
/// or invents. `TextConcatenationTests` pins that property over a few thousand
/// random strings and widths, so if the wrap ever stops holding to it, the
/// failure is a test rather than mis-coloured text.
enum TextRunAttribution {
    /// Splits `line` into `(text, runIndex)` fragments by walking a cursor
    /// through the source the runs describe.
    ///
    /// - Parameters:
    ///   - line: One wrapped (and possibly case-transformed) output line.
    ///   - runTexts: The runs' texts, in order, after the same transform.
    ///   - cursor: Where in the concatenated source this line starts; advanced
    ///     past what the line consumed.
    /// - Returns: The line in fragments, each tagged with its run.
    static func fragments(
        of line: String, runTexts: [String], cursor: inout (run: Int, offset: Int)
    ) -> [(text: String, run: Int)] {
        // The commonest line by far — a one-line concatenation or Markdown
        // literal, drawn unwrapped and uncut — IS the runs end to end. The
        // walk below would match every character at the cursor, skip and
        // resync nothing, and hand back each non-empty run whole; for that it
        // pays two `index(offsetBy:)` from the run's start, a `count` and an
        // append per character (~0.7 µs a Text on the `markdown` page). So
        // that line is recognised from its bytes first, and anything else —
        // a later line, a wrapped, cut or padded one — is walked as before.
        if cursor.run == 0, cursor.offset == 0, let whole = wholeRuns(of: line, runTexts: runTexts) {
            // Where the walk leaves it: just past the last run it consumed.
            // (It does not step over trailing empty runs; with no character
            // left it never looks at them.)
            if let last = whole.last { cursor = (last.run + 1, 0) }
            return whole
        }
        return walkedFragments(of: line, runTexts: runTexts, cursor: &cursor)
    }

    /// `line` as the runs laid end to end, each non-empty one whole and
    /// tagged with its index — or `nil` when `line` is anything else.
    ///
    /// The answer is ``walkedFragments(of:runTexts:cursor:)``'s for a walk
    /// from the start, whenever it is not `nil`: the bytes are the runs'
    /// bytes, and every run edge is a Character boundary of `line`
    /// (`String.Index(_:within:)` is `nil` otherwise). A string cut at its
    /// own grapheme boundaries segments into the same Characters as the
    /// whole — the regional-indicator parity restarts at a boundary, and the
    /// emoji-ZWJ and conjunct look-backs never cross one — so every
    /// Character the walk compares matches at the cursor. An edge INSIDE a
    /// grapheme (a run opening with a combining mark, a split flag) is the
    /// walk's to settle, so it is declined here.
    static func wholeRuns(of line: String, runTexts: [String]) -> [(text: String, run: Int)]? {
        let utf8 = line.utf8
        // A wrapped, cut or padded line is a different LENGTH from the runs,
        // which is a sum of stored counts — so it is declined before anything
        // is compared or allocated.
        var length = 0
        for text in runTexts { length += text.utf8.count }
        guard length == utf8.count else { return nil }
        var position = utf8.startIndex
        var result: [(text: String, run: Int)] = []
        result.reserveCapacity(runTexts.count)
        for (run, text) in runTexts.enumerated() where !text.isEmpty {
            guard String.Index(position, within: line) != nil,
                let end = utf8.index(position, offsetBy: text.utf8.count, limitedBy: utf8.endIndex),
                utf8[position..<end].elementsEqual(text.utf8)
            else { return nil }
            result.append((text, run))
            position = end
        }
        return position == utf8.endIndex ? result : nil
    }

    /// ``fragments(of:runTexts:cursor:)`` by walking: every line, from
    /// wherever `cursor` stands.
    static func walkedFragments(
        of line: String, runTexts: [String], cursor: inout (run: Int, offset: Int)
    ) -> [(text: String, run: Int)] {
        var result: [(text: String, run: Int)] = []
        var current = ""
        var currentRun = min(cursor.run, max(0, runTexts.count - 1))

        func flush() {
            if !current.isEmpty {
                result.append((current, currentRun))
                current = ""
            }
        }

        for character in line {
            // Skip source the wrap dropped: whitespace at a break point, and
            // whole runs that were entirely whitespace.
            while cursor.run < runTexts.count {
                let text = runTexts[cursor.run]
                let index = text.index(text.startIndex, offsetBy: cursor.offset)
                if index == text.endIndex {
                    cursor.run += 1
                    cursor.offset = 0
                    continue
                }
                if text[index] == character { break }
                guard text[index].isWhitespace else { break }
                cursor.offset += 1
            }
            guard cursor.run < runTexts.count else {
                // Past the end of the source: anything left is chrome the wrap
                // added (a truncation ellipsis), which belongs to the run that
                // was being cut.
                current.append(character)
                continue
            }
            let text = runTexts[cursor.run]
            let index = text.index(text.startIndex, offsetBy: cursor.offset)
            if index < text.endIndex, text[index] == character {
                if cursor.run != currentRun {
                    flush()
                    currentRun = cursor.run
                }
                current.append(character)
                cursor.offset += 1
                if cursor.offset == text.count {
                    cursor.run += 1
                    cursor.offset = 0
                }
            } else if !character.isWhitespace,
                let resynced = Self.scanAhead(for: character, in: runTexts, from: cursor)
            {
                // The source between the cursor and here was DROPPED by a
                // truncation: an over-wide word cut mid-line leaves the
                // cursor inside it, and a .head/.middle cut drops a span the
                // whitespace-only skip above cannot cross — after which every
                // later character mismatched forever and the rest of the text
                // wore whichever run was current at the desync. Jumping to
                // the next occurrence is a nearest-match heuristic; for
                // repeated characters it can bind a step early, which costs a
                // fragment boundary a character, not the resync. Whitespace
                // never triggers it: an inserted alignment space must not eat
                // real source hunting for a space to match.
                cursor = resynced
                if cursor.run != currentRun {
                    flush()
                    currentRun = cursor.run
                }
                current.append(character)
                cursor.offset += 1
                if cursor.offset == runTexts[cursor.run].count {
                    cursor.run += 1
                    cursor.offset = 0
                }
            } else {
                // Not in the source at all: an inserted ellipsis, or
                // alignment padding. Keep it with the run in hand rather
                // than dropping it.
                current.append(character)
            }
        }
        flush()
        return result
    }

    /// The next occurrence of `character` at or after `cursor`, across run
    /// boundaries, or `nil` when the remaining source never contains it.
    private static func scanAhead(
        for character: Character, in runTexts: [String],
        from cursor: (run: Int, offset: Int)
    ) -> (run: Int, offset: Int)? {
        var run = cursor.run
        var offset = cursor.offset
        while run < runTexts.count {
            let text = runTexts[run]
            var index = text.index(text.startIndex, offsetBy: offset)
            while index < text.endIndex {
                if text[index] == character { return (run, offset) }
                offset += 1
                index = text.index(after: index)
            }
            run += 1
            offset = 0
        }
        return nil
    }
}
