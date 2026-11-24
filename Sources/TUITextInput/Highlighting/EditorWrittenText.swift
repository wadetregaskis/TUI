//  🖥️ TUI — A Terminal UI framework for Swift
//  EditorWrittenText.swift
//
//  A text written whole into a highlighted TextEditor (the app's own write,
//  the editor's undo and redo) told to its highlight session as an edit of
//  the text before it (B-ATTRED-58): the bytes the two share at either end
//  found by `memcmp`, rounded out to whole lines, so the lines the write did
//  not touch keep their tokens and the highlighter is given a change.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Synchronization
import TUIFoundation

extension TextEditorHighlightSession {
    /// The text is now `string`, whose lines start at `lineStarts`, written
    /// whole: told as the edit it is of the text the session had, or not at
    /// all where it is that text. Returns the lines whose tokens went because
    /// they left the window.
    func textWritten(to string: String, lineStarts: [Int]) -> [Int] {
        let (old, lineCount, window, isClosed) = state.withLock { ($0.string, $0.lineCount, $0.window, $0.isClosed) }
        guard !isClosed else { return [] }
        // Only the main actor tells the session of the editor's text, so the
        // text read is still the session's when it is told.
        switch EditorWrittenText(string, lineStarts: lineStarts, over: old, lineCount: lineCount, window: window) {
        case .same: return []
        case .whole: return textChanged(to: string, lineCount: lineStarts.count, by: nil)
        case .edit(let edit): return textChanged(to: string, lineCount: lineStarts.count, by: edit)
        }
    }
}

/// What a text written whole is, to the text the session had.
enum EditorWrittenText {
    /// The same text: nothing to tell.
    case same
    /// Nothing in common, at either end: a text all new.
    case whole
    /// An edit of the last text, as the editor's own are told
    /// (``TextEditorHandler/highlightEdit(_:from:)``).
    case edit(EditorHighlightEdit)

    /// `new`, whose lines start at `starts`, as a write over `old`, of
    /// `oldLineCount` lines: the lines from the first the two texts differ in
    /// to the last, at line starts both texts share. The lines of `window`
    /// edited in place carry their tokens, shifted, as a key's line does
    /// (B-ATTRED-41), unless the lines edited are far more than a window's.
    init(
        _ new: String, lineStarts starts: [Int], over old: String, lineCount oldLineCount: Int,
        window: Range<Int>
    ) {
        let (oldBytes, newBytes) = (old.utf8, new.utf8)
        let (oldTotal, newTotal) = (oldBytes.count, newBytes.count)
        let (prefix, suffix) = Self.commonEnds(old, new)
        if prefix == oldTotal, prefix == newTotal {
            self = .same
            return
        }
        if prefix == 0, suffix == 0 {
            self = .whole
            return
        }
        // The first line the write touched, from its start: a line start in
        // both texts, the bytes before it shared, unless a lone CR ends the
        // line before, which an LF in the other text would have joined.
        var first = Self.lastIndex(in: starts, atOrBefore: prefix)
        if first > 0, Self.byte(newBytes, starts[first] - 1) == Self.cr { first -= 1 }
        let start = starts[first]
        // The first line after it: the first line start in the bytes shared
        // at the end, or at their start where the old text breaks a line
        // there too. Those bytes may reach back into the first line's, which
        // is a whole line's, not a byte's, worth: so a line taken whose
        // first letters are the next line's ("two" before "three") is the
        // line taken, not the two lines.
        let tail = newTotal - min(suffix, min(oldTotal, newTotal) - start)
        var end = Self.firstIndex(in: starts, atOrAfter: tail, from: first)
        if end < starts.count, starts[end] == tail,
            !Self.startsLine(oldBytes, at: tail + oldTotal - newTotal, after: start)
        {
            end += 1
        }
        let newEnd = end < starts.count ? starts[end] : newTotal
        let oldEnd = newEnd + oldTotal - newTotal
        let oldUpper = oldLineCount - (starts.count - end)
        guard oldEnd >= start, oldUpper >= first else {
            self = .whole
            return
        }
        let change = TextEditorTextChange(
            oldLines: first..<oldUpper, newLines: first..<end, oldUTF8: start..<oldEnd, newUTF8: start..<newEnd)
        // The tokens move as the editor's own edit moves them: the change's
        // first line kept where only its break is new or gone (B-ATTRED-36).
        var (replaced, replacementCount, replacedStart) = (first..<oldUpper, end - first, start)
        if first < end, first < oldUpper {
            let contentEnd = Self.contentEnd(newBytes, ofLine: first, starts: starts)
            if prefix >= contentEnd, contentEnd == oldTotal || Self.isBreak(Self.byte(oldBytes, contentEnd)) {
                replaced = (first + 1)..<oldUpper
                replacementCount -= 1
                // Past the old text's own break, which may not be the new's.
                let crlf = contentEnd + 1 < oldTotal && Self.byte(oldBytes, contentEnd) == Self.cr
                    && Self.byte(oldBytes, contentEnd + 1) == Self.lf
                replacedStart = min(oldTotal, contentEnd + (crlf ? 2 : 1))
            }
        }
        var edit = EditorHighlightEdit(change: change, replaced: replaced, replacementCount: replacementCount)
        // The highlighter's marks are carried by the bytes themselves, the
        // shared end short of the shared start (B-ATTRED-59).
        let markSuffix = min(suffix, min(oldTotal, newTotal) - prefix)
        edit.marks = EditorMarkEdit(start: prefix, oldEnd: oldTotal - markSuffix, newEnd: newTotal - markSuffix)
        if replaced.count == replacementCount, replaced.overlaps(window), replaced.count <= 4 * max(1, window.count),
            replacedStart <= oldEnd
        {
            edit.carried = Self.shifts(
                ofLines: replaced.clamped(to: window), from: replaced, old: oldBytes, at: replacedStart..<oldEnd,
                new: newBytes, starts: starts, oldLineCount: oldLineCount)
        }
        self = .edit(edit)
    }

    // MARK: - Bytes

    static let cr = UInt8(ascii: "\r")
    static let lf = UInt8(ascii: "\n")

    static func isBreak(_ byte: UInt8) -> Bool { byte == cr || byte == lf }

    /// The byte at `offset` of a native string's UTF-8, whose indices move by
    /// offsets in constant time.
    static func byte(_ utf8: String.UTF8View, _ offset: Int) -> UInt8 {
        utf8[utf8.index(utf8.startIndex, offsetBy: offset)]
    }

    /// Whether a line starts at `offset` of `utf8`: after a break there, or
    /// at `start`, which is a line's start already, or at either end.
    static func startsLine(_ utf8: String.UTF8View, at offset: Int, after start: Int) -> Bool {
        if offset == start || offset == 0 { return true }
        guard offset > start, offset <= utf8.count else { return false }
        let before = byte(utf8, offset - 1)
        if before == lf { return true }
        return before == cr && (offset == utf8.count || byte(utf8, offset) != lf)
    }

    /// Where line `line`'s characters end, before its break: at the next
    /// line's start less an LF, a CRLF or a lone CR, or at the text's end.
    static func contentEnd(_ utf8: String.UTF8View, ofLine line: Int, starts: [Int]) -> Int {
        guard line + 1 < starts.count else { return utf8.count }
        let (start, next) = (starts[line], starts[line + 1])
        if byte(utf8, next - 1) == lf, next - 2 >= start, byte(utf8, next - 2) == cr { return next - 2 }
        return next - 1
    }

    /// The shift of each of `lines`, among `replaced`, which start at
    /// `starts` in `new` and, as many of them, in the bytes `bytes` of `old`,
    /// their starts there found by a walk of those bytes alone.
    static func shifts(
        ofLines lines: Range<Int>, from replaced: Range<Int>, old: String.UTF8View, at bytes: Range<Int>,
        new: String.UTF8View, starts: [Int], oldLineCount: Int
    ) -> [Int: EditorLineShift] {
        let (oldStart, oldEnd) = (bytes.lowerBound, bytes.upperBound)
        let index = { (offset: Int) in old.index(old.startIndex, offsetBy: offset) }
        var oldStarts = EditorLayout.lineBreaks(inBytes: old[index(oldStart)..<index(oldEnd)], startingAt: oldStart).starts
        // A break ending the bytes starts the line after them, which is not one of theirs.
        if oldStarts.count > replaced.count { oldStarts.removeLast(oldStarts.count - replaced.count) }
        guard oldStarts.count == replaced.count else { return [:] }
        oldStarts.append(oldEnd)
        let newIndex = { (offset: Int) in new.index(new.startIndex, offsetBy: offset) }
        var shifts: [Int: EditorLineShift] = [:]
        for line in lines {
            let at = line - replaced.lowerBound
            // A break before the next start, unless this is the old text's
            // last line.
            let (oldLine, next) = (oldStarts[at], oldStarts[at + 1])
            var oldLineEnd = next
            if at + 1 < replaced.count || replaced.upperBound < oldLineCount {
                let crlf = byte(old, next - 1) == lf && next - 2 >= oldLine && byte(old, next - 2) == cr
                oldLineEnd -= crlf ? 2 : 1
            }
            let newLineEnd = contentEnd(new, ofLine: line, starts: starts)
            shifts[line] = EditorLineShift(
                from: old[index(oldLine)..<index(oldLineEnd)], to: new[newIndex(starts[line])..<newIndex(newLineEnd)])
        }
        return shifts
    }

    // MARK: - Searches

    /// The last index of `starts`, ascending from 0, whose value is at most
    /// `value`.
    static func lastIndex(in starts: [Int], atOrBefore value: Int) -> Int {
        var (low, high) = (0, starts.count - 1)
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= value { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// The first index of `starts` from `lower` whose value is at least
    /// `value`, or `starts.count`.
    static func firstIndex(in starts: [Int], atOrAfter value: Int, from lower: Int) -> Int {
        var (low, high) = (lower, starts.count)
        while low < high {
            let middle = (low + high) / 2
            if starts[middle] < value { low = middle + 1 } else { high = middle }
        }
        return low
    }

    /// The bytes `old` and `new` share at their start, and at their end, each
    /// found apart (so the two may overlap, by up to the shorter's length):
    /// by `memcmp`, a block at a time, then byte by byte. 122 µs for 3.4 MB
    /// that differ in the middle (B-ATTRED-58), against 115 ms for the editor
    /// to lay the text out.
    static func commonEnds(_ old: String, _ new: String) -> (prefix: Int, suffix: Int) {
        var (old, new) = (old, new)
        old.makeContiguousUTF8()
        new.makeContiguousUTF8()
        let found = old.utf8.withContiguousStorageIfAvailable { oldBytes in
            new.utf8.withContiguousStorageIfAvailable { newBytes in unsafe commonEnds(oldBytes, newBytes) }
        }
        return found.flatMap { $0 } ?? (0, 0)
    }

    /// `commonEnds` of two texts' bytes where they lie: what
    /// ``TextEdit/sharedEnds(_:_:)`` finds an undo step's edit by.
    static func commonEnds(
        _ lhs: UnsafeBufferPointer<UInt8>, _ rhs: UnsafeBufferPointer<UInt8>
    ) -> (prefix: Int, suffix: Int) {
        let shorter = min(lhs.count, rhs.count)
        guard shorter > 0, let left = lhs.baseAddress, let right = rhs.baseAddress else { return (0, 0) }
        let block = 4096
        var prefix = 0
        while prefix + block <= shorter, unsafe memcmp(left + prefix, right + prefix, block) == 0 { prefix += block }
        while prefix < shorter, unsafe left[prefix] == right[prefix] { prefix += 1 }
        if prefix == shorter, lhs.count == rhs.count { return (prefix, prefix) }
        let (leftCount, rightCount) = (lhs.count, rhs.count)
        var suffix = 0
        // Offsets named one by one: inline, the pointer sums go past the
        // type checker's patience.
        while suffix + block <= shorter {
            let leftStart: Int = leftCount - suffix - block
            let rightStart: Int = rightCount - suffix - block
            guard unsafe memcmp(left + leftStart, right + rightStart, block) == 0 else { break }
            suffix += block
        }
        while suffix < shorter {
            let (leftAt, rightAt): (Int, Int) = (leftCount - 1 - suffix, rightCount - 1 - suffix)
            guard unsafe left[leftAt] == right[rightAt] else { break }
            suffix += 1
        }
        return (prefix, suffix)
    }
}
