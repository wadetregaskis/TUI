//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ViewSpacing.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - View Spacing

/// The spacing a view prefers between itself and the next view, edge by edge.
///
/// A ``Layout`` that places subviews by their preferences reads each one's
/// ``LayoutSubview/spacing`` and asks how far apart two of them should be:
///
/// ```swift
/// let gap = subviews[0].spacing.distance(to: subviews[1].spacing, along: .horizontal)
/// ```
///
/// A layout publishes its own preference, for the container around it, with
/// ``Layout/spacing(subviews:cache:)``.
///
/// ## In cells
///
/// SwiftUI derives a view's preference from its kind and its font. A terminal
/// app has neither a font of its own nor a gap a view's kind could ask for, so
/// every view prefers what TUIkit's stacks have always put between views: **one
/// column** beside it — two words with no cell between them read as one word —
/// and **no row** above or below it, since a line is already separated from the
/// next by being a different line. ``init()`` is that; ``zero`` is no spacing at
/// all.
public struct ViewSpacing: Equatable, Sendable {
    private var top: Int
    private var leading: Int
    private var bottom: Int
    private var trailing: Int

    /// A view's default spacing: one column on the leading and trailing edges,
    /// no rows on the top and bottom.
    public init() {
        self.init(top: 0, leading: 1, bottom: 0, trailing: 1)
    }

    private init(top: Int, leading: Int, bottom: Int, trailing: Int) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    /// No spacing on any edge — what an empty view prefers.
    public static let zero = Self(top: 0, leading: 0, bottom: 0, trailing: 0)

    /// Merges another view's preferences into these, edge by edge: each of
    /// `edges` ends up with the larger of the two.
    ///
    /// - Parameters:
    ///   - other: The preferences to merge in.
    ///   - edges: The edges to merge; the others are left as they are.
    public mutating func formUnion(_ other: Self, edges: Edge.Set = .all) {
        if edges.contains(.top) { top = max(top, other.top) }
        if edges.contains(.leading) { leading = max(leading, other.leading) }
        if edges.contains(.bottom) { bottom = max(bottom, other.bottom) }
        if edges.contains(.trailing) { trailing = max(trailing, other.trailing) }
    }

    /// These preferences merged with another view's, edge by edge — see
    /// ``formUnion(_:edges:)``.
    ///
    /// - Parameters:
    ///   - other: The preferences to merge in.
    ///   - edges: The edges to merge; the others are left as they are.
    /// - Returns: The merged preferences.
    public func union(_ other: Self, edges: Edge.Set = .all) -> Self {
        var merged = self
        merged.formUnion(other, edges: edges)
        return merged
    }

    /// The distance, in cells, a view with these preferences prefers to the
    /// next view along `axis`, which has `next`'s: the larger of the two
    /// preferences for the edges that face each other — this view's trailing
    /// and the next one's leading, or this one's bottom and the next one's top.
    ///
    /// - Parameters:
    ///   - next: The preferences of the view after this one.
    ///   - axis: The axis the two views follow each other along.
    /// - Returns: The smallest distance that satisfies both views.
    public func distance(to next: Self, along axis: Axis) -> Int {
        switch axis {
        case .horizontal: max(trailing, next.leading)
        case .vertical: max(bottom, next.top)
        }
    }
}
