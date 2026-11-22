//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHighlightSession+Editor.swift
//
//  The editor's half of a highlight session (the highlighting design's
//  B-ATTRED-20, 21, 24, 27, 28, lane H6′): its edits, folded into one change
//  by whole lines and carried into the tokens kept; the lines on screen; and
//  what a frame reads. All of it on the main actor, each a lock held for
//  microseconds.
//
//  Created by Wade Tregaskis
//  License: MIT

import Synchronization
import TUIFoundation

/// A highlight session as the editor sees it, whatever its tokens' type.
protocol EditorHighlightFeed: AnyObject, Sendable {
    /// The text is now `string`, of `lineCount` lines: by `edit`, made from
    /// the text before, or whole. Returns the lines whose tokens went
    /// because they left the window.
    func textChanged(to string: String, lineCount: Int, by edit: EditorHighlightEdit?) -> [Int]
    /// The text is now `string`, whose lines start at `lineStarts`, written
    /// whole (the app's write, an undo, a redo): told as an edit of the text
    /// before, found from the bytes the two share (B-ATTRED-58). Returns the
    /// lines whose tokens went because they left the window.
    func textWritten(to string: String, lineStarts: [Int]) -> [Int]
    /// The lines on screen are `lines`. Returns the lines whose tokens went
    /// because they left the window.
    func show(lines: Range<Int>) -> [Int]
    /// The lines whose tokens changed since this was last asked.
    func takeChangedLines() -> Set<Int>
    /// `line`'s runs, in style indices from 1 (``tokenCount``).
    func runs(ofLine line: Int) -> [EditorHighlightRun]
    /// How many tokens have been interned.
    var tokenCount: Int { get }
    /// The lines tokens are kept for: those on screen and a screen either side.
    var window: Range<Int> { get }
    /// Whether the session holds marks, which an edit must carry
    /// (B-ATTRED-59).
    var hasMarks: Bool { get }
    /// The marks as they are now, and whether a publish changed them, if
    /// they changed since this was last asked.
    func takeMarks() -> (marks: [EditorMark], published: Bool)?
    /// The editor has gone: the highlighter's next update is `nil`.
    func close()
}

/// An edit as a highlight session is told it: as the highlighter is told
/// it, by whole lines at both ends (``change``), and as the editor spliced
/// its own lines, with how the tokens of each line edited in place move.
struct EditorHighlightEdit: Sendable {
    var change: TextEditorTextChange
    /// The editor's lines the edit replaced, and how many took their place
    /// (``EditorLayout/Edit``'s).
    var replaced: Range<Int>
    var replacementCount: Int
    /// For each line in the window edited in place (as many lines after the
    /// edit as before), how its tokens' offsets move (B-ATTRED-28).
    var carried: [Int: EditorLineShift] = [:]
    /// The edit by its bytes, which the highlighter's marks are carried
    /// through (B-ATTRED-59): `nil` where the session held none to carry.
    var marks: EditorMarkEdit?
}

/// How the offsets of a line edited in place move: those from where its
/// unchanged end starts move by the bytes inserted or removed, those up to
/// where it first differs stay, and those in between go to where it first
/// differs. So text typed where a token starts belongs to the token before
/// it: a word typed on is still the word.
struct EditorLineShift: Sendable, Equatable {
    var prefix: Int
    var oldSuffixStart: Int
    var delta: Int
    /// The line's new length in bytes: past the session's limit, it is drawn
    /// unstyled.
    var newLength: Int

    /// The shift that takes `old` to `new`, both a line's bytes.
    init(from old: some Collection<UInt8>, to new: some Collection<UInt8>) {
        let (old, new) = (Array(old), Array(new))
        var prefix = 0
        while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] {
            suffix += 1
        }
        self.prefix = prefix
        oldSuffixStart = old.count - suffix
        delta = new.count - old.count
        newLength = new.count
    }

    /// `runs` moved: each offset as the module comment says.
    func shifted(_ runs: [EditorHighlightRun]) -> [EditorHighlightRun] {
        runs.map { run in
            let offset = Int(run.utf8Offset)
            let moved = offset >= oldSuffixStart ? offset + delta : offset <= prefix ? offset : prefix
            return EditorHighlightRun(utf8Offset: moved, style: run.style)
        }
    }
}

/// A line's tokens as kept: provisional while they are the tokens of the
/// line before an edit, moved with it, until the highlighter publishes the
/// line again (B-ATTRED-24, 28).
struct EditorHighlightLine: Sendable, Equatable {
    var runs: [EditorHighlightRun]
    var isProvisional = false
}

/// What changed since the text the highlighter took last: everything, or
/// how many lines and bytes at either end did not (B-ATTRED-21).
enum EditorHighlightPending: Sendable, Equatable {
    case whole
    case ends(prefixLines: Int, suffixLines: Int, prefixBytes: Int, suffixBytes: Int)

    /// `pending` with `change`, made to a text of `lineCount` lines and
    /// `utf8Count` bytes, folded in: the lines and bytes neither touched.
    static func folding(
        _ change: TextEditorTextChange, into pending: Self?, lineCount: Int, utf8Count: Int
    ) -> Self {
        let lines = (change.oldLines.lowerBound, lineCount - change.oldLines.upperBound)
        let bytes = (change.oldUTF8.lowerBound, utf8Count - change.oldUTF8.upperBound)
        switch pending {
        case .whole: return .whole
        case nil: return .ends(prefixLines: lines.0, suffixLines: lines.1, prefixBytes: bytes.0, suffixBytes: bytes.1)
        case .ends(let prefixLines, let suffixLines, let prefixBytes, let suffixBytes):
            return .ends(
                prefixLines: min(prefixLines, lines.0), suffixLines: min(suffixLines, lines.1),
                prefixBytes: min(prefixBytes, bytes.0), suffixBytes: min(suffixBytes, bytes.1))
        }
    }
}

/// What a highlight session's editor and highlighter share, under its lock.
struct EditorHighlightState: Sendable {
    /// The editor's latest text, its version and its size.
    var version = 0
    var string: String
    var lineCount: Int
    var utf8Count: Int
    /// The lines on screen, and those tokens are kept for.
    var visible: Range<Int> = 0..<0
    var window: Range<Int> = 0..<1
    /// The tokens kept, by line.
    var lines: [Int: EditorHighlightLine] = [:]
    /// The lines whose tokens changed since the editor last took them, for
    /// it to forget what it drew them in.
    var changed: Set<Int> = []
    /// Whether a frame has been asked for since the editor last took them.
    var frameAsked = false
    /// Whether the editor has gone.
    var isClosed = false
    /// The text the highlighter took last, its lines found, and its size.
    var taken: TextEditorText?
    var takenSize = (lines: 0, bytes: 0)
    /// What changed since: everything until the first update.
    var pending: EditorHighlightPending? = .whole
    /// Whether the lines on screen moved since.
    var viewportMoved = false
    /// The highlighter, waiting for the next update.
    var waiter: CheckedContinuation<Void, Never>?
    /// The highlighter's marks, in UTF-8 offsets of the editor's text, and how
    /// they changed since the editor last took them (B-ATTRED-59).
    var marks: [EditorMark] = []
    var marksChange: EditorHighlightMarksChange?

    init(string: String, lineCount: Int, utf8Count: Int) {
        self.string = string
        self.lineCount = max(1, lineCount)
        self.utf8Count = utf8Count
    }

    /// Whether there is an update the highlighter has not taken.
    var hasUpdate: Bool { pending != nil || viewportMoved }

    /// The waiting highlighter, no longer waiting.
    mutating func takeWaiter() -> CheckedContinuation<Void, Never>? {
        defer { waiter = nil }
        return waiter
    }

    /// The lines tokens are kept for, about `visible`: a screen either side.
    static func window(around visible: Range<Int>, lineCount: Int) -> Range<Int> {
        let screen = max(1, visible.count)
        return max(0, visible.lowerBound - screen)..<min(lineCount, visible.upperBound + screen)
    }

    /// Moves the window about the lines on screen, clamped to the text, and
    /// drops the tokens of the lines that left it.
    mutating func placeWindow() -> [Int] {
        visible = min(visible.lowerBound, lineCount)..<min(visible.upperBound, lineCount)
        window = Self.window(around: visible, lineCount: lineCount)
        let gone = lines.keys.filter { !window.contains($0) }
        for line in gone { lines[line] = nil }
        return gone
    }
}

// MARK: - Taking an update

/// What looking for an update found.
enum EditorHighlightTake: Sendable {
    case closed
    case wait
    case update(Taken)

    /// An update taken: its text, made outside the lock unless it is the one
    /// the highlighter has (a scroll).
    struct Taken: Sendable {
        var version: Int
        var string: String
        var text: TextEditorText?
        var change: TextEditorTextChange?
        var visible: Range<Int>
        /// The lines tokens are kept for, and those of them that hold none of
        /// this text, or only provisional ones (B-ATTRED-57).
        var window: Range<Int>
        var linesToStyle: RangeSet<Int>
        /// The text the highlighter took last, which ``change`` is from, and
        /// the lines of the one taken now: its lines are found from that
        /// one's (B-ATTRED-45).
        var previous: TextEditorText?
        var lineCount: Int

        /// The text taken: the highlighter's own, where only the lines on
        /// screen moved; else its lines found from the last text's where
        /// there is a change from it, and from the whole text where not.
        func madeText() -> TextEditorText {
            if let text { return text }
            guard let previous, let change else { return TextEditorText(version: version, string: string) }
            return TextEditorText(version: version, string: string, changing: previous, by: change, lineCount: lineCount)
        }
    }
}

/// What keeping a publish's runs did: refused, or kept for some lines, with
/// whether to ask the editor for a frame.
enum EditorHighlightKeep: Sendable, Equatable {
    case refused
    case kept(Range<Int>, askForFrame: Bool)
}

extension EditorHighlightState {
    /// The next update, if there is one, taken: what changed since the text
    /// taken last, by whole lines, is from now on measured from this one.
    mutating func takeUpdate() -> EditorHighlightTake {
        if isClosed { return .closed }
        guard hasUpdate else { return .wait }
        var change: TextEditorTextChange?
        if case .ends(let prefixLines, let suffixLines, let prefixBytes, let suffixBytes) = pending {
            change = TextEditorTextChange(
                oldLines: prefixLines..<(takenSize.lines - suffixLines), newLines: prefixLines..<(lineCount - suffixLines),
                oldUTF8: prefixBytes..<(takenSize.bytes - suffixBytes), newUTF8: prefixBytes..<(utf8Count - suffixBytes))
        }
        let taken = EditorHighlightTake.Taken(
            version: version, string: string, text: taken?.version == version ? taken : nil, change: change,
            visible: visible, window: window, linesToStyle: linesToStyle(), previous: taken, lineCount: lineCount)
        (pending, viewportMoved, takenSize) = (nil, false, (lineCount, utf8Count))
        return .update(taken)
    }

    /// The lines of the window that hold no tokens, or only provisional ones
    /// (B-ATTRED-57): a look-up a line of the window, a few hundred at most.
    func linesToStyle() -> RangeSet<Int> {
        var found = RangeSet<Int>()
        var start: Int?
        for line in window {
            let held = lines[line].map { !$0.isProvisional } ?? false
            if !held, start == nil { start = line }
            if held, let first = start {
                found.insert(contentsOf: first..<line)
                start = nil
            }
        }
        if let first = start { found.insert(contentsOf: first..<window.upperBound) }
        return found
    }

    /// The highlighter has `text`, its lines found.
    mutating func noteTaken(_ text: TextEditorText) {
        if text.version >= taken?.version ?? -1 { taken = text }
    }

    /// The text a publish for `version` is checked against, and the window,
    /// or `nil` where the text is no longer the editor's.
    func publishable(version: Int) -> (text: TextEditorText, window: Range<Int>)? {
        guard !isClosed, version == self.version, let taken, taken.version == version else { return nil }
        return (taken, window)
    }

    /// Keeps `made`, each line's runs (none: drawn unstyled), made for the
    /// lines `madeLines` of those `published`, if `version` is still the
    /// editor's: a line whose runs changed is one to draw again, and one on
    /// screen asks for a frame, once until the editor next draws. Only the
    /// lines still in the window are kept, which a scroll since `made` was
    /// made may have moved.
    mutating func keep(
        _ made: [(line: Int, runs: [EditorHighlightRun])], madeFor madeLines: Range<Int>, of published: Range<Int>,
        ofVersion version: Int
    ) -> EditorHighlightKeep {
        guard !isClosed, version == self.version else { return .refused }
        var onScreen = false
        for (line, runs) in made where window.contains(line) {
            let kept = lines[line]
            guard kept?.runs != runs || kept?.isProvisional == true else { continue }
            lines[line] = EditorHighlightLine(runs: runs)
            guard kept?.runs != runs else { continue }
            changed.insert(line)
            onScreen = onScreen || visible.contains(line)
        }
        // None held: an empty range at the publish's start, wherever the
        // window is.
        var held = madeLines.clamped(to: window)
        if held.isEmpty { held = published.lowerBound..<published.lowerBound }
        guard onScreen, !frameAsked else { return .kept(held, askForFrame: false) }
        frameAsked = true
        return .kept(held, askForFrame: true)
    }
}

// MARK: - The editor's half

extension TextEditorHighlightSession: EditorHighlightFeed {
    func textChanged(to string: String, lineCount: Int, by edit: EditorHighlightEdit?) -> [Int] {
        let limit = maximumLineLength
        let (gone, waiter) = state.withLock { state -> ([Int], CheckedContinuation<Void, Never>?) in
            guard !state.isClosed else { return ([], nil) }
            state.version += 1
            if let edit {
                state.pending = .folding(
                    edit.change, into: state.pending, lineCount: state.lineCount, utf8Count: state.utf8Count)
                var moved = EditorLineStyleCache.moving(
                    state.lines, replacing: edit.replaced, withCount: edit.replacementCount)
                for (line, shift) in edit.carried where shift.newLength <= limit {
                    guard let kept = state.lines[line] else { continue }
                    moved[line] = EditorHighlightLine(runs: shift.shifted(kept.runs), isProvisional: true)
                }
                state.lines = moved
                let shift = edit.replacementCount - edit.replaced.count
                state.changed = Set(
                    state.changed.compactMap { line in
                        edit.replaced.contains(line) ? nil : line >= edit.replaced.upperBound ? line + shift : line
                    })
            } else {
                state.pending = .whole
                state.lines.removeAll()
                state.changed.removeAll()
            }
            state.carryMarks(through: edit?.marks)
            (state.string, state.lineCount, state.utf8Count) = (string, max(1, lineCount), string.utf8.count)
            return (state.placeWindow(), state.takeWaiter())
        }
        waiter?.resume()
        return gone
    }

    func show(lines: Range<Int>) -> [Int] {
        let (gone, waiter) = state.withLock { state -> ([Int], CheckedContinuation<Void, Never>?) in
            let shown = max(0, lines.lowerBound)..<max(0, lines.upperBound)
            guard !state.isClosed, shown != state.visible else { return ([], nil) }
            state.visible = shown
            state.viewportMoved = true
            return (state.placeWindow(), state.takeWaiter())
        }
        waiter?.resume()
        return gone
    }

    func takeChangedLines() -> Set<Int> {
        state.withLock { state in
            state.frameAsked = false
            defer { state.changed.removeAll() }
            return state.changed
        }
    }

    func runs(ofLine line: Int) -> [EditorHighlightRun] {
        state.withLock { $0.lines[line]?.runs ?? [] }
    }

    var window: Range<Int> { state.withLock { $0.window } }

    func close() {
        state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.isClosed = true
            state.lines.removeAll()
            state.marks.removeAll()
            return state.takeWaiter()
        }?.resume()
    }

    /// `line`'s tokens as kept, for a test.
    func keptLine(_ line: Int) -> EditorHighlightLine? { state.withLock { $0.lines[line] } }
}
