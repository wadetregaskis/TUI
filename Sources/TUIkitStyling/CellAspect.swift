//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CellAspect.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Cell aspect

/// The cell aspects (height ÷ width) the image arithmetic will compute with:
/// cells between a tenth as tall as they are wide and ten times as tall.
///
/// No terminal is near either end — measured cells sit between 1 and 4
/// (`Terminal` clamps its own measurement to that) — so the range costs a
/// real caller nothing. What it buys is that the arithmetic downstream
/// is bounded: an aspect of `1e300` is finite, passes a `> 0` test, and
/// still produces a width no `Int` can hold.
///
/// Here, in the lowest module both readers depend on, and not on
/// `ASCIIConverter`, so that TUIkit's environment value can apply the rule
/// without importing the image converter. `ASCIIConverter.cellAspectRange`
/// is this constant, re-published.
package let cellAspectRange: ClosedRange<Double> = 0.1...10

/// `ratio`, if it is a cell aspect the arithmetic can use; otherwise the
/// default of `2.0`, or the nearer end of ``cellAspectRange``.
///
/// ONE implementation of the rule, shared by `ASCIIConverter.targetSize`'s own
/// `cellAspect` argument (through `ASCIIConverter.sanitizedCellAspect`, which
/// forwards here) and by the `imageCellAspect` environment value that feeds
/// it, so the two cannot drift. A second copy of it is how
/// `.imageCellAspect(_:)` once came to admit `.infinity`. NaN, infinities and
/// non-positive values have no meaning as a ratio and fall back to the default
/// rather than to a bound.
///
/// Pure arithmetic: this module must keep building on Windows.
package func sanitizedCellAspect(_ ratio: Double) -> Double {
    guard ratio.isFinite, ratio > 0 else { return 2.0 }
    return min(max(ratio, cellAspectRange.lowerBound), cellAspectRange.upperBound)
}
