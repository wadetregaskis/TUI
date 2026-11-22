//  🖥️ TUI — A Terminal UI framework for Swift
//  EditorMarks.swift
//
//  Marks: ranges of a TextEditor's text stated with the text they were
//  computed from, carried through the editor's own edits, and drawn over
//  highlighting and under the selection (the highlighting design's B-ATTRED-8
//  and 13, lane H3 of its §8.6). An app's marks, such as a parse error, are
//  kept here, and drawn with the find bar's matches (`FindMatchSet`), which
//  the bar keeps and carries itself.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

/// A mark as the editor keeps it: UTF-8 offsets into the editor's text, and
/// the attributes an app gave it, interned in the store's
/// ``EditorMarkStore/styles`` and drawn over highlighting (B-ATTRED-8).
struct EditorMark: Equatable, Sendable {
    var utf8: Range<Int>
    var style: UInt16
}

/// An app's marks stated with the text they were computed from
/// (B-ATTRED-13). Equal when their ranges and attributes are and their texts
/// are one (``EditorMarkStore/isSameText(_:_:)``), which is how the editor
/// tells marks stated again from new ones each frame.
struct EditorMarkStatement: Equatable {
    let text: String
    let ranges: [Range<String.Index>]
    /// Each range's attributes, in order.
    let attributes: [AttributeContainer]

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.ranges == rhs.ranges && lhs.attributes == rhs.attributes && EditorMarkStore.isSameText(lhs.text, rhs.text)
    }
}

/// An edit as marks are carried through it: the bytes `start..<oldEnd` of
/// the text before it gave way to `start..<newEnd` (B-ATTRED-47).
///
/// A mark's ends do not take in text put in where they stand, as
/// CodeMirror's marks do not by default: text typed at a mark's start goes
/// before it and at its end after it. So a range around an edit grows or
/// shrinks with it, an end in text the edit took goes to the edge of what it
/// put in that leaves the mark outside it, and a range the edit took whole is
/// left empty, and dropped.
struct EditorMarkEdit: Equatable, Sendable {
    let start: Int
    let oldEnd: Int
    let newEnd: Int

    /// Where a mark's start at `offset` goes.
    func lower(_ offset: Int) -> Int {
        offset < start ? offset : offset >= oldEnd ? offset + newEnd - oldEnd : newEnd
    }

    /// Where a mark's end at `offset` goes.
    func upper(_ offset: Int) -> Int {
        offset <= start ? offset : offset > oldEnd ? offset + newEnd - oldEnd : start
    }

    /// `marks` moved through the edit, those it left empty dropped.
    func carry(_ marks: [EditorMark]) -> [EditorMark] {
        marks.compactMap { mark in
            let (lower, upper) = (lower(mark.utf8.lowerBound), upper(mark.utf8.upperBound))
            return lower < upper ? EditorMark(utf8: lower..<upper, style: mark.style) : nil
        }
    }

    /// The edit `edit` makes to `before`'s text, by its bytes: from where the
    /// lines it replaced and those in their place first differ to where they
    /// last do, found as B-ATTRED-41 finds a line's (``EditorLineShift``) but
    /// over all of them. So a mark on a line edited keeps its place in it,
    /// rather than the whole line being taken as replaced.
    init(_ edit: EditorLayout.Edit, from before: EditorLayout) {
        let (old, new) = (before.text.utf8, edit.text.utf8)
        let (oldTotal, newTotal) = (old.count, new.count)
        let lineCount = before.lines.count
        // The bytes before the line above the edit, and those after the lines
        // it replaced, are as they were: lines taken at the end take the break
        // before them, which is the line above's.
        let first = min(edit.replaced.lowerBound, lineCount)
        let head = min(first > 0 ? before.lineStarts[first - 1] : 0, oldTotal, newTotal)
        let tail = min(
            edit.replaced.upperBound < lineCount ? oldTotal - before.lineStarts[edit.replaced.upperBound] : 0,
            oldTotal - head, newTotal - head)
        // Bounds named one by one: written inline, the two slices put the expression past the type-check guard's
        // limit (`-solver-scope-threshold=2000`).
        let oldFrom: String.UTF8View.Index = old.index(old.startIndex, offsetBy: head)
        let oldTo: String.UTF8View.Index = old.index(old.startIndex, offsetBy: oldTotal - tail)
        let newFrom: String.UTF8View.Index = new.index(new.startIndex, offsetBy: head)
        let newTo: String.UTF8View.Index = new.index(new.startIndex, offsetBy: newTotal - tail)
        let shift = EditorLineShift(from: old[oldFrom..<oldTo], to: new[newFrom..<newTo])
        start = head + shift.prefix
        oldEnd = head + shift.oldSuffixStart
        newEnd = oldEnd + shift.delta
    }

    init(start: Int, oldEnd: Int, newEnd: Int) {
        (self.start, self.oldEnd, self.newEnd) = (start, oldEnd, newEnd)
    }
}

/// A drawn line's marks, in its columns: the find bar's matches, which the
/// row tints, and the app's marks as the styles drawn over the line's own.
struct EditorLineMarks {
    var find: [Range<Int>] = []
    var runs: [EditorStyledRun] = []
}

/// A ``TextEditor``'s marks (B-ATTRED-13): the app's as last stated and as
/// carried to the editor's text, their attributes interned, the texts the
/// editor wrote over its last few edits, the find bar's matches as the bar
/// last gave them, and each drawn line's marks.
struct EditorMarkStore {
    /// The app's marks: as last stated, and as carried to the editor's text,
    /// in the order stated.
    struct Source {
        var stated: EditorMarkStatement?
        var marks: [EditorMark] = []
    }

    /// How many of its edits back the editor finds an app's marks' text
    /// (B-ATTRED-48).
    static let carriedEdits = 4

    private(set) var app = Source()

    /// The find bar's matches, and the layout whose text they are of: drawn
    /// only on that layout. The bar finds them and carries them through the
    /// editor's edits itself (`FindMatchCache`), so the store holds them as
    /// given, and finds each drawn line's among them by its bytes.
    private(set) var find: FindMatchSet?
    private weak var findLayout: EditorLayout?

    /// The attributes of the app's marks, interned and resolved as
    /// highlighting's are (B-ATTRED-10, 33).
    private(set) var styles = EditorHighlightStyles()

    /// The layout whose text the marks are in. Any other (a text the app
    /// wrote, or one the editor wrote whole) hides every mark until it is
    /// stated again (B-ATTRED-46).
    private weak var layout: EditorLayout?

    /// The texts the editor wrote from, oldest first, each with the edit it
    /// made to it, the last edit leaving ``historyHead``'s text: kept while
    /// the app states marks, for marks stated against a text a few keys old.
    private var history: [(text: String, edit: EditorMarkEdit)] = []
    private weak var historyHead: EditorLayout?

    /// The marks each line holds, in UTF-8 offsets from the line's start,
    /// made when a line is first drawn after the marks change; and each
    /// drawn line's in its columns.
    private var byLine: [Int: [EditorMark]]?
    private var drawn: [Int: EditorLineMarks] = [:]

    /// Whether any mark is drawn.
    var hasMarks: Bool { !app.marks.isEmpty || hasFindMatches }

    /// Whether the find bar has matches drawn.
    var hasFindMatches: Bool { !(find?.isEmpty ?? true) }

    /// Whether two texts are one: the same storage at once, else compared,
    /// lengths first, so two texts of different lengths cost nothing.
    static func isSameText(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.count == rhs.utf8.count && lhs == rhs
    }

    /// Takes a frame's statements, in `layout`'s text: the app's marks kept
    /// where it states what it stated last, and found again otherwise; the
    /// find bar's matches as given (``note(find:in:)``). `styling` is what
    /// the app's attributes are drawn under.
    mutating func note(
        app appStatement: EditorMarkStatement?, find findMatches: FindMatchSet?, in layout: EditorLayout,
        styling: () -> EditorAttributedStyling
    ) {
        note(find: findMatches, in: layout)
        // No marks, and none stated: nothing to do, and no history kept.
        guard appStatement != nil || app.stated != nil else { return }
        if self.layout !== layout {
            // A text the editor did not carry its marks to.
            (app, self.layout) = (Source(), layout)
            forgetDrawn()
        }
        if historyHead !== layout { (history, historyHead) = ([], nil) }
        if appStatement != nil, styles.adopt(styling()) { forgetDrawn() }
        if let resolved = resolved(appStatement, replacing: app, in: layout) {
            app = resolved
            forgetDrawn()
        }
    }

    /// Takes the find bar's matches, of `layout`'s text, or `nil` for none:
    /// at each frame, and after each of the editor's edits, which the bar's
    /// matches are carried through. Matches of another text draw nothing.
    mutating func note(find matches: FindMatchSet?, in layout: EditorLayout) {
        let matches = matches.flatMap { Self.isSameText($0.text, layout.text) ? $0 : nil }
        guard matches?.identity !== find?.identity || (matches != nil && findLayout !== layout) else { return }
        (find, findLayout) = (matches, matches == nil ? nil : layout)
        forgetDrawn()
    }

    /// `statement`'s marks in `layout`'s text, or `nil` where `source` has
    /// them already. Where its text is one the editor wrote over its last
    /// few edits, they are carried through the edits since; where it is
    /// none the editor knows, there are none to draw until stated again.
    private mutating func resolved(
        _ statement: EditorMarkStatement?, replacing source: Source, in layout: EditorLayout
    ) -> Source? {
        guard source.stated != statement else { return nil }
        guard let statement else { return Source() }
        let edits: [EditorMarkEdit]
        if Self.isSameText(statement.text, layout.text) {
            edits = []
        } else if let index = history.lastIndex(where: { Self.isSameText($0.text, statement.text) }) {
            edits = history[index...].map(\.edit)
            // What came before it, the app will not state marks against again.
            history.removeFirst(index)
        } else {
            return Source(stated: statement)
        }
        let text = statement.text
        let utf8 = text.utf8
        var marks: [EditorMark] = []
        marks.reserveCapacity(statement.ranges.count)
        for (index, range) in statement.ranges.enumerated() {
            // Never trusted: clamped to the text, a mark of another text too.
            let lower = min(range.lowerBound, text.endIndex)
            let upper = min(max(range.upperBound, lower), text.endIndex)
            guard lower < upper else { continue }
            let style = styles.index(of: statement.attributes[index]) { container in container }
            marks.append(
                EditorMark(
                    utf8: utf8.distance(from: utf8.startIndex, to: lower)..<utf8.distance(from: utf8.startIndex, to: upper),
                    style: style))
        }
        for edit in edits { marks = edit.carry(marks) }
        return Source(stated: statement, marks: marks)
    }

    /// Whether an edit made from `before` is one the marks are carried
    /// through, or the history kept.
    func carries(from before: EditorLayout) -> Bool {
        (layout === before && !app.marks.isEmpty) || app.stated != nil
    }

    /// Carries the marks through `edit`, made to `text`, `before`'s, which
    /// left `after`; and keeps `text` while the app states marks.
    mutating func carry(through edit: EditorMarkEdit, of text: String, from before: EditorLayout, to after: EditorLayout) {
        if layout === before {
            app.marks = edit.carry(app.marks)
            layout = after
            forgetDrawn()
        }
        guard app.stated != nil else { return }
        if historyHead !== before { history = [] }
        history.append((text, edit))
        if history.count > Self.carriedEdits { history.removeFirst(history.count - Self.carriedEdits) }
        historyHead = after
    }

    private mutating func forgetDrawn() {
        byLine = nil
        drawn = [:]
    }

    /// `line`'s marks in its columns, from `layout`: the app's where it is
    /// theirs, the find bar's where it is of their text.
    mutating func marks(ofLine line: Int, in layout: EditorLayout) -> EditorLineMarks {
        guard hasMarks, line < layout.lines.count else { return EditorLineMarks() }
        let drawsApp = layout === self.layout && !app.marks.isEmpty
        let drawsFind = layout === findLayout && hasFindMatches
        guard drawsApp || drawsFind else { return EditorLineMarks() }
        if let kept = drawn[line] { return kept }
        var made = EditorLineMarks()
        if drawsFind, let find {
            // The line's own bytes, its break included, found among the
            // matches by a search rather than a table of every line's.
            let starts = layout.lineStarts
            let start = starts[line]
            let end = line + 1 < starts.count ? starts[line + 1] : layout.text.utf8.count
            let ranges = find.matches(touching: start..<end).map {
                (max($0.lowerBound, start) - start)..<(min($0.upperBound, end) - start)
            }
            made.find = Self.columns(of: ranges, in: layout.lines[line]).filter { !$0.isEmpty }
        }
        if drawsApp {
            if byLine == nil { byLine = Self.byLine(app.marks, in: layout) }
            made.runs = Self.runs(of: byLine?[line] ?? [], inLine: layout.lines[line], styles: styles)
        }
        drawn[line] = made
        return made
    }

    /// The runs `marks`, a line's in UTF-8 offsets from its start, are drawn
    /// in, in `styles`, in the line's columns: a mark stated later drawn over
    /// one before it. The app's marks' and a highlighter's (B-ATTRED-59).
    static func runs(of marks: [EditorMark], inLine line: [Character], styles: EditorHighlightStyles) -> [EditorStyledRun] {
        var runs: [EditorStyledRun] = []
        for (mark, columns) in zip(marks, columns(of: marks.map(\.utf8), in: line)) where !columns.isEmpty {
            guard var run = styles.style(mark.style) else { continue }
            run.columns = columns
            runs = EditorStyledRun.overlaying([run], on: runs)
        }
        return runs
    }

    /// `marks` by the lines they cover, each in UTF-8 offsets from its
    /// line's start: a mark across a line break covers the end of one line
    /// and the start of the next.
    static func byLine(_ marks: [EditorMark], in layout: EditorLayout) -> [Int: [EditorMark]] {
        var table: [Int: [EditorMark]] = [:]
        let starts = layout.lineStarts
        for mark in marks {
            var line = layout.line(containingUTF8Offset: mark.utf8.lowerBound)
            while line < starts.count {
                let next = line + 1 < starts.count ? starts[line + 1] : Int.max
                let (lower, upper) = (max(mark.utf8.lowerBound, starts[line]), min(mark.utf8.upperBound, next))
                if lower < upper {
                    table[line, default: []].append(
                        EditorMark(utf8: (lower - starts[line])..<(upper - starts[line]), style: mark.style))
                }
                guard mark.utf8.upperBound > next else { break }
                line += 1
            }
        }
        return table
    }

    /// `ranges`, UTF-8 offsets into `line`, as its columns, in one walk of
    /// the line as far as the last: a start inside a character takes in the
    /// character, and so does an end; past the line, its end.
    static func columns(of ranges: [Range<Int>], in line: [Character]) -> [Range<Int>] {
        guard !ranges.isEmpty else { return [] }
        // Each end, starts before ends at one offset.
        var bounds: [(offset: Int, slot: Int)] = []
        bounds.reserveCapacity(ranges.count * 2)
        for (index, range) in ranges.enumerated() {
            bounds.append((range.lowerBound, index * 2))
            bounds.append((range.upperBound, index * 2 + 1))
        }
        bounds.sort { ($0.offset, $0.slot & 1) < ($1.offset, $1.slot & 1) }
        var columns = [Int](repeating: 0, count: ranges.count * 2)
        // The character the walk is on, the byte it starts at, and the byte
        // the character before it started at.
        var (column, byte, previous) = (0, 0, 0)
        for (offset, slot) in bounds {
            if slot & 1 == 0 {
                while column < line.count, byte + line[column].utf8.count <= offset {
                    (previous, byte, column) = (byte, byte + line[column].utf8.count, column + 1)
                }
                // An end before it, inside one character, walked past it.
                columns[slot] = byte > offset && previous <= offset ? column - 1 : column
            } else {
                while column < line.count, byte < offset {
                    (previous, byte, column) = (byte, byte + line[column].utf8.count, column + 1)
                }
                columns[slot] = column
            }
        }
        return ranges.indices.map { columns[$0 * 2]..<max(columns[$0 * 2], columns[$0 * 2 + 1]) }
    }
}
