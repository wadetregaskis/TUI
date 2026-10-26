//  🖥️ TUI — A Terminal UI framework for Swift
//  GradientHalfRows.swift
//
//  A ramp behind blank cells drawn two samples a cell — the top half's and the
//  bottom half's, by the shapes' own half-block rule — where the terminal
//  draws Block Elements to the line's edges (decisions B95).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIStyling

/// A `.background` ramp's rows at half-row resolution: each BARE cell of the
/// content — a space with no styling in force — drawn as
/// ``ShapeHalfBlocks/cell(upper:lower:)`` draws a rasterized shape's cell
/// (`▄` in the bottom half's colour over the top half's, or a space where they
/// agree), and every other cell on the one sample it had.
///
/// Made only where it can show and costs nothing it should not
/// (``init(paint:sampler:opaque:extent:context:)``): a ramp that changes down
/// a column, opaque throughout, with no blend mode, on a terminal with colour
/// whose Block Elements fill the line. Apple Terminal draws them short of it
/// (Terminal compatibility survey, "Apple Terminal draws Block Elements short
/// of the line"), where the halves would be stripes, so it keeps one sample a
/// cell, as a rectangle-family shape's corners do there.
struct GradientHalfRows {
    /// The ramp at half rows: row `2y` is cell row `y`'s top half, `2y + 1`
    /// its bottom.
    private let halves: RampSampler
    /// The ramp at whole cells, for the cells that are not bare.
    private let cells: RampSampler
    private let palette: any Palette
    /// The escape that starts a run of each pair of half entries, and the
    /// glyph the run repeats, worked out once.
    private var spelled: [HalfPair: (opening: String, glyph: Character)] = [:]

    /// The two entries a bare cell takes, top and bottom.
    private struct HalfPair: Hashable {
        let upper: Int
        let lower: Int
    }

    /// A run of a row's cells that take one drawing.
    private enum Piece: Equatable {
        /// Bare cells, at these two half entries.
        case halves(HalfPair)
        /// The content's own cells, on this one-sample entry.
        case content(Int)
    }

    /// `nil` where the halves would not show, or not show right: see the type.
    init?(paint: Paint, sampler: RampSampler, opaque: Bool, extent: GradientFrame, context: RenderContext) {
        let depth = ColorDepth.current
        guard opaque, paint.blendMode == nil, sampler.variesDownColumn, depth != .noColor,
            context.environment.blockElementsFillTheLine,
            let halves = RampSampler(
                halfRowsOf: paint, extent: extent, depth: depth, cellAspect: context.environment.imageCellAspect)
        else { return nil }
        self.halves = halves
        self.cells = sampler
        self.palette = context.environment.palette
    }

    /// Row `row` of the content — `padded`, `width` cells — with the ramp
    /// behind it: halves under its bare cells, `oneSample` under the rest.
    ///
    /// A row holding an escape that is not SGR (a hyperlink) is drawn by
    /// `oneSample` whole: which of its spaces are bare is not worth deciding.
    ///
    /// - Parameters:
    ///   - oneSample: How the row is painted at one sample a cell — the
    ///     background's own row painter — for a row that keeps it.
    ///   - escape: The background escape of a one-sample ramp entry, from the
    ///     background's own table.
    mutating func row(
        _ padded: String, row: Int, width: Int, oneSample: (String, Int) -> String,
        escape: (Int) -> String
    ) -> String {
        let allBare = padded.utf8.allSatisfy { $0 == 0x20 }
        let bare: [Bool]
        if allBare {
            bare = []
        } else if let found = padded.bareCells(width: width) {
            guard found.contains(true) else { return oneSample(padded, row) }
            bare = found
        } else {
            return oneSample(padded, row)
        }
        let pieces = pieces(row: row, width: width, isBare: { allBare || bare[$0] })
        var result = ""
        result.reserveCapacity(width * 40 + padded.utf8.count)
        guard !allBare else {
            for piece in pieces {
                if case .halves(let pair) = piece.what { result += halfRun(pair, count: piece.columns.count) }
            }
            return result
        }
        var afterContent = false
        padded.ansiAwareSlicedRuns(
            runCount: pieces.count, width: { pieces[$0].columns.count },
            receive: { index, slice in
                switch pieces[index].what {
                case .halves(let pair):
                    // The content's styling may still be in force where its
                    // run ended without a reset: the half cells state theirs
                    // on a clean slate.
                    if afterContent { result += ANSIRenderer.reset }
                    result += halfRun(pair, count: pieces[index].columns.count)
                    afterContent = false
                case .content(let entry):
                    // As the background's own painter cuts a row at a ramp's
                    // boundaries: the fill restated after every reset inside.
                    let fill = escape(entry)
                    result += fill
                    result += ANSIRenderer.restating(fill, afterResetsIn: slice)
                    result += ANSIRenderer.reset
                    afterContent = true
                }
            })
        return result
    }

    /// Row `row`'s cells grouped into runs that take one drawing.
    private func pieces(row: Int, width: Int, isBare: (Int) -> Bool) -> [(columns: Range<Int>, what: Piece)] {
        let upperTerm = halves.rowTerm(row * 2)
        let lowerTerm = halves.rowTerm(row * 2 + 1)
        let cellTerm = cells.rowTerm(row)
        var pieces: [(columns: Range<Int>, what: Piece)] = []
        for column in 0..<width {
            let what: Piece =
                isBare(column)
                ? .halves(
                    HalfPair(
                        upper: halves.entry(column: column, rowTerm: upperTerm),
                        lower: halves.entry(column: column, rowTerm: lowerTerm)))
                : .content(cells.entry(column: column, rowTerm: cellTerm))
            if let last = pieces.last, last.what == what {
                pieces[pieces.count - 1].columns = last.columns.lowerBound..<(column + 1)
            } else {
                pieces.append((column..<(column + 1), what))
            }
        }
        return pieces
    }

    /// `count` bare cells at `pair`, closed with a reset.
    private mutating func halfRun(_ pair: HalfPair, count: Int) -> String {
        let run: (opening: String, glyph: Character)
        if let cached = spelled[pair] {
            run = cached
        } else {
            // A mesh's ramp grows as entries are named, so it is read after
            // `entry`, which `pieces` has already asked.
            let cell = ShapeHalfBlocks.cell(
                upper: halves.ramp[pair.upper].resolve(with: palette),
                lower: halves.ramp[pair.lower].resolve(with: palette))
            var style = TextStyle()
            style.foregroundColor = cell.ink?.opaqueSpelling
            style.backgroundColor = cell.field?.opaqueSpelling
            run = (ANSIRenderer.styleSequence(for: style) ?? "", cell.glyph)
            spelled[pair] = run
        }
        return run.opening + String(repeating: run.glyph, count: count) + ANSIRenderer.reset
    }
}

extension String {
    /// Which of this row's first `width` cells are bare — a space drawn with
    /// nothing in force: no colour, no attribute — or `nil` where the row
    /// holds an escape that is not SGR, a hyperlink's, say.
    ///
    /// A bare cell is one the content leaves to its background, which is what
    /// lets a ramp draw a glyph of its own there.
    func bareCells(width: Int) -> [Bool]? {
        var bare = [Bool](repeating: false, count: max(0, width))
        var state = SGRState()
        let plain = SGRState()
        var column = 0
        var understood = true
        forEachANSISegment { segment in
            switch segment {
            // swiftlint:disable:next framework_colour_literal - an escape segment, not a colour
            case .ansi(let sequence, let isSGR):
                guard isSGR else {
                    understood = false
                    return false
                }
                state.apply(sequence)
            case .visible(let character):
                if character == " ", state == plain, column < width { bare[column] = true }
                column += max(0, character.terminalWidth)
            }
            return column < width
        }
        return understood ? bare : nil
    }
}
