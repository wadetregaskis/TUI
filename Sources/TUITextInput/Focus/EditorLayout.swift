//  🖥️ TUI — A Terminal UI framework for Swift
//  EditorLayout.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// A ``TextEditor``'s document laid out: split into lines once for each text
/// the binding holds, rather than once per use.
///
/// The editor used to split its whole document into lines four times over: in
/// its measure, its render, every key's handling and every pointer event's.
/// Its handler keeps one of these instead, keyed by the text it was made from.
/// An untouched document costs one string comparison a frame — `String ==`
/// answers from the storage when the binding hands back the same string — and
/// an edit, which the editor writes itself, is made from the layout before it
/// (``replacing(_:)``, ``laidOut(_:reusingStorage:)``): the lines it changed
/// are spliced into the text's bytes and wrapped again, and the rest are kept
/// as they are, so a key costs the lines it touched and not the document
/// (tuitree's M4 feedback, item 3).
final class EditorLayout {
    /// The text laid out.
    private(set) var text: String

    /// Its lines, as characters, a newline between each and the next. Never
    /// empty: an empty text is one empty line.
    private(set) var lines: [TextCharacters]

    /// The line ending separator detected from the text ("\n", "\r\n", or "\r").
    let lineEnding: String

    /// Where each line starts in the text, in UTF-8 bytes.
    private(set) var lineStarts: [Int]

    /// Where each line starts in the text, in characters: a line break is one.
    private(set) var characterStarts: [Int]

    /// Whether every line break in the text is ``lineEnding``, so the text is
    /// its lines joined by it, byte for byte, and an edit can be spliced into
    /// it (``replacing(lines:)``). A text that mixes them is joined afresh by
    /// each edit, which writes every break as ``lineEnding``.
    let hasOneLineEnding: Bool

    /// The lines wrapped at the widths asked for this frame and the last
    /// (``wrapped(width:tabWidth:)``), each with the frame that last asked,
    /// and the same rows spaced by the line heights last asked for
    /// (``wrapped(width:tabWidth:gaps:)``).
    var wrappings: [(rows: WrappedRows, tabWidth: TabWidth, frame: UInt, spaced: (gaps: [Int], rows: WrappedRows)?)] = []

    /// The frame the wrappings are stamped with, moved on by ``endFrame()``.
    var frame: UInt = 0

    /// How many times this layout has wrapped its lines: what shows a frame
    /// served from the wrappings it kept rather than wrapping again.
    var wrapsMade = 0

    /// Told of every text split into lines whole (``init(text:)``), while a
    /// task binds it: the test seam that counts how often a frame lays a
    /// document out, as `DroppedMember.reporter` is one for its reports.
    @TaskLocal static var buildReporter: TaskLocalReporter<Void>?

    /// Splits `text` into its lines.
    ///
    /// Each line is its bytes between the breaks ``lineBreaks(in:)`` finds, a
    /// byte at a time: not the text split on `Character` comparisons, which
    /// walked every character of it, as a layout was made until EDMEM-1
    /// (2026-11-22). A line break is a character of its own (GB4, GB5), so a
    /// line's bytes are the characters the split found.
    convenience init(text: String) {
        Self.buildReporter?()
        let breaks = Self.lineBreaks(in: text)
        // Bridged text read as UTF-8 once, so the offsets below are O(1).
        var source = text
        source.makeContiguousUTF8()
        let utf8 = source.utf8
        let starts = breaks.starts
        var lines: [TextCharacters] = []
        lines.reserveCapacity(starts.count)
        var lower = utf8.startIndex
        for index in starts.indices {
            var length = utf8.count - starts[index]
            if index + 1 < starts.count {
                // Less the break: a CRLF's two bytes, a CR's or an LF's one.
                length = starts[index + 1] - starts[index] - 1
                if length > 0, utf8[utf8.index(lower, offsetBy: length)] == 0x0A,
                    utf8[utf8.index(lower, offsetBy: length - 1)] == 0x0D
                {
                    length -= 1
                }
            }
            let upper = utf8.index(lower, offsetBy: length)
            lines.append(TextCharacters(source[lower..<upper]))
            if index + 1 < starts.count { lower = utf8.index(utf8.startIndex, offsetBy: starts[index + 1]) }
        }
        self.init(text: text, lines: lines, breaks: breaks)
    }

    /// The layout of `text`, whose lines the caller already has — the editor's
    /// own edit, written as these lines joined.
    convenience init(text: String, lines: [TextCharacters], lineEnding: String? = nil) {
        self.init(text: text, lines: lines, lineEnding: lineEnding, breaks: Self.lineBreaks(in: text))
    }

    /// The layout of `text`, whose lines and breaks the caller has found.
    private init(
        text: String, lines: [TextCharacters], lineEnding: String? = nil,
        breaks: (starts: [Int], ending: String, isUniform: Bool)
    ) {
        self.text = text
        self.lines = lines.isEmpty ? [[]] : lines
        self.lineEnding = lineEnding ?? breaks.ending
        self.lineStarts = breaks.starts
        self.hasOneLineEnding = breaks.isUniform
        self.characterStarts = Self.characterStarts(of: self.lines)
    }

    /// A layout made by ``laidOut(_:reusingStorage:)``, with its parts
    /// worked out there.
    private init(
        text: String, lines: [TextCharacters], lineEnding: String, lineStarts: [Int], characterStarts: [Int]
    ) {
        self.text = text
        self.lines = lines
        self.lineEnding = lineEnding
        self.lineStarts = lineStarts
        self.characterStarts = characterStarts
        self.hasOneLineEnding = true
    }

    /// The text's line breaks: where each line starts, in bytes; the ending
    /// the text uses — CRLF if it has one, else a lone CR if it has one, else
    /// LF — and whether it uses no other.
    ///
    /// A byte at a time: a line break is a grapheme of its own (Unicode's
    /// rules GB4 and GB5 break after and before every CR and LF), so its bytes
    /// are where its character is.
    static func lineBreaks(in text: String) -> (starts: [Int], ending: String, isUniform: Bool) {
        lineBreaks(inBytes: text.utf8)
    }

    /// ``lineBreaks(in:)`` of `bytes`, which start at byte `base` of a text:
    /// the starts are the text's, the first of them `base`.
    static func lineBreaks(
        inBytes bytes: some Sequence<UInt8>, startingAt base: Int = 0
    ) -> (starts: [Int], ending: String, isUniform: Bool) {
        var starts = [base]
        var kinds = (lf: false, crlf: false, cr: false)
        // A CR seen, which the byte after it says is a CRLF's or a lone one.
        var afterCR = false
        var offset = base
        for byte in bytes {
            if afterCR {
                afterCR = false
                if byte == 0x0A {
                    kinds.crlf = true
                    starts.append(offset + 1)
                    offset += 1
                    continue
                }
                kinds.cr = true
                starts.append(offset)
            }
            if byte == 0x0D {
                afterCR = true
            } else if byte == 0x0A {
                kinds.lf = true
                starts.append(offset + 1)
            }
            offset += 1
        }
        if afterCR {
            kinds.cr = true
            starts.append(offset)
        }
        let ending = kinds.crlf ? "\r\n" : kinds.cr ? "\r" : "\n"
        let seen = [kinds.lf, kinds.crlf, kinds.cr].filter { $0 }.count
        return (starts, ending, seen <= 1)
    }

    /// Where each of `lines` starts, in characters, a line break between each
    /// and the next.
    private static func characterStarts(of lines: [TextCharacters]) -> [Int] {
        var starts: [Int] = []
        starts.reserveCapacity(lines.count)
        var next = 0
        for line in lines {
            starts.append(next)
            next += line.count + 1
        }
        return starts
    }
}

// MARK: - An edit

extension EditorLayout {
    /// An edit to a layout's lines, as ``replacing(_:)`` makes it: the text it
    /// leaves, and what of the lines it changed, to be laid out
    /// (``laidOut(_:reusingStorage:)``) once the binding has taken the text.
    struct Edit {
        /// The text with the edit made.
        let text: String
        /// The lines of the layout before it that the edit replaced
        /// (``EditorLayout/lines`` indices), and those of the layout after it
        /// that took their place.
        let replaced: Range<Int>
        let replacement: Range<Int>
        /// The lines in ``replacement``, each as its string's characters.
        let lines: [TextCharacters]
        /// Where they start in the text, in bytes and in characters.
        fileprivate let lineStarts: [Int]
        fileprivate let characterStarts: [Int]
        /// How far the lines after them moved, in bytes and in characters.
        fileprivate let byteShift: Int
        fileprivate let characterShift: Int

        /// Whether the edit changed no line: its layout is the one before.
        var isUnchanged: Bool { replaced.isEmpty && replacement.isEmpty }
    }

    /// The text `edited` is, made from this layout's: the lines that differ
    /// from this layout's, at its start and its end, are spliced into its
    /// text's bytes, and the rest is kept, so an edit costs the lines it
    /// changed and a copy of the bytes, not the whole document read again as
    /// characters. `nil` where the text has more than one kind of line break
    /// (``hasOneLineEnding``): there every break is written as
    /// ``lineEnding``, as joining the lines writes it.
    ///
    /// `edited`'s base must be this layout's ``lines``: every line outside
    /// the span it replaced is taken as this layout's own, unchanged, so the
    /// scans for the first and last line that differ start at that span's
    /// edges rather than at the document's ends. They find the lines a scan
    /// from the ends would: a line that is the base's own is the same line.
    ///
    /// Nothing of this layout changes: the binding can refuse the text, and
    /// the layout of the text it keeps is this one.
    ///
    /// Each line the edit replaced is laid out as its string's characters
    /// (``segmented(_:)``), whatever characters the edit put together.
    func replacing(_ edited: EditedLines) -> Edit? {
        // Never empty from an editor's lines: an empty text is one empty line.
        guard hasOneLineEnding, edited.count >= 1 else { return nil }
        let old = lines
        let newCount = edited.count
        let shorter = min(old.count, newCount)
        var first = min(edited.replaced.lowerBound, shorter)
        while first < shorter, Self.same(old[first], edited[first]) { first += 1 }
        if first == old.count, first == newCount {
            return Edit(
                text: text, replaced: first..<first, replacement: first..<first, lines: [], lineStarts: [],
                characterStarts: [], byteShift: 0, characterShift: 0)
        }
        var kept = min(old.count - edited.replaced.upperBound, shorter - first)
        while kept < shorter - first, Self.same(old[old.count - 1 - kept], edited[newCount - 1 - kept]) {
            kept += 1
        }
        let replaced = first..<(old.count - kept)
        let replacement = first..<(newCount - kept)
        // Copied only where one changes, which an edit rarely makes one do.
        // Compared character by character, not by count: regional indicators
        // can pair afresh and keep it — "🇺" before "🇸🇬" is "🇺🇸" and "🇬".
        let newLines = replacement.map { index in
            let line = edited[index]
            let segmented = Self.segmented(line)
            return Self.same(segmented, line) ? line : segmented
        }
        let ending = Array(lineEnding.utf8)
        let total = text.utf8.count

        // The bytes the edit replaces, and those it puts there: each new line
        // with the break after it while lines follow, else the break before
        // it, or nothing where lines at the end went.
        var bytes: [UInt8] = []
        var lengths: [Int] = []
        lengths.reserveCapacity(replacement.count)
        let span: Range<Int>
        var firstStart: Int
        if kept > 0 {
            span = lineStarts[replaced.lowerBound]..<lineStarts[replaced.upperBound]
            firstStart = span.lowerBound
            for line in newLines {
                let utf8 = line.string.utf8
                lengths.append(utf8.count)
                bytes += utf8
                bytes += ending
            }
        } else if first < old.count {
            if replacement.isEmpty {
                // Lines at the end gone, with the break before them.
                span = (lineStarts[first] - ending.count)..<total
            } else {
                span = lineStarts[first]..<total
            }
            firstStart = span.lowerBound
            for (index, line) in newLines.enumerated() {
                if index > 0 { bytes += ending }
                let utf8 = line.string.utf8
                lengths.append(utf8.count)
                bytes += utf8
            }
        } else {
            // Lines added at the end.
            span = total..<total
            firstStart = total + ending.count
            for line in newLines {
                let utf8 = line.string.utf8
                lengths.append(utf8.count)
                bytes += ending
                bytes += utf8
            }
        }
        let newText = Self.splicing(text, bytes: span, with: bytes)

        // Where the lines start: the kept ones before as they were, the new
        // ones where their bytes went, the kept ones after moved by as much
        // as the edit grew or shrank the text.
        var newStarts: [Int] = []
        var newCharacters: [Int] = []
        newStarts.reserveCapacity(replacement.count)
        newCharacters.reserveCapacity(replacement.count)
        var characterStart =
            first < old.count ? characterStarts[first] : characterStarts[old.count - 1] + old[old.count - 1].count + 1
        for (line, length) in zip(newLines, lengths) {
            newStarts.append(firstStart)
            newCharacters.append(characterStart)
            firstStart += length + ending.count
            characterStart += line.count + 1
        }
        // Nothing follows the replaced lines unless some were kept after them.
        return Edit(
            text: newText, replaced: replaced, replacement: replacement, lines: newLines, lineStarts: newStarts,
            characterStarts: newCharacters,
            byteShift: kept > 0 ? firstStart - lineStarts[replaced.upperBound] : 0,
            characterShift: kept > 0 ? characterStart - characterStarts[replaced.upperBound] : 0)
    }

    /// The layout `edit`, which ``replacing(_:)`` made from this layout,
    /// leaves: this layout's lines and line starts with the edit's spliced
    /// in, and its wrappings, the lines the edit replaced wrapped again
    /// (``WrappedRows/replaceLines(_:with:tabWidth:)``), so a key wraps the
    /// lines it touched and not the document. Made once the binding has taken
    /// the edit's text: this layout keeps no wrappings, being the layout of a
    /// text no longer there.
    ///
    /// - Parameter reusingStorage: Whether to make the edit in this layout's
    ///   own arrays, in place, leaving it the layout of an empty text: for a
    ///   layout nothing else holds, whose arrays nothing else shares. Without
    ///   it they are copied and this layout keeps its lines. A copy of forty
    ///   thousand lines, and their release with this layout, were 26.8% of
    ///   the `bigtext` session's time until 2026-11-19.
    func laidOut(_ edit: Edit, reusingStorage: Bool) -> EditorLayout {
        if edit.isUnchanged { return self }
        var (newLines, starts, characters) = (lines, lineStarts, characterStarts)
        if reusingStorage {
            // Let go, so the arrays above are the only references to them.
            (text, lines, lineStarts, characterStarts) = ("", [[]], [0], [0])
        }
        newLines.replaceSubrange(edit.replaced, with: edit.lines)
        Self.splice(&starts, edit.replaced, with: edit.lineStarts, shiftingRestBy: edit.byteShift)
        Self.splice(&characters, edit.replaced, with: edit.characterStarts, shiftingRestBy: edit.characterShift)
        let layout = EditorLayout(
            text: edit.text, lines: newLines, lineEnding: lineEnding, lineStarts: starts, characterStarts: characters)
        if !wrappings.isEmpty {
            var taken = wrappings
            wrappings = []
            for index in taken.indices {
                taken[index].rows.replaceLines(
                    edit.replaced, with: newLines[edit.replacement], tabWidth: taken[index].tabWidth)
                // Spaced by the gaps of the lines before the edit.
                taken[index].spaced = nil
            }
            layout.wrappings = taken
            layout.frame = frame
        }
        return layout
    }

    /// `text` with the bytes in `span` given way to `inserted`: the bytes kept
    /// copied once, as blocks, into a string made the size it ends up.
    ///
    /// Not the bytes spliced into an array and decoded, as an edit was made
    /// until 2026-11-19: that copied the text twice and checked every byte of
    /// it was UTF-8, which the text's own bytes are, and was 17.9% of the
    /// `bigtext` session's time. Only the inserted lines' bytes are decoded.
    static func splicing(_ text: String, bytes span: Range<Int>, with inserted: [UInt8]) -> String {
        var source = text
        // Bridged text read as UTF-8 once, so the offsets below are bytes.
        source.makeContiguousUTF8()
        let utf8 = source.utf8
        let lower = utf8.index(utf8.startIndex, offsetBy: span.lowerBound)
        let upper = utf8.index(utf8.startIndex, offsetBy: span.upperBound)
        var spliced = String()
        spliced.reserveCapacity(utf8.count - span.count + inserted.count)
        spliced.append(contentsOf: source[..<lower])
        // Bytes, not `Data`: whole lines' UTF-8, from their characters.
        // swiftlint:disable:next optional_data_string_conversion
        spliced.append(contentsOf: String(decoding: inserted, as: UTF8.self))
        spliced.append(contentsOf: source[upper...])
        return spliced
    }

    /// `starts` with its entries in `replaced` giving way to `inserted`, and
    /// those after them moved by `shift`, in place: in the array itself where
    /// nothing else shares it (``laidOut(_:reusingStorage:)``), else in its
    /// copy.
    ///
    /// Not the prefix copied into an array, that array grown (copied again)
    /// and the rest appended an entry at a time through a lazy map, as both
    /// of a key's line-start arrays were made until 2026-11-19: 3.6% of the
    /// `bigtext` session's time then.
    static func splice(_ starts: inout [Int], _ replaced: Range<Int>, with inserted: [Int], shiftingRestBy shift: Int) {
        starts.replaceSubrange(replaced, with: inserted)
        guard shift != 0 else { return }
        for index in (replaced.lowerBound + inserted.count)..<starts.count { starts[index] += shift }
    }

    /// `line` as its string's characters. An edit that takes characters out
    /// of a line, or joins two, can leave a combining mark, a joiner or a
    /// regional indicator beside the character it belongs to — "e" and a line
    /// that began with a combining acute, joined, are "é" — and kept apart, the
    /// line put the caret, and the next character typed, between them: the
    /// accent went to the "Y" typed after the "e". An insertion's characters
    /// merge as they are typed, as the string's own do.
    static func segmented(_ line: TextCharacters) -> TextCharacters {
        line.segmented()
    }

    /// Whether two lines are the same characters, byte for byte
    /// (``TextCharacters/hasSameBytes(as:)``). Not `==`, which takes
    /// canonically equivalent characters for one.
    private static func same(_ a: TextCharacters, _ b: TextCharacters) -> Bool {
        a.hasSameBytes(as: b)
    }
}

// MARK: - Character offsets

extension EditorLayout: TextCharacterOffsets {
    /// The line the character `offset` is on, and its column there.
    func position(ofCharacter offset: Int) -> TextEditorPosition {
        let offset = max(0, offset)
        let line = Self.lastIndex(in: characterStarts, atOrBefore: offset)
        return TextEditorPosition(line: line, column: min(offset - characterStarts[line], lines[line].count))
    }

    /// `position` as a character offset into the text, line breaks counted.
    func characterOffset(of position: TextEditorPosition) -> Int {
        let line = min(max(0, position.line), lines.count - 1)
        return characterStarts[line] + min(max(0, position.column), lines[line].count)
    }

    func offset(of index: String.Index, in text: String) -> Int {
        guard index > text.startIndex else { return 0 }
        guard index < text.endIndex else {
            // Typed in steps: as one expression it exceeded the type-check guard.
            let last: Int = lines.count - 1
            let lastStart: Int = characterStarts[last]
            return lastStart + lines[last].count
        }
        // Onto the character the index is in, as the editor's characters are.
        let index = text.index(index, offsetBy: 0)
        let byte = text.utf8.distance(from: text.utf8.startIndex, to: index)
        let line = Self.lastIndex(in: lineStarts, atOrBefore: byte)
        let start = text.utf8.index(text.utf8.startIndex, offsetBy: lineStarts[line])
        return characterStarts[line] + min(text[start..<index].count, lines[line].count)
    }

    func index(atOffset offset: Int, in text: String) -> String.Index {
        let position = position(ofCharacter: offset)
        guard offset <= characterOffset(of: TextEditorPosition(line: lines.count - 1, column: .max)) else {
            return text.endIndex
        }
        let bytes = lines[position.line].utf8Offset(of: position.column)
        return text.utf8.index(text.utf8.startIndex, offsetBy: lineStarts[position.line] + bytes)
    }

    /// Each of `offsets`, UTF-8 offsets into the text in ascending order, on
    /// a character's edge, as a line and a column: in one walk of each line
    /// as far as its last, however many fall in it.
    func positions(ofUTF8 offsets: [Int]) -> [TextEditorPosition] {
        var positions: [TextEditorPosition] = []
        positions.reserveCapacity(offsets.count)
        var (line, column, byte) = (-1, 0, 0)
        for offset in offsets {
            let found = self.line(containingUTF8Offset: offset)
            if found != line { (line, column, byte) = (found, 0, lineStarts[found]) }
            let characters = lines[line]
            while column < characters.count, byte < offset {
                byte += characters.utf8Length(of: column)
                column += 1
            }
            positions.append(TextEditorPosition(line: line, column: column))
        }
        return positions
    }

    /// The line the byte at `offset` is in, a line's break counted as its
    /// own: the last line for an offset past the text.
    func line(containingUTF8Offset offset: Int) -> Int {
        Self.lastIndex(in: lineStarts, atOrBefore: offset)
    }

    /// The last index of `starts`, ascending from 0, whose value is at most
    /// `value`.
    private static func lastIndex(in starts: [Int], atOrBefore value: Int) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= value { low = middle } else { high = middle - 1 }
        }
        return low
    }
}
