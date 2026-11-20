//  🖥️ TUI — A Terminal UI framework for Swift
//  EditorLineStyles.swift
//
//  What a TextEditor's lines state of their own drawing — colours and
//  attributes, by stretches of a line — and the cache that keeps them for the
//  lines drawn (G3: B-ATTRED-2, B-ATTRED-5).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

/// What a cell draws beside its colours: bold, faint, italic, and its lines.
///
/// Part of a run's identity in the rows' run accumulator
/// (``TextFieldContentRenderer/RunAccumulator``), so a run closes where it
/// changes, as it closes where a colour does (G3, B-ATTRED-5).
struct CellDecoration: Equatable, Sendable {
    var isBold = false
    var isDim = false
    var isItalic = false
    /// The underline, or `nil` for none.
    var underline: Text.LineStyle?
    /// The strikethrough, or `nil` for none.
    var strikethrough: Text.LineStyle?

    /// Writes the decoration into `style`, beside whatever colours it has.
    func apply(to style: inout TextStyle) {
        if isBold { style.isBold = true }
        if isDim { style.isDim = true }
        if isItalic { style.isItalic = true }
        if let underline { style.underline = .some(underline) }
        if let strikethrough { style.strikethrough = .some(strikethrough) }
    }

    /// The decoration with its lines' own colours put through `transform`:
    /// faded, in a disabled editor (``EditorStyledRun/mappingColors(_:)``).
    func mappingLineColors(_ transform: (Color) -> Color) -> Self {
        guard underline != nil || strikethrough != nil else { return self }
        var mapped = self
        mapped.underline = underline?.mappingColor(transform)
        mapped.strikethrough = strikethrough?.mappingColor(transform)
        return mapped
    }

    /// The decoration as a terminal with `environment`'s line styles draws
    /// it, its lines' colours resolved by `environment`'s palette: each shape
    /// the terminal lacks a single line, each colour it lacks the text's own
    /// (B-ATTRED-6), as `Text` fits its own (``TextStyle/fittingLines(to:)``).
    @MainActor
    func fitted(to environment: EnvironmentValues) -> Self {
        fitted(to: environment.lineStyleSupport, palette: environment.palette)
    }

    /// The decoration as a terminal with `support` draws it, its lines'
    /// colours resolved by `palette` (``fitted(to:)-(EnvironmentValues)``).
    func fitted(to support: LineStyleSupport, palette: any Palette) -> Self {
        guard underline != nil || strikethrough != nil else { return self }
        var style = TextStyle()
        apply(to: &style)
        style = style.fittingLines(to: support).resolved(with: palette)
        var fitted = self
        fitted.underline = style.underline.flatMap { $0 }
        fitted.strikethrough = style.strikethrough.flatMap { $0 }
        return fitted
    }
}

/// A stretch of one of a ``TextEditor``'s lines, and what it states of its own
/// drawing: its colours, resolved, and its decoration (G3, B-ATTRED-5).
///
/// The rows draw it under the selection and a find match: a selection's
/// colours win over its colours and a match's field over its field, and both
/// keep its decoration, as `NSTextView` keeps a selected run's font.
struct EditorStyledRun: Equatable {
    /// The characters of the line it covers, as columns.
    var columns: Range<Int>
    /// Its ink, or `nil` for the editor's own.
    var foreground: Color?
    /// Its field, or `nil` for the editor's own.
    var background: Color?
    var decoration = CellDecoration()

    /// The run with every colour it states put through `transform` — its ink,
    /// its field and its lines' — and its attributes as they were: how a
    /// disabled editor fades it (``_TextEditorCore/RowStyling/runFade``).
    func mappingColors(_ transform: (Color) -> Color) -> Self {
        var mapped = self
        mapped.foreground = foreground.map(transform)
        mapped.background = background.map(transform)
        mapped.decoration = decoration.mappingLineColors(transform)
        return mapped
    }

    /// The run as a row starting at `start` of its line and ending before
    /// `end` holds it, in that row's columns, or `nil` where it is not on it.
    func clipped(toColumns start: Int, _ end: Int) -> Self? {
        let lower = max(columns.lowerBound, start)
        let upper = min(columns.upperBound, end)
        guard lower < upper else { return nil }
        var clipped = self
        clipped.columns = (lower - start)..<(upper - start)
        return clipped
    }

    /// The run of `runs`, ascending and apart, covering `column`, with
    /// `cursor` the index of the first run that may: moved on, so a row read
    /// left to right finds each in one pass.
    static func run(at column: Int, in runs: [Self], cursor: inout Int) -> Self? {
        while cursor < runs.count, runs[cursor].columns.upperBound <= column { cursor += 1 }
        guard cursor < runs.count, runs[cursor].columns.lowerBound <= column else { return nil }
        return runs[cursor]
    }
}

/// The styles of the lines an editor has drawn, read once a line from where
/// they come from and kept until an edit changes the line (G3, B-ATTRED-2):
/// a line never drawn is never read, so a large document costs a screenful.
struct EditorLineStyleCache {
    private var kept: [Int: [EditorStyledRun]] = [:]
    /// Each read line's paragraph alignment (A-ATTRED-3), `nil` inside for a
    /// line whose paragraph states none: read for the lines drawn, and for
    /// those the caret, a click or a vertical key reaches.
    private var alignments: [Int: TextAlignment?] = [:]
    /// Each read line's paragraph's rows a line (A-ATTRED-13), and, of those,
    /// the lines of more than one: read for the lines drawn and the caret's.
    private var lineRows: [Int: Int] = [:]
    private var spacedLines: [Int: Int] = [:]
    /// Each drawn line's runs with its highlighting over them
    /// (``EditorHighlightLayer``), while the editor has a highlighter: kept
    /// until the line, its highlighting or the styles' environment change.
    private var drawn: [Int: [EditorStyledRun]] = [:]

    /// How many lines' styles are kept.
    var count: Int { kept.count }

    /// How many lines' highlighted runs are kept.
    var drawnCount: Int { drawn.count }

    /// `line`'s styles: those kept, or `read`'s, kept from now on.
    mutating func runs(ofLine line: Int, reading read: (Int) -> [EditorStyledRun]) -> [EditorStyledRun] {
        if let runs = kept[line] { return runs }
        let runs = read(line)
        kept[line] = runs
        return runs
    }

    /// `line`'s highlighted runs, if kept. Not read through a closure, as
    /// ``runs(ofLine:reading:)`` is: making them reads the layout, which may
    /// clear this very cache.
    func drawnRuns(ofLine line: Int) -> [EditorStyledRun]? { drawn[line] }

    /// Keeps `runs` as `line`'s highlighted runs.
    mutating func keepDrawnRuns(_ runs: [EditorStyledRun], ofLine line: Int) { drawn[line] = runs }

    /// Forgets the highlighted runs of `lines`, or of every line: their
    /// highlighting, or the environment its styles were resolved in, changed.
    /// The lines' own styles stay.
    mutating func forgetDrawnRuns(ofLines lines: Range<Int>? = nil) {
        guard let lines else {
            drawn.removeAll()
            return
        }
        drawn = drawn.filter { !lines.contains($0.key) }
    }

    /// `line`'s paragraph alignment: that kept, or `read`'s, kept from now on.
    mutating func alignment(
        ofLine line: Int, reading read: (Int) -> TextAlignment?
    ) -> TextAlignment? {
        if let alignment = alignments[line] { return alignment }
        let alignment = read(line)
        alignments[line] = .some(alignment)
        return alignment
    }

    /// Reads `line`'s rows a line with `read`, unless it has been. Whether it
    /// was read now and takes more than one: the gaps need making again.
    mutating func readLineRows(ofLine line: Int, reading read: (Int) -> Int) -> Bool {
        guard lineRows[line] == nil else { return false }
        let rows = read(line)
        lineRows[line] = rows
        guard rows > 1 else { return false }
        spacedLines[line] = rows
        return true
    }

    /// The blank rows after each of each of `lineCount` lines' rows, from the
    /// lines read so far, or `nil` where none read takes more than a row.
    func gaps(lineCount: Int) -> [Int]? {
        guard !spacedLines.isEmpty else { return nil }
        var gaps = [Int](repeating: 0, count: lineCount)
        for (line, rows) in spacedLines where line < lineCount { gaps[line] = rows - 1 }
        return gaps
    }

    /// An edit replaced the lines `replaced` with `count` others: their styles
    /// go, those before stay, and those after move with their lines.
    mutating func replaceLines(_ replaced: Range<Int>, withCount count: Int) {
        kept = Self.moving(kept, replacing: replaced, withCount: count)
        alignments = Self.moving(alignments, replacing: replaced, withCount: count)
        lineRows = Self.moving(lineRows, replacing: replaced, withCount: count)
        spacedLines = Self.moving(spacedLines, replacing: replaced, withCount: count)
        drawn = Self.moving(drawn, replacing: replaced, withCount: count)
    }

    /// `kept`'s lines, those `replaced` gone and those after moved by the lines
    /// that took their place.
    private static func moving<Value>(
        _ kept: [Int: Value], replacing replaced: Range<Int>, withCount count: Int
    ) -> [Int: Value] {
        guard !kept.isEmpty else { return kept }
        let shift = count - replaced.count
        var moved: [Int: Value] = [:]
        moved.reserveCapacity(kept.count)
        for (line, value) in kept where !replaced.contains(line) {
            moved[line >= replaced.upperBound ? line + shift : line] = value
        }
        return moved
    }

    /// Forgets every line's styles: the text was replaced whole, or the styles
    /// came from somewhere else.
    mutating func removeAll() {
        kept.removeAll()
        alignments.removeAll()
        lineRows.removeAll()
        spacedLines.removeAll()
        drawn.removeAll()
    }
}
