//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollExtentPrecision.swift
//
//  Created by Wade Tregaskis
//  License: MIT

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
