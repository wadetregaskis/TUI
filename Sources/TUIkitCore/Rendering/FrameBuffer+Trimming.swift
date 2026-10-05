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
    public func trimmingTrailingBlankCells() -> FrameBuffer {
        var trimmed = lines
        var changed = false
        for index in trimmed.indices {
            let keep = trimmed[index].visibleWidthBeforeTrailingBlanks()
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
