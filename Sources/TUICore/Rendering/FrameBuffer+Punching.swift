//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameBuffer+Punching.swift
//
//  What a composite takes away. An overlay replaces the cells under it, so the
//  claims the buffer beneath still holds over those cells — a pending opacity
//  region, an animated run — have to give up exactly that much and no more.
//  Split from `FrameBuffer.swift`, which had reached the file-length limit.
//
//  Created by Wade Tregaskis
//  License: MIT

extension FrameBuffer {

    /// A stretch of rows over which an overlay's footprint spans the same
    /// columns.
    typealias FootprintBand = (rows: Range<Int>, columns: Range<Int>)

    /// The overlay's per-row visible footprint — the cells its composite
    /// replaces — banded: consecutive rows of equal span collapse into one
    /// entry, so a rectangular overlay is one band.
    ///
    /// Each row's width is the one the overlay knows (`knownWidth(ofRow:line:)`:
    /// its width where its lines are uniform, its `lineWidths` where it has
    /// them), measured only where it knows none.
    func footprintBands(of overlay: Self, at position: (x: Int, y: Int)) -> [FootprintBand] {
        var bands: [FootprintBand] = []
        for (index, line) in overlay.lines.enumerated() {
            // An empty line replaces nothing — the compositors skip it — so it
            // punches nothing either.
            let visible = overlay.knownWidth(ofRow: index, line: line)
            guard visible > 0 else { continue }
            let row = position.y + index
            let columns = position.x..<(position.x + visible)
            if let last = bands.last, last.rows.upperBound == row, last.columns == columns {
                bands[bands.count - 1].rows = last.rows.lowerBound..<(row + 1)
            } else {
                bands.append((row..<(row + 1), columns))
            }
        }
        return bands
    }

    /// This buffer's runs and regions with the overlay's footprint punched out
    /// of them: what a composite leaves of the claims under it.
    ///
    /// The footprint is banded once for both, and only when there is a claim to
    /// punch. Each kind banded it for itself, which on a base carrying both
    /// measured every overlay line twice (CORE1-13).
    func claimsPunched(
        by overlay: Self, at position: (x: Int, y: Int)
    ) -> (animatedCells: [AnimatedCellRun], opacityRegions: [OpacityRegion]) {
        guard !animatedCells.isEmpty || !opacityRegions.isEmpty else { return ([], []) }
        let bands = footprintBands(of: overlay, at: position)
        return (animatedCellsPunched(by: bands), opacityRegionsPunched(by: bands))
    }

    /// This buffer's regions with the overlay's footprint removed — see the
    /// note at the assignment above.
    func opacityRegionsPunched(
        by overlay: Self, at position: (x: Int, y: Int)
    ) -> [OpacityRegion] {
        guard !opacityRegions.isEmpty else { return [] }
        return opacityRegionsPunched(by: footprintBands(of: overlay, at: position))
    }

    /// This buffer's regions with `bands` removed.
    private func opacityRegionsPunched(by bands: [FootprintBand]) -> [OpacityRegion] {
        guard !opacityRegions.isEmpty else { return [] }
        guard !bands.isEmpty else { return opacityRegions }
        var result = opacityRegions
        for band in bands {
            // Only the regions the band reaches are cut, in their places; the
            // rest are kept as they are. Not `flatMap` over `subtracting`,
            // which gives the same regions in the same order but makes an
            // array for every region it leaves whole: a canvas's labels punch
            // its cells' claims once a run, and the claims are hundreds, most
            // of them nowhere near the run (`canvas-labels`).
            func reaches(_ region: OpacityRegion) -> Bool {
                region.offsetY < band.rows.upperBound && band.rows.lowerBound < region.offsetY + region.height
                    && region.offsetX < band.columns.upperBound && band.columns.lowerBound < region.offsetX + region.width
            }
            guard let first = result.firstIndex(where: reaches) else { continue }
            var punched = Array(result[..<first])
            punched.reserveCapacity(result.count + 3)
            for region in result[first...] {
                if reaches(region) {
                    punched += region.subtracting(columns: band.columns, rows: band.rows)
                } else {
                    punched.append(region)
                }
            }
            result = punched
        }
        return result
    }

    /// This buffer's runs with the cells the overlay covers taken out of them —
    /// see the note at the assignment above.
    ///
    /// A partly covered run is **cut**, not dropped. It used to be dropped
    /// whole, on the grounds that half a frozen spinner beats half a spinner
    /// drawn over a menu — true of a spinner, and much too coarse for the case
    /// that turned out to matter: a dialog centred over a page lands in the
    /// MIDDLE of the rows either side of it, so every run on those rows was
    /// partly covered and every one of them went. That is what left the dimmed
    /// page behind a sheet advancing only when something else caused a render.
    /// The remainder either side is a whole picture in its own right, so it is
    /// kept as its own run; a piece with nothing left to animate is dropped,
    /// since a still run only holds the clock open.
    func animatedCellsPunched(
        by overlay: Self, at position: (x: Int, y: Int)
    ) -> [AnimatedCellRun] {
        guard !animatedCells.isEmpty else { return [] }
        return animatedCellsPunched(by: footprintBands(of: overlay, at: position))
    }

    /// This buffer's runs with the cells `bands` cover taken out of them.
    private func animatedCellsPunched(by bands: [FootprintBand]) -> [AnimatedCellRun] {
        guard !animatedCells.isEmpty else { return [] }
        guard !bands.isEmpty else { return animatedCells }
        var kept: [AnimatedCellRun] = []
        kept.reserveCapacity(animatedCells.count)
        for run in animatedCells {
            let span = run.offsetX..<(run.offsetX + run.width)
            let covers = bands.lazy.filter {
                $0.rows.contains(run.offsetY) && $0.columns.overlaps(span)
            }.map(\.columns)
            var remaining = [span]
            for cover in covers {
                remaining = remaining.flatMap { Self.subtracting(cover, from: $0) }
                if remaining.isEmpty { break }
            }
            if remaining == [span] {
                kept.append(run)
                continue
            }
            for piece in remaining {
                guard let clipped = run.clipped(toColumns: piece), clipped.isAnimating else {
                    continue
                }
                kept.append(clipped)
            }
        }
        return kept
    }

    /// `span` with `cover` removed: itself, nothing, or the one or two pieces
    /// left either side.
    static func subtracting(_ cover: Range<Int>, from span: Range<Int>) -> [Range<Int>] {
        guard cover.overlaps(span) else { return [span] }
        var pieces: [Range<Int>] = []
        if span.lowerBound < cover.lowerBound { pieces.append(span.lowerBound..<cover.lowerBound) }
        if cover.upperBound < span.upperBound { pieces.append(cover.upperBound..<span.upperBound) }
        return pieces
    }
}
