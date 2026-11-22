//  🖥️ TUI — A Terminal UI framework for Swift
//  SaturatingLines.swift
//
//  Line arithmetic that cannot trap, for the windowed stacks' estimates: a
//  row count times a pitch is a count of lines, and a row count is whatever
//  the data says — `ForEach(0..<Int.max)` is SwiftUI's endless-list idiom.
//
//  Created by Wade Tregaskis
//  License: MIT

/// The most lines a windowed stack's estimate of rows it never measured
/// counts: a quarter of `Int`'s range. A position at the very end of an
/// estimate held at `Int.max` still adds a viewport, a band of rows and a
/// footer to it in the walk's plain arithmetic, which then trapped.
let estimatedLinesCeiling = Int.max / 4

extension Int {
    /// This many estimated lines, held within ±``estimatedLinesCeiling``.
    var clampedToEstimatedLines: Int { Swift.min(Swift.max(self, -estimatedLinesCeiling), estimatedLinesCeiling) }

    /// `rows` rows of `pitch` lines, in lines, held within
    /// ±``estimatedLinesCeiling``: what every estimate of rows not measured
    /// prices them at.
    static func lines(ofRows rows: Int, pitch: Int) -> Int {
        rows.saturatingMultiplied(by: pitch).clampedToEstimatedLines
    }

    /// `self × other`, held at `Int.max` or `Int.min` where it would pass
    /// either: the lines of more rows than `Int` can count are as many as it
    /// can. NOT `&*`, which wraps a total of `Int.max` two-line rows to -2.
    func saturatingMultiplied(by other: Int) -> Int {
        let (product, overflowed) = multipliedReportingOverflow(by: other)
        guard overflowed else { return product }
        return (self < 0) == (other < 0) ? .max : .min
    }

    /// `self + other`, held at the bound it would pass.
    func saturatingAdding(_ other: Int) -> Int {
        let (sum, overflowed) = addingReportingOverflow(other)
        guard overflowed else { return sum }
        return other < 0 ? .min : .max
    }

    /// `self - other`, held at the bound it would pass.
    func saturatingSubtracting(_ other: Int) -> Int {
        let (difference, overflowed) = subtractingReportingOverflow(other)
        guard overflowed else { return difference }
        return other < 0 ? .max : .min
    }
}
