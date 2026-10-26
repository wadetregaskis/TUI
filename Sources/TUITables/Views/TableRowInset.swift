//  🖥️ TUI — A Terminal UI framework for Swift
//  TableRowInset.swift
//
//  The cell between a table's edge and its rows, drawn as part of each row so
//  a row's fill reaches the edge.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation

/// The one cell a table keeps between its edge (or its border) and its rows,
/// drawn by the rows themselves rather than as the container's padding.
///
/// As padding it was a cell no row could paint, so a striped, selected or
/// focused row's fill began one cell in from the table's leading edge while it
/// ran to the trailing one — a notch down the left of every filled row, plain
/// to see on a `.surface` table, where the rows are bands of their own. Drawn
/// here it opens on whatever fill the row opens on, and the row's breath and
/// opacity claims are widened to cover it, so it is part of the row.
///
/// The table's geometry is unchanged: the container's leading padding is
/// taken off by exactly the cell this adds (`_TableCore.drawnContainerPadding`),
/// so `_TableCore.containerPadding` still says where the rows' first column is
/// — what the mouse maths and the analytic measure read.
enum TableRowInset {
    /// `line` with the inset cell before it, on the fill the line opens with.
    ///
    /// The cell is a space straight after the escape that opens the line's
    /// fill, so it takes the fill and nothing the line states after it — the
    /// colour of the row's text is not the cell's. A line that opens with no
    /// fill is the line it was with a space in front.
    ///
    /// On the line's bytes, and only as far as its leading escapes: the fill a
    /// row opens on is stated before its first visible cell, so nothing after
    /// that can change where the cell goes. Every line of every row comes
    /// through here every frame — walked as segments, which decoded the text up
    /// to the next escape to hand over its first character, it was a tenth of
    /// a frame of a table of wrapped rows.
    static func inset(_ line: String) -> String {
        var line = line
        return line.withUTF8(inset(bytes:))
    }

    /// ``inset(_:)-(String)`` on the line's bytes, written in one allocation.
    ///
    /// A function of its own rather than a closure in `withUTF8`: nested
    /// there, two closures' types were left for the solver to infer together,
    /// which the type-check guard's limits time out on.
    private static func inset(bytes: UnsafeBufferPointer<UInt8>) -> String {
        guard let base = bytes.baseAddress else { return " " }
        let split: Int = leadingFillEnd(of: bytes) ?? 0
        let count: Int = bytes.count
        return String(unsafeUninitializedCapacity: count + 1) { (out: UnsafeMutableBufferPointer<UInt8>) -> Int in
            guard let target = out.baseAddress else { return 0 }
            target.initialize(from: base, count: split)
            target[split] = UInt8(ascii: " ")
            (target + split + 1).initialize(from: base + split, count: count - split)
            return count + 1
        }
    }

    /// The offset just past the escape that leaves the background set, among
    /// the escapes `bytes` opens with — `nil` if they leave it the terminal's.
    static func leadingFillEnd(of bytes: UnsafeBufferPointer<UInt8>) -> Int? {
        var index = 0
        var afterFill: Int?
        while index < bytes.count, bytes[index] == 0x1B {
            let (end, isSGR) = String.escapeSequenceEnd(startingAt: index, in: bytes)
            if isSGR, let sets = backgroundEffect(of: bytes[index..<end]) { afterFill = sets ? end : nil }
            index = end
        }
        return afterFill
    }

    /// What an SGR sequence does to the background: `true` when it states one,
    /// `false` when it puts back the terminal's own (`0`, an empty reset, `49`),
    /// `nil` when it leaves the background alone.
    static func backgroundEffect<Bytes: BidirectionalCollection<UInt8>>(of sequence: Bytes) -> Bool? {
        // `ESC [` … `m`: the parameters between.
        let body = sequence.dropFirst(2).dropLast()
        guard !body.isEmpty else { return false }
        var effect: Bool?
        var skip = 0
        var colourIntroducer = false
        for parameter in body.split(separator: UInt8(ascii: ";"), omittingEmptySubsequences: false) {
            // A colon-separated sub-parameter list (`48:2::r:g:b`) is one
            // parameter; its first field says what it is.
            let head = parameter.prefix { $0 != UInt8(ascii: ":") }
            let value = head.reduce(0) { value, byte in
                // -1, and kept there, for a field that is not a number.
                guard value >= 0, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) else { return -1 }
                return value * 10 + Int(byte - UInt8(ascii: "0"))
            }
            if skip > 0 {
                skip -= 1
                continue
            }
            if colourIntroducer {
                // `5;n` or `2;r;g;b` after a 38 or 48.
                skip = value == 5 ? 1 : value == 2 ? 3 : 0
                colourIntroducer = false
                continue
            }
            switch value {
            case 0, 49: effect = false
            case 40...47, 100...107: effect = true
            case 48:
                effect = true
                colourIntroducer = !parameter.contains(UInt8(ascii: ":"))
            case 38, 58: colourIntroducer = !parameter.contains(UInt8(ascii: ":"))
            default: break
            }
        }
        return effect
    }

    /// `run` with the inset cell before it: widened over the cell when it
    /// begins at the row's first column — the row's breath is the row's fill —
    /// and moved one cell along otherwise.
    static func inset(_ run: AnimatedCellRun) -> AnimatedCellRun {
        guard run.offsetX == 0 else {
            var moved = run
            moved.offsetX += 1
            return moved
        }
        let alpha = run.alpha.map { alpha in
            AnimatedRunAlpha(
                perFrame: alpha.perFrame.map { spans in
                    spans.map { span in
                        var span = span
                        if span.start == 0 { span.cells += 1 } else { span.start += 1 }
                        return span
                    }
                },
                drawnIndex: alpha.drawnIndex)
        }
        var widened = AnimatedCellRun(
            offsetX: 0, offsetY: run.offsetY, width: run.width + 1, frames: run.frames.map(inset),
            frameTicks: run.frameTicks, clock: run.clock, alpha: alpha)
        widened.ground = run.ground.map(inset)
        widened.groundUnderStatedDefault = run.groundUnderStatedDefault.map(inset)
        return widened
    }

    /// `claim` with the inset cell before it, widened over the cell or moved
    /// along as ``inset(_:)-(AnimatedCellRun)`` does a run.
    static func inset(_ claim: OpacityRegion) -> OpacityRegion {
        var claim = claim
        if claim.offsetX == 0 { claim.width += 1 } else { claim.offsetX += 1 }
        return claim
    }
}

/// The cells a table keeps between its rows and its trailing edge (or border),
/// drawn by the rows themselves for the reason ``TableRowInset`` draws the
/// leading one.
///
/// As the container's padding, the cell was a space appended after the row's
/// line, so it took whatever fill the line left open: a cursor row's colour at
/// the frame that was drawn. The row's breath covered the row's own cells, so
/// the last cell held that colour while the rest breathed — plain in the
/// README's Unicode clip, filmed in Ghostty and iTerm2 alike. Drawn here, the
/// cell is the same space after the same line, and a run or a claim that
/// reaches the line's end is widened over it.
enum TableTrailingInset {
    /// `line` with `cells` spaces after it, taking the fill it leaves open — the
    /// cells the container's padding drew, as it drew them.
    static func inset(_ line: String, cells: Int) -> String {
        cells > 0 ? line + String(repeating: " ", count: cells) : line
    }

    /// `run`, widened over the `cells` after it when it reaches the end of its
    /// line, `lineWidth` cells wide; as it was otherwise.
    static func inset(_ run: AnimatedCellRun, cells: Int, lineWidth: Int) -> AnimatedCellRun {
        guard cells > 0, run.offsetX + run.width == lineWidth else { return run }
        let width = run.width
        let alpha = run.alpha.map { alpha in
            AnimatedRunAlpha(
                perFrame: alpha.perFrame.map { spans in
                    spans.map { span in
                        var span = span
                        if span.start + span.cells == width { span.cells += cells }
                        return span
                    }
                },
                drawnIndex: alpha.drawnIndex)
        }
        var widened = AnimatedCellRun(
            offsetX: run.offsetX, offsetY: run.offsetY, width: width + cells,
            frames: run.frames.map { inset($0, cells: cells) },
            frameTicks: run.frameTicks, clock: run.clock, alpha: alpha)
        widened.ground = run.ground.map { inset($0, cells: cells) }
        widened.groundUnderStatedDefault = run.groundUnderStatedDefault.map { inset($0, cells: cells) }
        return widened
    }

    /// `claim`, widened over the `cells` after it when it reaches the end of its
    /// line, `lineWidth` cells wide.
    static func inset(_ claim: OpacityRegion, cells: Int, lineWidth: Int) -> OpacityRegion {
        guard cells > 0, claim.offsetX + claim.width == lineWidth else { return claim }
        var claim = claim
        claim.width += cells
        return claim
    }
}
