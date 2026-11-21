//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHighlighter.swift
//
//  The seam a styler of any kind highlights a TextEditor through (the
//  highlighting design's §8.1 and §8.6, lane H6′): the styler itself, the
//  editor's text as it hands it over, a change by whole lines, and the
//  tokens a styler publishes. Behind `@_spi(TextEditorHighlighting)` until a
//  second real styler has been written against it (A-ATTRED-10 (b)).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// TUI-specific. Anything that styles a ``TextEditor``'s text: a tree-sitter
/// adapter, a language server's client, a hand-written lexer that keeps its
/// own line states.
///
/// The editor runs ``highlight(_:)`` in a task of its own, off the main
/// actor, for as long as it shows this highlighter, and cancels it when it
/// stops (the editor goes, or is given a highlighter that is not this one).
/// The highlighter takes the editor's text from its session as it changes
/// (``TextEditorHighlightSession/nextUpdate()``) and publishes tokens for
/// lines of it (``TextEditorHighlightSession/publish(_:forLine:of:)``). The
/// editor draws whatever was published last, and never waits for a
/// highlighter: a line it has not styled is drawn in the editor's own ink, or
/// in its tokens from before the edit, carried with it.
///
/// Two values of one type are one highlighter, and an editor given one keeps
/// the task it started, unless the type is `Equatable` and the two are
/// unequal: as `.task(id:)` restarts only for a new id (B-ATTRED-25).
///
/// Units (B-ATTRED-26): lines split at LF, CRLF and a lone CR, as the editor
/// splits them, numbered from 0; offsets in UTF-8 bytes, from the start of
/// the text or of a line. tree-sitter's rows and byte columns are these,
/// except that it does not take a lone CR for a line break.
///
/// The seam is SPI: a module uses it after
/// `@_spi(TextEditorHighlighting) import TUITextInput`, and gives a
/// highlighter to an editor with `textEditorHighlighter(_:maximumLineLength:style:)`.
/// It is outside the API stability policy, and may change in any release,
/// minor ones included, until a real highlighter outside TUI (tuitree's
/// tree-sitter adapter is to be the first) has been written against it and
/// settled, and it is made public in a minor release (A-ATTRED-10, 15).
@_spi(TextEditorHighlighting)
public protocol TextEditorHighlighter: Sendable {
    /// What the highlighter calls a token: each distinct value is styled once,
    /// by the modifier's `style`.
    associatedtype Token: Hashable, Sendable

    /// Highlights the editor's text for as long as the editor shows this
    /// highlighter, off the main actor. Returning, or the task's
    /// cancellation, ends it; ``TextEditorHighlightSession/nextUpdate()``
    /// returns `nil` once the editor has gone.
    func highlight(_ session: TextEditorHighlightSession<Token>) async
}

/// TUI-specific. The tokens of one line, each where it starts: a UTF-8 offset
/// from the line's start, without its break. A token lasts to the next one's
/// start, or to the line's end, so a gap between two tokens is a token too,
/// one the style draws nothing for.
///
/// Never trusted: an offset that goes backwards is taken as the one before
/// it, one past the line as its end, and one inside a character styles the
/// whole character.
@_spi(TextEditorHighlighting)
public struct TextEditorTokens<Token: Hashable & Sendable>: Sendable {
    /// Each token, and where it starts.
    var tokens: [Token] = []
    var offsets: [Int] = []

    /// No tokens: a line drawn in the editor's own ink.
    public init() {}

    /// Adds `token`, starting at `utf8Offset` of the line.
    public mutating func append(_ token: Token, at utf8Offset: Int) {
        tokens.append(token)
        offsets.append(utf8Offset)
    }

    /// Makes room for `count` tokens.
    public mutating func reserveCapacity(_ count: Int) {
        tokens.reserveCapacity(count)
        offsets.reserveCapacity(count)
    }

    /// How many tokens there are.
    public var count: Int { tokens.count }

    /// Whether there are none.
    public var isEmpty: Bool { tokens.isEmpty }
}

/// TUI-specific. The editor's text as a highlighter is given it: one version
/// of it, which never changes. A snapshot shares the editor's own `String`.
@_spi(TextEditorHighlighting)
public struct TextEditorText: Sendable {
    /// The version: one more for each change the editor made or was given.
    /// What a publish names, so tokens for an older text are refused.
    public let version: Int
    /// The text.
    public let string: String
    /// Where each line starts, in UTF-8 bytes: found from ``string`` by the
    /// highlighter's task when it takes the text, never shared with the
    /// editor's layout, whose own array each key splices in place
    /// (B-ATTRED-34).
    let lineStarts: [Int]

    /// `string` as version `version`, its lines found as ``EditorLayout``
    /// finds them, and its bytes made contiguous for ``withUTF8(_:)``.
    init(version: Int, string: String) {
        var string = string
        string.makeContiguousUTF8()
        self.version = version
        self.string = string
        lineStarts = EditorLayout.lineBreaks(in: string).starts
    }

    /// `string` as version `version`, which `change` made from `previous`,
    /// its lines found from `previous`'s (B-ATTRED-45): those before the
    /// change kept, those after it moved by the bytes it added or took, and
    /// only its own bytes walked, not the whole text's as
    /// ``init(version:string:)`` walks them. Where the change does not fit
    /// `previous`, or a CR at either of its ends might join a break across
    /// it, or the lines found are not `lineCount`, they are found whole.
    init(version: Int, string: String, changing previous: Self, by change: TextEditorTextChange, lineCount: Int) {
        var string = string
        string.makeContiguousUTF8()
        guard let starts = Self.lineStarts(of: string.utf8, changing: previous, by: change), starts.count == lineCount
        else {
            self = Self(version: version, string: string)
            return
        }
        self.version = version
        self.string = string
        lineStarts = starts
    }

    /// The line starts of `utf8`, the text `change` made from `previous`, or
    /// `nil` where the change cannot be trusted to have left them. A native
    /// string's view, whose indices move by offsets in constant time.
    static func lineStarts(
        of utf8: String.UTF8View, changing previous: Self, by change: TextEditorTextChange
    ) -> [Int]? {
        let old = previous.lineStarts
        let (oldLines, newLines, oldUTF8, newUTF8) = (change.oldLines, change.newLines, change.oldUTF8, change.newUTF8)
        let (oldTotal, newTotal) = (previous.utf8Count, utf8.count)
        // The change as `previous` has it: whole lines, at their starts.
        guard oldLines.lowerBound < old.count, oldLines.upperBound <= old.count,
            old[oldLines.lowerBound] == oldUTF8.lowerBound, newUTF8.lowerBound == oldUTF8.lowerBound,
            oldUTF8.upperBound == (oldLines.upperBound < old.count ? old[oldLines.upperBound] : oldTotal),
            newUTF8.upperBound <= newTotal, oldTotal - oldUTF8.upperBound == newTotal - newUTF8.upperBound
        else { return nil }
        let hasSuffix = oldLines.upperBound < old.count
        func index(_ offset: Int) -> String.UTF8View.Index { utf8.index(utf8.startIndex, offsetBy: offset) }
        // A lone CR before the change, or one ending it, could pair with an
        // LF the other side of it into one CRLF: walked whole.
        let cr = UInt8(ascii: "\r")
        if newUTF8.lowerBound > 0, utf8[index(newUTF8.lowerBound - 1)] == cr { return nil }
        if hasSuffix, !newUTF8.isEmpty, utf8[index(newUTF8.upperBound - 1)] == cr { return nil }
        var starts: [Int] = []
        starts.reserveCapacity(old.count - oldLines.count + newLines.count)
        starts += old[..<oldLines.lowerBound]
        if !newLines.isEmpty {
            var found = EditorLayout.lineBreaks(
                inBytes: utf8[index(newUTF8.lowerBound)..<index(newUTF8.upperBound)], startingAt: newUTF8.lowerBound
            ).starts
            // The last break's start is the first line after the change's.
            if hasSuffix, found.last == newUTF8.upperBound { found.removeLast() }
            guard found.count == newLines.count else { return nil }
            starts += found
        }
        let shift = newUTF8.upperBound - oldUTF8.upperBound
        starts += old[oldLines.upperBound...].lazy.map { $0 + shift }
        return starts
    }

    /// How many lines there are: never fewer than one.
    public var lineCount: Int { lineStarts.count }

    /// How many UTF-8 bytes the text is.
    public var utf8Count: Int { string.utf8.count }

    /// Where `line` starts, in UTF-8 bytes from the text's start: clamped to
    /// the lines there are.
    public func utf8Offset(ofLine line: Int) -> Int {
        lineStarts[min(max(0, line), lineStarts.count - 1)]
    }

    /// Where `line` ends, before its break, in UTF-8 bytes from the text's
    /// start.
    func utf8End(ofLine line: Int) -> Int {
        let line = min(max(0, line), lineStarts.count - 1)
        guard line + 1 < lineStarts.count else { return string.utf8.count }
        let (start, next) = (lineStarts[line], lineStarts[line + 1])
        // Back over its break: an LF, a lone CR, or a CRLF.
        let utf8 = string.utf8
        func byte(_ offset: Int) -> UInt8 { utf8[utf8.index(utf8.startIndex, offsetBy: offset)] }
        if byte(next - 1) == 0x0A, next - 2 >= start, byte(next - 2) == 0x0D { return next - 2 }
        return next - 1
    }

    /// `line`'s UTF-8, without its break: a view of ``string``'s own bytes.
    public func line(_ line: Int) -> Substring.UTF8View {
        let utf8 = string.utf8
        let start = utf8.index(utf8.startIndex, offsetBy: utf8Offset(ofLine: line))
        let end = utf8.index(utf8.startIndex, offsetBy: utf8End(ofLine: line))
        return string[start..<end].utf8
    }

    /// The line that holds the byte at `utf8Offset`, by a binary search of
    /// the line starts: a line's break is its own; an offset past the text's
    /// end is the last line's (B-ATTRED-29, for a changed range or a capture
    /// a tree styler maps to lines).
    public func line(containingUTF8Offset utf8Offset: Int) -> Int {
        var (low, high) = (0, lineStarts.count - 1)
        while low < high {
            let middle = (low + high + 1) / 2
            if lineStarts[middle] <= utf8Offset { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// Calls `body` with the whole text's UTF-8, borrowed, not copied: for a
    /// parse through a C library (B-ATTRED-29). The buffer is valid only
    /// while `body` runs.
    public func withUTF8<Result>(_ body: (UnsafeBufferPointer<UInt8>) throws -> Result) rethrows -> Result {
        // Contiguous since ``init(version:string:)``; copied only if not.
        if let result = try string.utf8.withContiguousStorageIfAvailable(body) { return result }
        return try Array(string.utf8).withUnsafeBufferPointer(body)
    }
}

/// TUI-specific. What changed from the text a highlighter last took to the
/// one it takes now, by whole lines, as the editor splices them: the lines
/// replaced, the lines in their place, and their bytes (B-ATTRED-21). Every
/// edit made since the last update is folded into one.
///
/// Both ranges start at the start of a line, so a tree-sitter `InputEdit` is
/// `startByte` = `oldUTF8.lowerBound`, `oldEndByte` = `oldUTF8.upperBound`,
/// `newEndByte` = `newUTF8.upperBound`, with points at column 0 of
/// `oldLines.lowerBound`, `oldLines.upperBound` and `newLines.upperBound`.
@_spi(TextEditorHighlighting)
public struct TextEditorTextChange: Sendable, Equatable {
    /// The lines of the old text that were replaced, and those of the new
    /// text in their place.
    public var oldLines: Range<Int>
    public var newLines: Range<Int>
    /// Their bytes, from the text's start: breaks included.
    public var oldUTF8: Range<Int>
    public var newUTF8: Range<Int>

    public init(oldLines: Range<Int>, newLines: Range<Int>, oldUTF8: Range<Int>, newUTF8: Range<Int>) {
        self.oldLines = oldLines
        self.newLines = newLines
        self.oldUTF8 = oldUTF8
        self.newUTF8 = newUTF8
    }
}

/// TUI-specific. What a highlighter is told: the latest text, what changed
/// since the text it took last, the lines on screen, the lines the editor
/// keeps tokens for, and those of them it holds no tokens of this text for.
@_spi(TextEditorHighlighting)
public struct TextEditorHighlightUpdate: Sendable {
    /// The latest text: only the latest is kept, so a slow highlighter holds
    /// one old text, never a queue of them.
    public var text: TextEditorText
    /// Every edit since the text the highlighter took last, as one; `nil`
    /// when the text is all new: the first update, or a text written whole
    /// (by the app, an undo or a redo) that shares no byte at either end with
    /// the last; a text written whole that does comes as the change from it,
    /// by whole lines (B-ATTRED-58). An update whose text has the version the
    /// highlighter last had is a scroll: only ``visibleLines`` moved
    /// (B-ATTRED-27).
    public var change: TextEditorTextChange?
    /// The lines on screen: what to style first.
    public var visibleLines: Range<Int>
    /// The lines the editor keeps tokens for: those on screen and a screen
    /// either side (B-ATTRED-20, 30). Tokens published for any other line
    /// are kept nowhere (B-ATTRED-57).
    public var window: Range<Int>
    /// The lines of ``window`` the editor holds no tokens of this text for:
    /// lines never published, lines that left the window and came back (a
    /// line that leaves it loses its tokens, B-ATTRED-38), lines an edit put
    /// in, and lines edited in place, which the editor draws in their old
    /// tokens, moved, until they are published again (B-ATTRED-28).
    ///
    /// A highlighter that publishes these, and the lines of the window its
    /// own analysis says changed (tree-sitter's changed ranges), leaves no
    /// line drawn in another text's tokens: a line not listed holds the
    /// tokens last published for it, moved with its text where an edit moved
    /// it. A stateless line styler publishes these alone (B-ATTRED-57).
    public var linesToStyle: RangeSet<Int>
}

/// TUI-specific. What became of tokens published to a
/// ``TextEditorHighlightSession`` (B-ATTRED-57).
@_spi(TextEditorHighlighting)
public enum TextEditorPublishOutcome: Sendable, Equatable {
    /// Taken, and kept for these lines: those published that are in the
    /// editor's window. A publish's other lines are kept nowhere, so a range
    /// short of the lines published, or empty, says the window moved; the
    /// next update lists the lines in
    /// ``TextEditorHighlightUpdate/linesToStyle`` once they are in it.
    case kept(Range<Int>)
    /// Refused, and kept nowhere: the text is no longer the editor's (take
    /// the next update), a line is past its end, or a batch's tokens are not
    /// one a line (B-ATTRED-37).
    case refused

    /// Whether it was refused.
    public var isRefused: Bool { self == .refused }
}
