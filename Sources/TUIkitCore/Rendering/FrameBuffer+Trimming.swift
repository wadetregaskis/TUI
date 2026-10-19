//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FrameBuffer+Trimming.swift
//
//  Created by Wade Tregaskis
//  License: MIT

extension FrameBuffer {
    /// A copy with each line's trailing unstyled blank cells removed.
    ///
    /// For buffers that are drawn OVER something — a floating drag preview,
    /// above all. Compositing is opaque per cell, so a row padded to its
    /// container's width erases a column of whatever it passes over for every
    /// blank it carries. Trailing blanks that carry a background are kept:
    /// there they are fill, not padding.
    ///
    /// Lines are left ragged, which ``FrameBuffer`` supports (see
    /// ``linesAreUniformWidth``) and ``composited(with:at:)`` honours line by
    /// line — so a multi-line preview keeps its own silhouette.
    ///
    /// A blank cell an animated run repaints is kept too, as the overflow's
    /// painted columns keep it (`paintedColumnsByLine(inRows:)`): a caret blinking on
    /// a trailing blank of a dragged row, or of a row a transition slides, is
    /// drawn there whatever the line holds under it, and trimmed it lost its
    /// cell — and the caret with it — for the length of the drag.
    public func trimmingTrailingBlankCells() -> FrameBuffer {
        var trimmed = lines
        var changed = false
        // Where each line's last run ends: nothing to look up, and nothing
        // allocated, for the buffer with no runs, which is nearly every one.
        var runEnds: [Int: Int] = [:]
        for run in animatedCells where run.width > 0 {
            runEnds[run.offsetY] = max(runEnds[run.offsetY] ?? 0, run.offsetX + run.width)
        }
        for index in trimmed.indices {
            let keep = max(trimmed[index].visibleWidthBeforeTrailingBlanks(), runEnds[index] ?? 0)
            let lineWidth = trimmed[index].strippedLength
            guard keep < lineWidth else { continue }
            trimmed[index] = trimmed[index].ansiAwarePrefix(
                visibleCount: keep, knownVisibleWidth: lineWidth)
            changed = true
        }
        guard changed else { return self }
        var copy = self
        copy.lines = trimmed  // didSet remeasures the width and drops the stale per-line widths
        return copy
    }
}
