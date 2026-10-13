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
///
/// ## A stated edge outweighs a default one
///
/// As in SwiftUI, an edge of ``init()`` is the DEFAULT, not a number: it gives
/// way to any edge that states a value, which in TUIkit is ``zero``'s. So a
/// view that asks for no space beside it gets none from its neighbour either —
/// two views are apart by the default distance only when both facing edges are
/// the default — and a union with ``zero`` is ``zero`` on the edges merged.
/// Measured on SwiftUI (macOS 15): `ViewSpacing.zero` against `ViewSpacing()`
/// is 0 apart either way round, and `.zero` merged with `ViewSpacing()` is
/// still 0 from it (`Tools/SwiftUIProbes/Stack spacing per pair/distances.out`).
public struct ViewSpacing: Equatable, Sendable {
    // Each edge is a stated distance or ``unstated``, the default. The
    // sentinel is the smallest Int so that a merge is `max` and a stated edge
    // always outweighs a default one; `Int` rather than `Int?` keeps the
    // struct four words with no padding, should a view ever hold one in a
    // value a memo hashes.
    private var top: Int
    private var leading: Int
    private var bottom: Int
    private var trailing: Int

    /// An edge that states nothing: the default.
    private static let unstated = Int.min

    /// A view's default spacing: what the stacks put between two such views —
    /// one column beside it, no row above or below. Every edge gives way to
    /// one that states a value, such as ``zero``'s.
    public init() {
        self.init(top: Self.unstated, leading: Self.unstated, bottom: Self.unstated, trailing: Self.unstated)
    }

    private init(top: Int, leading: Int, bottom: Int, trailing: Int) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    /// No spacing on any edge — what an empty view prefers. Stated, so it
    /// outweighs the default edge it faces or is merged with.
    public static let zero = Self(top: 0, leading: 0, bottom: 0, trailing: 0)

    /// Merges another view's preferences into these, edge by edge: on each of
    /// `edges`, the larger stated value, or the default where neither states
    /// one. A stated edge outweighs a default one, so `.zero` merged in makes
    /// those edges zero.
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

    /// These preferences with `edges` back to the default — what padding
    /// leaves of its content's preference on the edges it pads.
    func defaulting(_ edges: Edge.Set) -> Self {
        var defaulted = self
        if edges.contains(.top) { defaulted.top = Self.unstated }
        if edges.contains(.leading) { defaulted.leading = Self.unstated }
        if edges.contains(.bottom) { defaulted.bottom = Self.unstated }
        if edges.contains(.trailing) { defaulted.trailing = Self.unstated }
        return defaulted
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
    /// next view along `axis`, which has `next`'s, from the edges that face each
    /// other — this view's trailing and the next one's leading, or this one's
    /// bottom and the next one's top: the larger of the two where either states
    /// a value, and the default distance (one column, no row) where both are
    /// the default.
    ///
    /// - Parameters:
    ///   - next: The preferences of the view after this one.
    ///   - axis: The axis the two views follow each other along.
    /// - Returns: The distance both views' facing edges ask for.
    public func distance(to next: Self, along axis: Axis) -> Int {
        let facing =
            switch axis {
            case .horizontal: max(trailing, next.leading)
            case .vertical: max(bottom, next.top)
            }
        guard facing == Self.unstated else { return facing }
        return Self.defaultDistance(along: axis)
    }

    /// The distance between two views that both prefer the default: one
    /// column beside, no row between.
    private static func defaultDistance(along axis: Axis) -> Int {
        switch axis {
        case .horizontal: 1
        case .vertical: 0
        }
    }
}
