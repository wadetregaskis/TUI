//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollExtentEstimator.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - ScrollExtentProfile

/// What a previous ``ScrollExtentEstimator/lineMetrics(visible:count:topClip:precision:cached:height:)``
/// worked out about a set of rows' heights, for a caller whose key still holds.
///
/// One type for both modes, because both are the same bargain in different
/// shapes: asking a row its height costs a wrap per column for a `Table` and a
/// row materialisation for a `List`, the answer does not change while the
/// layout that produced it does not, and the caller is the only thing that
/// knows when that is. Data edited under an unchanged signature goes stale,
/// which is the documented trade for the mean and holds identically for the
/// sums — both ends of the thumb's travel are pinned by construction
/// (``ScrollExtentPrecision``), so only the middle can drift.
enum ScrollExtentProfile: Sendable, Equatable {
    /// The mean height of the sample, under ``ScrollExtentPrecision/approximate``.
    case mean(Double)

    /// `sums[i]` is the total height of rows `0..<i`, so `sums` has one more
    /// entry than there are rows. Under ``ScrollExtentPrecision/exact`` or
    /// below ``ScrollExtentPrecision/exactRowLimit``.
    ///
    /// One `Int` per row is the cost of not re-wrapping every row every frame —
    /// 2 KB for the 250-row table that motivated it, and proportionally more
    /// for a large table someone put into `.exact`, which is a mode whose whole
    /// premise is already that exactness is worth paying for.
    case prefixSums([Int])
}

// MARK: - Shared estimator

/// The line-metered scrollbar arithmetic shared by ``List`` and ``Table``,
/// which meter their bars in *lines* whenever a row can span more than one.
///
/// Both views arrive here with the same three facts — the range of rows on
/// screen, a way to ask any row's height, and how many of the top row's lines
/// are clipped above the fold — and want the same two numbers back. Keeping the
/// arithmetic in one place is what stops the twins drifting apart yet again;
/// see the divergence history in `List`/`Table`'s scroll rules.
enum ScrollExtentEstimator {

    /// The scrollbar's `extent` (total content lines) and `offset` (lines above
    /// the viewport) for a run of variable-height rows.
    ///
    /// The two are computed together, from the same numbers, so they cannot
    /// disagree:
    ///
    ///     extent = linesAbove + linesVisible + linesBelow
    ///     offset = linesAbove + topClip
    ///
    /// which pins both ends of the travel regardless of how wrong the estimate
    /// is. At the top `linesAbove` is 0, so the thumb starts at the top of the
    /// track. At the furthest scroll `linesBelow` is 0 and the visible rows fill
    /// the viewport, so `offset + viewport == extent` and the thumb ends flush
    /// at the bottom. An estimate that only bends the middle of the travel is
    /// invisible; one that misses the ends looks broken.
    ///
    /// - Parameters:
    ///   - visible: the range of rows currently on screen.
    ///   - count: the total number of rows.
    ///   - topClip: lines of the first visible row hidden above the fold.
    ///   - precision: whether off-screen rows are sampled or measured.
    ///   - height: the height in lines of the row at an index. Called once per
    ///     visible row always, and for every other row only under
    ///     ``ScrollExtentPrecision/exact`` (or below its row limit).
    /// - Parameters:
    ///   - cachedMean: a mean this estimator previously RETURNED for the same
    ///     inputs, when the caller still holds one. The sample is the same 64
    ///     indices every frame for a given row count (see
    ///     ``ScrollExtentPrecision/sampleCount``), yet deriving it costs a
    ///     height — for a Table, a cell-string build and a fit per column; for
    ///     a List, MATERIALISING the row — per sampled off-screen row, per
    ///     frame. The caller keys its stash on whatever shapes the heights
    ///     (row count, column widths and limits, available width, precision)
    ///     and hands the mean back while the key holds, so steady-state frames
    ///     sample nothing. Data edits under an unchanged key can go stale —
    ///     accepted, because the mean only bends the MIDDLE of the thumb's
    ///     travel (both ends are pinned by construction, the property the type
    ///     doc calls out) and the estimate was already approximate.
    static func lineMetrics(
        visible: Range<Int>,
        count: Int,
        topClip: Int,
        precision: ScrollExtentPrecision,
        cached: ScrollExtentProfile? = nil,
        height: (Int) -> Int
    ) -> (extent: Int, offset: Int, profile: ScrollExtentProfile?) {
        guard count > 0 else { return (extent: 0, offset: 0, profile: nil) }
        let clamped = visible.clamped(to: 0..<count)
        var linesVisible = 0
        for index in clamped { linesVisible += height(index) }

        let linesAbove: Int
        let linesBelow: Int
        var profileUsed: ScrollExtentProfile?
        if precision == .exact {
            // Asked for, so measured — every row, every frame. `.exact` says in
            // its own documentation that it costs O(rows) per frame and is for
            // callers who want a thumb proportionally exact to the line, so a
            // cache here would quietly sell them the approximation they
            // declined. The cheap case below is the one worth keeping.
            var above = 0
            for index in 0..<clamped.lowerBound { above += height(index) }
            var below = 0
            for index in clamped.upperBound..<count { below += height(index) }
            (linesAbove, linesBelow) = (above, below)
        } else if count <= ScrollExtentPrecision.exactRowLimit {
            // Exact because it is CHEAP, not because anyone asked — and it was
            // not cheap. This was the one path with no stash of its own, which
            // made the small case the expensive one: a table above the row limit
            // samples 64 rows and keeps the answer, while one below it wrapped
            // every row on every frame and kept nothing. A wrapped table of 250
            // rows spent 45% of its frame here to draw twelve rows.
            //
            // The heights are kept as a PREFIX SUM rather than a total, because
            // the thumb needs the split as well as the sum: `linesAbove` is the
            // sum before the window and `linesBelow` the sum after it, and both
            // move every time the window does while the heights themselves do
            // not. One `Int` per row, under the signature the mean already uses.
            let sums: [Int]
            if case .prefixSums(let cachedSums) = cached, cachedSums.count == count + 1 {
                sums = cachedSums
            } else {
                var built = [Int](repeating: 0, count: count + 1)
                for index in 0..<count { built[index + 1] = built[index] + height(index) }
                sums = built
            }
            profileUsed = .prefixSums(sums)
            // The VISIBLE rows are measured live above and not taken from the
            // sums: those rows are laid out this frame anyway, so reading them
            // from a stash could only make the one part of the estimate that is
            // exact approximate.
            (linesAbove, linesBelow) = (sums[clamped.lowerBound], sums[count] - sums[clamped.upperBound])
        } else {
            // One mean, applied to both sides, so the two ends of the estimate
            // are drawn from the same sample and stay mutually consistent.
            let cachedMean: Double? = if case .mean(let value) = cached { value } else { nil }
            let mean = cachedMean ?? meanRowHeight(count: count, height: height)
            profileUsed = .mean(mean)
            linesAbove = Int((Double(clamped.lowerBound) * mean).rounded())
            linesBelow = Int((Double(count - clamped.upperBound) * mean).rounded())
        }

        return (
            extent: linesAbove + linesVisible + linesBelow,
            offset: linesAbove + topClip,
            profile: profileUsed
        )
    }

    /// The mean height of ``ScrollExtentPrecision/sampleCount`` rows spread
    /// evenly across the collection.
    ///
    /// Kept fractional: rounding a 2.4-line mean down to 2 understates a
    /// 10,000-row extent by 17%, which is a visibly wrong thumb size. The
    /// rounding happens once, on the product.
    private static func meanRowHeight(count: Int, height: (Int) -> Int) -> Double {
        let samples = min(count, ScrollExtentPrecision.sampleCount)
        guard samples > 0 else { return 1 }
        var total = 0
        for step in 0..<samples { total += height((step * count) / samples) }
        return Double(total) / Double(samples)
    }
}
