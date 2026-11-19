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
/// (``replacing(lines:)``): the lines it changed are spliced into the text's
/// bytes and wrapped again, and the rest are kept as they are, so a key costs
/// the lines it touched and not the document (tuitree's M4 feedback, item 3).
final class EditorLayout {
    /// The text laid out.
    let text: String

    /// Its lines, as characters, a newline between each and the next. Never
    /// empty: an empty text is one empty line.
    let lines: [[Character]]

    /// The line ending separator detected from the text ("\n", "\r\n", or "\r").
    let lineEnding: String

    /// Where each line starts in the text, in UTF-8 bytes.
    let lineStarts: [Int]

    /// Where each line starts in the text, in characters: a line break is one.
    let characterStarts: [Int]

    /// Whether every line break in the text is ``lineEnding``, so the text is
    /// its lines joined by it, byte for byte, and an edit can be spliced into
    /// it (``replacing(lines:)``). A text that mixes them is joined afresh by
    /// each edit, which writes every break as ``lineEnding``.
    let hasOneLineEnding: Bool

    /// The lines wrapped at the widths asked for this frame and the last
    /// (``wrapped(width:tabWidth:)``), each with the frame that last asked.
    var wrappings: [(rows: WrappedRows, tabWidth: TabWidth, frame: UInt)] = []

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
    convenience init(text: String) {
        Self.buildReporter?()
        let parts = text.split(omittingEmptySubsequences: false, whereSeparator: {
            $0 == "\n" || $0 == "\r\n" || $0 == "\r"
        }).map { Array($0) }
        self.init(text: text, lines: parts)
    }

    /// The layout of `text`, whose lines the caller already has — the editor's
    /// own edit, written as these lines joined.
    init(text: String, lines: [[Character]], lineEnding: String? = nil) {
        let breaks = Self.lineBreaks(in: text)
        self.text = text
        self.lines = lines.isEmpty ? [[]] : lines
        self.lineEnding = lineEnding ?? breaks.ending
        self.lineStarts = breaks.starts
        self.hasOneLineEnding = breaks.isUniform
        self.characterStarts = Self.characterStarts(of: self.lines)
    }

    /// A layout made by ``replacing(lines:)``, with its parts worked out
    /// there.
    private init(
        text: String, lines: [[Character]], lineEnding: String, lineStarts: [Int], characterStarts: [Int]
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
    private static func lineBreaks(in text: String) -> (starts: [Int], ending: String, isUniform: Bool) {
        var starts = [0]
        var kinds = (lf: false, crlf: false, cr: false)
        // A CR seen, which the byte after it says is a CRLF's or a lone one.
        var afterCR = false
        var offset = 0
        for byte in text.utf8 {
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
    private static func characterStarts(of lines: [[Character]]) -> [Int] {
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
    /// An edit to a layout's lines, as ``replacing(lines:)`` makes it: the
    /// text it leaves, and what of the layout it changed.
    struct Edit {
        /// The text with the edit made.
        let text: String
        /// Its layout.
        let layout: EditorLayout
        /// The lines of the layout before it that the edit replaced
        /// (``EditorLayout/lines`` indices), and those of the layout after it
        /// that took their place.
        let replaced: Range<Int>
        let replacement: Range<Int>
    }

    /// The text `newLines` are, and its layout, made from this layout's: the
    /// lines that differ from this layout's, at its start and its end, are
    /// spliced into its text's bytes, and the rest is kept, so an edit costs
    /// the lines it changed and a copy of the bytes, not the whole document
    /// read again as characters. `nil` where the text has more than one kind
    /// of line break (``hasOneLineEnding``): there every break is written as
    /// ``lineEnding``, as joining the lines writes it.
    ///
    /// The layout's wrappings are not carried over until the text is known to
    /// be written (``adoptWrappings(of:for:)``): a binding can refuse it.
    ///
    /// Each line the edit replaced is laid out as its string's characters
    /// (``segmented(_:)``), whatever characters the edit put together.
    func replacing(lines newLines: [[Character]]) -> Edit? {
        guard hasOneLineEnding, !newLines.isEmpty else { return nil }
        var newLines = newLines
        let old = lines
        let shorter = min(old.count, newLines.count)
        var first = 0
        while first < shorter, Self.same(old[first], newLines[first]) { first += 1 }
        if first == old.count, first == newLines.count {
            return Edit(text: text, layout: self, replaced: first..<first, replacement: first..<first)
        }
        var kept = 0
        while kept < shorter - first, Self.same(old[old.count - 1 - kept], newLines[newLines.count - 1 - kept]) {
            kept += 1
        }
        let replaced = first..<(old.count - kept)
        let replacement = first..<(newLines.count - kept)
        // Copied only where one changes, which an edit rarely makes one do.
        // Compared character by character, not by count: regional indicators
        // can pair afresh and keep it — "🇺" before "🇸🇬" is "🇺🇸" and "🇬".
        for index in replacement {
            let segmented = Self.segmented(newLines[index])
            if !Self.same(segmented, newLines[index]) { newLines[index] = segmented }
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
            for line in newLines[replacement] {
                let utf8 = String(line).utf8
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
            for (index, line) in newLines[replacement].enumerated() {
                if index > 0 { bytes += ending }
                let utf8 = String(line).utf8
                lengths.append(utf8.count)
                bytes += utf8
            }
        } else {
            // Lines added at the end.
            span = total..<total
            firstStart = total + ending.count
            for line in newLines[replacement] {
                let utf8 = String(line).utf8
                lengths.append(utf8.count)
                bytes += ending
                bytes += utf8
            }
        }

        // Copied from the text's contiguous bytes, as a block: through its
        // UTF-8 view, a byte at a time, the copy was most of a key's cost.
        var source = text
        let newText = source.withUTF8 { old in
            var spliced: [UInt8] = []
            spliced.reserveCapacity(total - span.count + bytes.count)
            unsafe spliced.append(contentsOf: old[..<span.lowerBound])
            spliced += bytes
            unsafe spliced.append(contentsOf: old[span.upperBound...])
            // Bytes, not `Data`: the text's own UTF-8 around whole lines'.
            // swiftlint:disable:next optional_data_string_conversion
            return String(decoding: spliced, as: UTF8.self)
        }

        // Where the lines start: the kept ones before as they were, the new
        // ones where their bytes went, the kept ones after moved by as much
        // as the edit grew or shrank the text.
        var newStarts: [Int] = []
        var newCharacters: [Int] = []
        newStarts.reserveCapacity(replacement.count)
        newCharacters.reserveCapacity(replacement.count)
        var characterStart =
            first < old.count ? characterStarts[first] : characterStarts[old.count - 1] + old[old.count - 1].count + 1
        for (line, length) in zip(newLines[replacement], lengths) {
            newStarts.append(firstStart)
            newCharacters.append(characterStart)
            firstStart += length + ending.count
            characterStart += line.count + 1
        }
        // Nothing follows the replaced lines unless some were kept after them.
        let byteShift = kept > 0 ? firstStart - lineStarts[replaced.upperBound] : 0
        let characterShift = kept > 0 ? characterStart - characterStarts[replaced.upperBound] : 0
        let starts = Self.splicing(lineStarts, replaced, with: newStarts, shiftingRestBy: byteShift)
        let characters = Self.splicing(characterStarts, replaced, with: newCharacters, shiftingRestBy: characterShift)
        let layout = EditorLayout(
            text: newText, lines: newLines, lineEnding: lineEnding, lineStarts: starts, characterStarts: characters)
        return Edit(text: newText, layout: layout, replaced: replaced, replacement: replacement)
    }

    /// `starts` with its entries in `replaced` giving way to `inserted`, and
    /// those after them moved by `shift`: one buffer, the entries kept copied
    /// into it as blocks and the moved ones shifted where they landed.
    ///
    /// Not the prefix copied into an array, that array grown (copied again)
    /// and the rest appended an entry at a time through a lazy map, as both
    /// of a key's line-start arrays were made until 2026-11-19: 3.6% of the
    /// `bigtext` session's time then, 1.4% so. Still a copy of the whole
    /// array, not a splice in place: the layout before keeps its own, as it
    /// keeps its wrappings (``adoptWrappings(of:for:)``), until the binding
    /// takes the edit, and one it refuses leaves that layout the handler's.
    static func splicing(_ starts: [Int], _ replaced: Range<Int>, with inserted: [Int], shiftingRestBy shift: Int)
        -> [Int]
    {
        var spliced: [Int] = []
        spliced.reserveCapacity(starts.count - replaced.count + inserted.count)
        spliced += starts[..<replaced.lowerBound]
        spliced += inserted
        let moved = spliced.count
        spliced += starts[replaced.upperBound...]
        if shift != 0 {
            for index in moved..<spliced.count { spliced[index] += shift }
        }
        return spliced
    }

    /// `line` as its string's characters. An edit that takes characters out
    /// of a line, or joins two, can leave a combining mark, a joiner or a
    /// regional indicator beside the character it belongs to — "e" and a line
    /// that began with a combining acute, joined, are "é" — and kept apart, the
    /// line put the caret, and the next character typed, between them: the
    /// accent went to the "Y" typed after the "e". An insertion's characters
    /// merge as they are typed, as the string's own do.
    static func segmented(_ line: [Character]) -> [Character] {
        Array(String(line))
    }

    /// Whether two lines are the same characters, byte for byte: at once where
    /// they share storage, as the lines an edit left alone do. Not `==`, which
    /// takes canonically equivalent characters for one.
    private static func same(_ a: [Character], _ b: [Character]) -> Bool {
        guard a.count == b.count else { return false }
        // The closures' pointer types are unsafe before Swift 6.4, and not
        // from it, which warns of an `unsafe` with nothing unsafe in it.
        #if compiler(>=6.4)
            let shared = a.withUnsafeBufferPointer { x in
                b.withUnsafeBufferPointer { y in unsafe x.baseAddress == y.baseAddress }
            }
        #else
            let shared = unsafe a.withUnsafeBufferPointer { x in
                unsafe b.withUnsafeBufferPointer { y in unsafe x.baseAddress == y.baseAddress }
            }
        #endif
        if shared { return true }
        return zip(a, b).allSatisfy { $0.utf8.elementsEqual($1.utf8) }
    }

    /// Takes `old`'s wrappings for this layout, which `edit` made from it:
    /// the lines it replaced wrapped again, the rest kept, so a key wraps the
    /// lines it touched and not the document. `old` keeps none: it is the
    /// layout of a text no longer there.
    func adoptWrappings(of old: EditorLayout, for edit: Edit) {
        guard edit.layout === self, old !== self, !old.wrappings.isEmpty else { return }
        var taken = old.wrappings
        old.wrappings = []
        for index in taken.indices {
            taken[index].rows.replaceLines(
                edit.replaced, with: lines[edit.replacement], tabWidth: taken[index].tabWidth)
        }
        wrappings = taken
        frame = old.frame
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
        let line = lines[position.line]
        let bytes = line[..<position.column].reduce(0) { $0 + $1.utf8.count }
        return text.utf8.index(text.utf8.startIndex, offsetBy: lineStarts[position.line] + bytes)
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
