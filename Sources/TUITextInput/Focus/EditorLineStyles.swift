//  🖥️ TUI — A Terminal UI framework for Swift
//  EditorLineStyles.swift
//
//  What a TextEditor's lines state of their own drawing — colours and
//  attributes, by stretches of a line — and the cache that keeps them for the
//  lines drawn (G3: B-ATTRED-2, B-ATTRED-5).
//
//  Created by Wade Tregaskis
//  License: MIT

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

    /// The decoration as a terminal with `environment`'s line styles draws
    /// it, its lines' colours resolved by `environment`'s palette: each shape
    /// the terminal lacks a single line, each colour it lacks the text's own
    /// (B-ATTRED-6), as `Text` fits its own (``TextStyle/fittingLines(to:)``).
    @MainActor
    func fitted(to environment: EnvironmentValues) -> Self {
        guard underline != nil || strikethrough != nil else { return self }
        var style = TextStyle()
        apply(to: &style)
        style = style.fittingLines(to: environment.lineStyleSupport).resolved(with: environment.palette)
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

    /// How many lines' styles are kept.
    var count: Int { kept.count }

    /// `line`'s styles: those kept, or `read`'s, kept from now on.
    mutating func runs(ofLine line: Int, reading read: (Int) -> [EditorStyledRun]) -> [EditorStyledRun] {
        if let runs = kept[line] { return runs }
        let runs = read(line)
        kept[line] = runs
        return runs
    }

    /// An edit replaced the lines `replaced` with `count` others: their styles
    /// go, those before stay, and those after move with their lines.
    mutating func replaceLines(_ replaced: Range<Int>, withCount count: Int) {
        guard !kept.isEmpty else { return }
        let shift = count - replaced.count
        var moved: [Int: [EditorStyledRun]] = [:]
        moved.reserveCapacity(kept.count)
        for (line, runs) in kept where !replaced.contains(line) {
            moved[line >= replaced.upperBound ? line + shift : line] = runs
        }
        kept = moved
    }

    /// Forgets every line's styles: the text was replaced whole, or the styles
    /// came from somewhere else.
    mutating func removeAll() {
        kept.removeAll()
    }
}
