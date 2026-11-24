//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameBuffer+Clamping.swift
//
//  Created by Wade Tregaskis
//  License: MIT

extension FrameBuffer {
    /// A copy cut to fit `width` × `height` cells, or `self` when it already
    /// does.
    ///
    /// The boundary every container enforces on content that came back larger
    /// than the space it was given. Rows past `height` are dropped whole;
    /// lines longer than `width` are cut with
    /// ``String/ansiAwarePrefix(visibleCount:knownVisibleWidth:)``, so
    /// the cut counts terminal cells rather than characters, never splits a
    /// wide glyph, keeps the styling that was in force, and closes it where the
    /// cut left it on, so what is drawn after the line is not drawn in it. A
    /// wide glyph cut in half there leaves its kept cell blank but in the run's
    /// styling, so a filled view cut through one is filled to the cut.
    ///
    /// Hit-test regions are trimmed to the surviving box and dropped when
    /// nothing of them remains — a clamp at a container edge is final, and a
    /// region kept for cells that were cut away would be a phantom click
    /// target wherever the next sibling lands. Overlay layers are *kept*
    /// regardless: they float free of the flow and are composited at the root
    /// (see `overlays`).
    ///
    /// - Parameters:
    ///   - width: Maximum width in terminal cells. Negative values clamp to 0.
    ///   - height: Maximum height in lines. Negative values clamp to 0.
    /// - Returns: The clamped buffer.
    public func clamped(toWidth width: Int, height: Int) -> FrameBuffer {
        let maxWidth = max(0, width)
        let maxHeight = max(0, height)

        // Fast path: already within bounds.
        if self.width <= maxWidth && self.height <= maxHeight {
            return self
        }

        var clippedLines = self.height > maxHeight ? Array(lines.prefix(maxHeight)) : lines
        var resultWidth = 0
        // The widths this walk learns are carried out: a consumer that pads
        // these lines next (a scroll window, a scrollbar, the writer) then
        // does not scan them again to learn what was just measured here.
        var clippedWidths: [Int] = []
        clippedWidths.reserveCapacity(clippedLines.count)
        for index in clippedLines.indices {
            // `self.width`: the parameter `width` is the TARGET, and shadows it.
            let known: Int? = linesAreUniformWidth ? self.width : lineWidths?[index]
            let lineWidth = known ?? clippedLines[index].strippedLength
            if lineWidth > maxWidth {
                let (clipped, clippedWidth) = clippedLines[index].ansiAwarePrefixWithWidth(
                    visibleCount: maxWidth, knownVisibleWidth: lineWidth)
                clippedLines[index] = clipped
                resultWidth = max(resultWidth, clippedWidth)
                clippedWidths.append(clippedWidth)
            } else {
                resultWidth = max(resultWidth, lineWidth)
                clippedWidths.append(lineWidth)
            }
        }
        let uniform = clippedWidths.allSatisfy { $0 == resultWidth }
        var result = FrameBuffer(
            lines: clippedLines, width: resultWidth,
            uniformWidth: uniform, lineWidths: uniform ? nil : clippedWidths)
        // Overlay layers are free-floating and composited separately at the
        // root — clamping the in-flow content must never discard them. The
        // old comment claimed the same for hit regions, but theirs describe
        // IN-FLOW cells: a clamp at a container boundary is final, and a
        // region kept for rows or columns that were clipped away is a
        // phantom click target sitting wherever later siblings land. Trimmed
        // to the box, dropped when nothing remains.
        result.overlays = overlays
        // Opacity regions are IN-FLOW, like hit regions — a rectangle over
        // cells that are in this buffer — and are trimmed on the same rule.
        // Carried verbatim, a region kept for clipped-away rows named
        // whatever a later sibling put there: a TabView's filler rows and its
        // bottom rule faded because a tab's content had been cut to the panel.
        result.opacityRegions = opacityRegions.compactMap { region -> OpacityRegion? in
            region.clipped(toColumns: 0..<maxWidth, rows: 0..<maxHeight)
        }
        result.hitTestRegions = hitTestRegions.compactMap { region -> HitTestRegion? in
            region.clipped(toColumns: 0..<maxWidth, rows: 0..<maxHeight)
        }
        // Runs describe CELLS, so unlike the free-floating layers above they
        // follow the clip. A run whose ROW is clipped away is gone — scrolled
        // out of a viewport it must stop, or it keeps repainting over whatever
        // took its place. A run the WIDTH cuts through is cut to the cells that
        // survive, not dropped: dropping it whole froze the visible part of a
        // pulsing label at a container's right edge, which read as the
        // animation dying wherever a clamp happened to fall. The same cut the
        // overlay punch makes (`animatedCellsPunched`).
        result.animatedCells = animatedCells.compactMap {
            $0.clipped(toCanvasColumns: maxWidth, rows: maxHeight)
        }
        return result
    }
}
