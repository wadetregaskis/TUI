//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollExtentPrecision.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - ScrollExtentPrecision

/// How precisely a scrollable measures the rows it is *not* showing.
///
/// A ``List`` or ``Table`` whose rows span multiple lines only knows a row's
/// height by wrapping its text into the column widths. The rows on screen have
/// to be wrapped anyway — they are about to be drawn — but the ones above and
/// below the viewport are needed for exactly one thing: the scroll indicator.
/// Either the scrollbar's thumb (where it sits in the track and how large it
/// is) or the count in "▲ N more above". Wrapping thousands of off-screen rows
/// every frame to place a thumb a cell or two more accurately is a poor trade,
/// so by default the off-screen rows are sampled rather than measured.
///
/// - ``approximate``: the visible rows are exact; the rest are estimated from a
///   fixed, evenly-spaced sample. O(1) in the row count. The default.
/// - ``exact``: every row is measured. O(rows) per frame, and every row's text
///   is wrapped. Opt into it when a thumb that is proportionally exact to the
///   line matters more than the cost.
///
/// Both ends are pinned in either mode: scrolled fully to the top the thumb is
/// at the top of its track, and at the furthest scroll it is at the bottom.
/// Only the middle of the travel can drift, and only when rows differ wildly in
/// height.
///
/// Below ``exactRowLimit`` rows every row is measured rather than sampled — a
/// table small enough to measure outright is simply measured — but the answer is
/// then KEPT while the layout that produced it holds, so editing the rows'
/// content without changing their number or their columns leaves the middle of
/// the travel as approximate as ``approximate`` would. That is the trade
/// ``approximate`` already makes, taken on a path where exactness was never
/// asked for; ``exact`` itself is never cached, and re-measures every row every
/// frame as its own documentation says.
///
/// Single-line rows are unaffected: there the line count *is* the row count, so
/// the extent is already exact at no cost.
///
/// ```swift
/// Table(logEntries) { ... }
///     .scrollExtentPrecision(.exact)
/// ```
public enum ScrollExtentPrecision: Sendable, Hashable, CaseIterable {
    /// Measure the visible rows; estimate the rest from a sample. The default.
    case approximate

    /// Measure every row, on screen or not.
    case exact

    /// At or below this many rows both modes measure everything: the sampling
    /// only pays for itself once the walk it replaces is long, and a small
    /// table that reports an approximate extent would be all cost and no
    /// benefit. Matches the exact-walk rung of the lazy stacks' measure ladder.
    public static let exactRowLimit = 256

    /// How many rows ``approximate`` measures to derive its mean row height.
    ///
    /// Deliberately a fixed count rather than a fraction: the estimate must not
    /// change as the view scrolls, or the thumb would resize under the pointer.
    /// The sample is taken at evenly spaced indices over the whole collection,
    /// so it is the same sample every frame for a given row count.
    public static let sampleCount = 64
}

// MARK: - Environment

/// `@usableFromInline`, so internal rather than `private`, with its default: the
/// `@inlinable` accessor reads it (module split step A3).
@usableFromInline
struct ScrollExtentPrecisionKey: EnvironmentKey {
    @usableFromInline static let defaultValue: ScrollExtentPrecision = .approximate
}

extension EnvironmentValues {
    /// How precisely scrollables in this subtree measure their off-screen rows
    /// — see ``ScrollExtentPrecision``. Defaults to
    /// ``ScrollExtentPrecision/approximate``.
    @inlinable
    public var scrollExtentPrecision: ScrollExtentPrecision {
        get { self[ScrollExtentPrecisionKey.self] }
        set { self[ScrollExtentPrecisionKey.self] = newValue }
    }
}

// MARK: - View Modifier

extension View {
    /// Sets how precisely ``List`` and ``Table`` content in this subtree
    /// measures the rows outside its viewport.
    ///
    /// The off-screen rows feed only the scroll indicators, so they are
    /// ``ScrollExtentPrecision/approximate`` by default. Pass
    /// ``ScrollExtentPrecision/exact`` where a proportionally exact scrollbar
    /// thumb is worth wrapping every row's text on every frame.
    public func scrollExtentPrecision(_ precision: ScrollExtentPrecision) -> some View {
        environment(\.scrollExtentPrecision, precision)
    }
}
