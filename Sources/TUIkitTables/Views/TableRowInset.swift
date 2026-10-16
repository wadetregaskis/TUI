//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableRowInset.swift
//
//  The cell between a table's edge and its rows, drawn as part of each row so
//  a row's fill reaches the edge.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation

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
    static func inset(_ line: String) -> String {
        var consumed = 0
        var afterFill: Int?
        line.forEachANSISegment { segment in
            // `.ansi` is the segment kind (an escape sequence), not a colour.
            // swiftlint:disable:next framework_colour_literal
            guard case .ansi(let sequence, let isSGR) = segment else { return false }
            consumed += sequence.utf8.count
            if isSGR, let sets = backgroundEffect(of: sequence) { afterFill = sets ? consumed : nil }
            return true
        }
        guard let afterFill else { return " " + line }
        let split = line.utf8.index(line.utf8.startIndex, offsetBy: afterFill)
        return String(line[..<split]) + " " + String(line[split...])
    }

    /// What an SGR sequence does to the background: `true` when it states one,
    /// `false` when it puts back the terminal's own (`0`, an empty reset, `49`),
    /// `nil` when it leaves the background alone.
    static func backgroundEffect(of sequence: String) -> Bool? {
        // `ESC [` … `m`: the parameters between.
        let body = sequence.utf8.dropFirst(2).dropLast()
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
