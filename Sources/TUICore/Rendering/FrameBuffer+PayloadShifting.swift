//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameBuffer+PayloadShifting.swift
//
//  Moving a buffer's side payloads — overlay layers, hit-test regions, animated
//  runs and opacity claims — with the cells they describe. Split from
//  `FrameBuffer.swift`, which had reached the file-length limit.
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Overlay Layer Propagation

extension FrameBuffer {
    /// Returns this buffer's ``overlays``, each shifted by `(dx, dy)`.
    ///
    /// Combining operations call this to keep an overlay layer pinned to the
    /// content it was emitted alongside: the layer moves by exactly the same
    /// amount as the lines it accompanies.
    ///
    /// - Parameters:
    ///   - dx: The horizontal shift in columns.
    ///   - dy: The vertical shift in rows.
    /// - Returns: The shifted overlay layers (empty if there are none).
    package func shiftedOverlays(byX dx: Int, y dy: Int) -> [OverlayLayer] {
        guard !overlays.isEmpty else { return [] }
        guard dx != 0 || dy != 0 else { return overlays }
        return overlays.map { $0.shifted(byX: dx, y: dy) }
    }

    /// Returns a buffer with `newLines` as its content, carrying this buffer's
    /// overlay layers shifted by `(overlayShiftX, overlayShiftY)`.
    ///
    /// Use this in place of `FrameBuffer(lines:)` whenever a view or modifier
    /// rebuilds its line content from a child buffer (padding, borders,
    /// alignment, …). The shift should match however far the child's content
    /// moved within `newLines` — for example, padding shifts by its leading /
    /// top insets, a border by `(1, 1)`.
    ///
    /// - Parameters:
    ///   - newLines: The rebuilt line content.
    ///   - width: The result's visible width, when the caller already knows it
    ///     (padding: the input width plus its horizontal insets). Skips the
    ///     per-line re-measure `FrameBuffer(lines:)` would do. `nil` keeps that
    ///     measuring path.
    ///   - uniformWidth: As ``init(lines:width:uniformWidth:lineWidths:)``, and
    ///     honoured only alongside an explicit `width` — the measuring path
    ///     works uniformity out for itself.
    ///   - lineWidths: Likewise, and carried verbatim rather than shifted:
    ///     per-line widths are position-independent.
    ///   - overlayShiftX: How far the content moved horizontally.
    ///   - overlayShiftY: How far the content moved vertically.
    /// - Returns: A buffer with the new lines and all four side payloads
    ///   shifted: overlay layers, hit-test regions, animated cell runs and
    ///   opacity regions.
    public func replacingLines(
        _ newLines: [String],
        width: Int? = nil,
        uniformWidth: Bool = false,
        lineWidths: [Int]? = nil,
        overlayShiftX: Int = 0,
        overlayShiftY: Int = 0
    ) -> FrameBuffer {
        // When the caller already knows the result width (e.g. padding: the
        // input width plus the horizontal insets), pass it to skip the
        // re-measure of every line that `FrameBuffer(lines:)` → `computeWidth`
        // would do. `nil` keeps the original recompute behaviour. `uniformWidth`
        // and `lineWidths` are only honoured alongside an explicit `width`; the
        // measuring path computes width/uniformity itself and leaves the per-line
        // widths unknown. Per-line widths are position-independent, so they are
        // carried verbatim (no shift) when the caller supplies them.
        var result = width.map {
            FrameBuffer(
                lines: newLines, width: $0, uniformWidth: uniformWidth, lineWidths: lineWidths)
        } ?? FrameBuffer(lines: newLines)
        result.overlays = shiftedOverlays(byX: overlayShiftX, y: overlayShiftY)
        result.hitTestRegions = shiftedHitTestRegions(
            byX: overlayShiftX, y: overlayShiftY)
        // Runs move with the cells they describe, exactly like the regions
        // above. Omitting them here is not a missing animation but a FROZEN one:
        // the run loop keeps the clock alive on the strength of the runs it
        // finds on the final buffer, so a run lost on the way up stops the clock
        // for everything (see `AnimatedRunPropagationTests`).
        result.animatedCells = shiftedAnimatedCells(byX: overlayShiftX, y: overlayShiftY)
        // Content-preserving, so the faded regions travel with the content. A
        // `.padding` or `.frame` around a faded view must not make it opaque,
        // and the shift is the same one its runs and regions take.
        result.opacityRegions = shiftedOpacityRegions(byX: overlayShiftX, y: overlayShiftY)
        return result
    }
}

// MARK: - Hit-Test Region Propagation

extension FrameBuffer {
    /// Returns this buffer's ``hitTestRegions``, each shifted by `(dx, dy)`.
    ///
    /// Mirrors `shiftedOverlays(byX:y:)` — combining operations call
    /// this so a region tracks the lines it was emitted with as the
    /// surrounding view tree composes its parent.
    /// This buffer's ``animatedCells``, each shifted by `(dx, dy)`.
    public func shiftedAnimatedCells(byX dx: Int, y dy: Int) -> [AnimatedCellRun] {
        guard !animatedCells.isEmpty else { return [] }
        guard dx != 0 || dy != 0 else { return animatedCells }
        return animatedCells.map { $0.shifted(byX: dx, y: dy) }
    }

    /// This buffer's runs as compositing it at `(dx, dy)` leaves them: shifted,
    /// and each one's ground painted over the fields its row was composited onto.
    ///
    /// Compositing paints an overlay cell that states no field of its own over the
    /// base's field under that cell (`String.paintedOver(fieldsUnder:)`), so that is
    /// what a run's bare cells are drawn over — `ZStack { Color.red; … }` puts a
    /// breathing caret on the red, and a run over two colours on each. The same
    /// painting goes on the ground, column by column, so the run records it
    /// (``AnimatedCellRun/ground``).
    ///
    /// - Parameter fields: The fields each of this buffer's rows was painted over, as
    ///   `insertOverlay` reported them, or `nil` to shift only.
    func shiftedRuns(
        groundedOn fields: [FieldsUnderOverlay]?, byX dx: Int, y dy: Int
    ) -> [AnimatedCellRun] {
        guard let fields else { return shiftedAnimatedCells(byX: dx, y: dy) }
        return animatedCells.map { run in
            let under = fields.indices.contains(run.offsetY) ? fields[run.offsetY] : .none
            // The run's first cell lands at `dx + offsetX` of the base, the columns
            // the fields are kept in.
            return run.paintingGround(over: under, atColumn: dx + run.offsetX).shifted(byX: dx, y: dy)
        }
    }

    /// This buffer's ``opacityRegions``, each shifted by `(dx, dy)`.
    ///
    /// Mirrors ``shiftedAnimatedCells(byX:y:)`` — and for the same reason: a
    /// combining operation that moves the cells must move every claim about
    /// them, or the claim lands on somebody else's content.
    package func shiftedOpacityRegions(byX dx: Int, y dy: Int) -> [OpacityRegion] {
        guard !opacityRegions.isEmpty else { return [] }
        guard dx != 0 || dy != 0 else { return opacityRegions }
        return opacityRegions.map { $0.shifted(byX: dx, y: dy) }
    }

    /// This buffer's ``hitTestRegions``, each moved by `(dx, dy)`.
    ///
    /// The sibling of `shiftedOverlays(byX:y:)` and
    /// ``shiftedAnimatedCells(byX:y:)``, and load-bearing for the same reason:
    /// a region records where a control is *clickable*, in this buffer's
    /// coordinates. Any operation that places these cells somewhere else —
    /// padding, bordering, stacking, windowing — must carry the regions by the
    /// same offset, or the control keeps taking clicks at the position it used
    /// to occupy while drawing somewhere new.
    ///
    /// - Parameters:
    ///   - dx: Cells to move right; negative moves left.
    ///   - dy: Lines to move down; negative moves up.
    /// - Returns: The shifted regions, or the originals when the offset is zero.
    public func shiftedHitTestRegions(byX dx: Int, y dy: Int) -> [HitTestRegion] {
        guard !hitTestRegions.isEmpty else { return [] }
        guard dx != 0 || dy != 0 else { return hitTestRegions }
        return hitTestRegions.map { $0.shifted(byX: dx, y: dy) }
    }
}
