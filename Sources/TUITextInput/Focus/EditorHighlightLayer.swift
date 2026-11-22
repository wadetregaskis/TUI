//  🖥️ TUI — A Terminal UI framework for Swift
//  EditorHighlightLayer.swift
//
//  Highlighting drawn over a TextEditor's text and never written into it: the
//  runs a highlighter gives a line, in UTF-8 offsets and interned styles, and
//  how a row draws them over the line's own styles (the highlighting design's
//  B-ATTRED-8 and 10, lane H1 of its §8.6).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

/// Where a stretch of highlighting starts in its line, and what it is drawn
/// in: a UTF-8 offset from the line's start (without its break) and a style
/// of ``EditorHighlightStyles``, 8 bytes in all (B-ATTRED-10). A run lasts to
/// the next run's start, or to the line's end.
///
/// Not ranges: a highlighter's runs cover the line, and the gaps between its
/// tokens are runs of ``EditorHighlightStyles/none``, as tree-sitter's
/// adapter fills them (§8.6).
struct EditorHighlightRun: Equatable, Sendable {
    var utf8Offset: Int32
    var style: UInt16

    /// A run from `utf8Offset`, clamped to what an `Int32` holds: an offset
    /// past a line is clamped to its end when drawn anyway.
    init(utf8Offset: Int, style: UInt16) {
        self.utf8Offset = Int32(clamping: utf8Offset)
        self.style = style
    }

    /// `runs`, which start at UTF-8 offsets of `line`, as the columns of its
    /// characters, each drawn in its style under ``EditorHighlightStyles``'
    /// environment; a run of no style, or of one that draws nothing, is left
    /// out.
    ///
    /// Never trusted (B-ATTRED-9, 15): an offset inside a character styles
    /// the whole character, so of two runs that start in one character the
    /// later wins; an offset that goes backwards is taken as the one before
    /// it, and one past the line as its end. Walks the line only as far as
    /// the last run's start.
    static func styledRuns(
        _ runs: [Self], in line: TextCharacters, styles: EditorHighlightStyles
    ) -> [EditorStyledRun] {
        guard !runs.isEmpty, !line.isEmpty else { return [] }
        var styled: [EditorStyledRun] = []
        // The character the walk is on, and the byte it starts at.
        var (column, byte) = (0, 0)
        var floor = 0
        var open: (column: Int, style: UInt16)?
        func close(at end: Int) {
            guard let open, open.column < end, var run = styles.style(open.style) else { return }
            run.columns = open.column..<end
            styled.append(run)
        }
        for run in runs {
            floor = max(floor, Int(run.utf8Offset))
            while column < line.count, byte + line.utf8Length(of: column) <= floor {
                byte += line.utf8Length(of: column)
                column += 1
            }
            close(at: column)
            open = (column, run.style)
        }
        close(at: line.count)
        return styled
    }
}

/// The styles highlighting is drawn in: each distinct token's
/// `AttributeContainer`, taken from the highlighter's style once and interned
/// to a 16-bit index (B-ATTRED-10), and each resolved for drawing once per
/// environment, so a palette change re-resolves them without asking again.
///
/// The vocabulary is the attributed editor's (``EditorStyledRun/init(_:columns:styling:)``):
/// colours, a font's tier and weight as bold or faint, italic, its lines.
struct EditorHighlightStyles {
    /// The style of a run drawn in the editor's own colours: the gaps
    /// between tokens.
    static let none: UInt16 = 0

    private var indices: [AnyHashable: UInt16] = [:]
    /// Each style's attributes, by index; the first, ``none``'s, empty.
    private(set) var containers = [AttributeContainer()]
    /// Each style as drawn under ``resolvedUnder``, by index.
    private var resolved: [EditorStyledRun?] = [nil]
    /// The environment the styles were last resolved under, or `nil` before
    /// the editor first drew.
    private(set) var resolvedUnder: EditorAttributedStyling?

    /// `token`'s style: the one it was given, or the next, from `style`.
    /// Past 65,535 styles a token is drawn in ``none``.
    mutating func index<Token: Hashable>(of token: Token, style: (Token) -> AttributeContainer) -> UInt16 {
        let key = AnyHashable(token)
        if let index = indices[key] { return index }
        guard containers.count <= Int(UInt16.max) else { return Self.none }
        let index = UInt16(containers.count)
        let container = style(token)
        containers.append(container)
        resolved.append(resolvedUnder.flatMap { Self.resolve(container, under: $0) })
        indices[key] = index
        return index
    }

    /// Resolves every style under `styling`, unless they are already. Whether
    /// they were not: the runs drawn in the old ones must go.
    mutating func adopt(_ styling: EditorAttributedStyling) -> Bool {
        guard styling != resolvedUnder else { return false }
        resolvedUnder = styling
        resolved = containers.map { Self.resolve($0, under: styling) }
        return true
    }

    /// Style `index` as drawn, its columns empty, or `nil` for ``none``, an
    /// index out of range, or a style that draws nothing.
    func style(_ index: UInt16) -> EditorStyledRun? {
        Int(index) < resolved.count ? resolved[Int(index)] : nil
    }

    /// `container` as an attributed editor draws a run with its attributes:
    /// read off a one-space string's substring, not its `runs`, which a
    /// program on Windows cannot link (`Documentation/Windows port.md`,
    /// "Toolchain").
    private static func resolve(_ container: AttributeContainer, under styling: EditorAttributedStyling)
        -> EditorStyledRun?
    {
        let sample = AttributedString(" ", attributes: container)
        return EditorStyledRun(sample[sample.startIndex..<sample.endIndex], columns: 0..<0, styling: styling)
    }
}

/// A ``TextEditor``'s highlighting (B-ATTRED-8): where each line's runs come
/// from, and the styles they name. The editor reads a line's runs only when
/// it draws the line, and keeps what it drew until the line, its runs or the
/// environment change (``EditorLineStyleCache``).
struct EditorHighlightLayer {
    /// A line's runs as the highlighter last gave them, ascending, or none.
    var runs: (Int) -> [EditorHighlightRun]
    var styles: EditorHighlightStyles
}

extension CellDecoration {
    /// This decoration drawn over `below`: what it sets wins, and what it
    /// leaves unset is `below`'s (B-ATTRED-8).
    func over(_ below: Self) -> Self {
        Self(
            isBold: isBold || below.isBold, isDim: isDim || below.isDim, isItalic: isItalic || below.isItalic,
            underline: underline ?? below.underline, strikethrough: strikethrough ?? below.strikethrough)
    }
}

extension EditorStyledRun {
    /// `top` drawn over `bottom`, both ascending and apart: where they meet,
    /// what a run of `top` sets wins and what it leaves unset is `bottom`'s
    /// (B-ATTRED-8: highlighting over an attributed value's own runs). In one
    /// pass, so its cost is the runs'.
    static func overlaying(_ top: [Self], on bottom: [Self]) -> [Self] {
        guard !top.isEmpty else { return bottom }
        guard !bottom.isEmpty else { return top }
        var result: [Self] = []
        result.reserveCapacity(top.count + bottom.count)
        var (upper, lower) = (0, 0)
        var position = min(top[0].columns.lowerBound, bottom[0].columns.lowerBound)
        while upper < top.count || lower < bottom.count {
            let above = upper < top.count ? top[upper] : nil
            let below = lower < bottom.count ? bottom[lower] : nil
            // The runs of each that hold `position`.
            let aboveIn = above.flatMap { $0.columns.lowerBound <= position ? $0 : nil }
            let belowIn = below.flatMap { $0.columns.lowerBound <= position ? $0 : nil }
            // Where the stretch from `position` ends: at the first edge of either.
            var end = Int.max
            if let above { end = min(end, aboveIn == nil ? above.columns.lowerBound : above.columns.upperBound) }
            if let below { end = min(end, belowIn == nil ? below.columns.lowerBound : below.columns.upperBound) }
            var run: Self?
            switch (aboveIn, belowIn) {
            case (let above?, let below?):
                run = above
                run?.foreground = above.foreground ?? below.foreground
                run?.background = above.background ?? below.background
                run?.decoration = above.decoration.over(below.decoration)
            case (let only?, nil), (nil, let only?): run = only
            case (nil, nil): run = nil
            }
            if var run, position < end {
                run.columns = position..<end
                result.append(run)
            }
            position = max(position, end)
            if let above, above.columns.upperBound <= position { upper += 1 }
            if let below, below.columns.upperBound <= position { lower += 1 }
        }
        return result
    }

    /// Those of `runs`, ascending and apart, that a row from column `start`
    /// to before `end` holds, in the row's columns: found by a binary search,
    /// so a row costs its own runs, not its line's.
    static func clipping(_ runs: [Self], toColumns start: Int, _ end: Int) -> [Self] {
        guard !runs.isEmpty else { return [] }
        var (low, high) = (0, runs.count)
        while low < high {
            let middle = (low + high) / 2
            if runs[middle].columns.upperBound <= start { low = middle + 1 } else { high = middle }
        }
        var clipped: [Self] = []
        var index = low
        while index < runs.count, runs[index].columns.lowerBound < end {
            if let run = runs[index].clipped(toColumns: start, end) { clipped.append(run) }
            index += 1
        }
        return clipped
    }
}
