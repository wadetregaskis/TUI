//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollWindowHold.swift
//
//  What a scrollable keeps in place when the content above the rows it shows
//  changes and no anchor holds it — `Documentation/Layout and scrolling/Scroll
//  anchoring.md` §1.1's Window mode, and §5 for the hold itself.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - ScrollWindowHold

/// What a scrollable keeps in place when rows are inserted, removed or resized
/// above the ones it shows, and nothing else holds it.
///
/// Nothing else holds it when it is in Window mode — no anchor declared, or
/// released from one by a scroll (a bound ``TUIkit/View/anchorPosition(_:)``
/// reading ``ScrollAnchor/window``) — or when it is away from the edge its
/// declared anchor names: a `.defaultScrollAnchor(.bottom)` view scrolled up
/// from its tail, a `.top` one scrolled down from its top. A view at its top,
/// a view following its tail and a designated row (``ScrollAnchor/row(_:)``)
/// keep their own rules whatever this says.
///
/// | Value | Rows inserted above the top row… |
/// |---|---|
/// | ``topRow`` (the default) | …leave the rows on screen where they are: the offset moves by their lines |
/// | ``offset`` | …push the rows on screen down: the offset stays where it is, in lines |
///
/// ```swift
/// // A chat that loads earlier messages above the ones being read: the
/// // default keeps the reader's place.
/// ScrollView { LazyVStack { ForEach(messages) { MessageRow($0) } } }
///
/// // A view that should show what arrives above it, wherever it is scrolled:
/// List(events) { EventRow($0) }
///     .scrollWindowHold(.offset)
/// ```
///
/// ``topRow`` is SwiftUI's behaviour, measured on macOS 15.8: a `LazyVStack`
/// in a `ScrollView`, scrolled to row 10, keeps row 10 at the top when five
/// rows are inserted above it, and keeps its offset — showing the new rows —
/// when it is at its top (`Tools/SwiftUIProbes/Scroll anchoring/hold.out`).
/// `List`, `Table` and the windowed lazy stacks hold here; an eager `VStack`
/// does not, as SwiftUI's does not — its rows are drawn whole and clipped,
/// with no window to hold — and a held row's line is kept through removals and
/// height changes above it too, where SwiftUI's lazy stack moves on a removal.
/// A change made under `Transaction.scrollContentOffsetAdjustmentBehavior =
/// .disabled` is not held, under either value; nor is a reorder that takes the
/// top row away from the rows either side of it — a sort — which keeps the
/// offset, as SwiftUI's does (`Tools/SwiftUIProbes/Scroll anchoring/reorder.out`).
///
/// TUI-specific: SwiftUI has no setting for this, and
/// `defaultScrollAnchor(_:for: .sizeChanges)` does not change it there
/// (measured: every anchor holds the row alike).
public enum ScrollWindowHold: Hashable, Sendable {
    /// The row at the top of the viewport keeps its line as rows change above
    /// it, and the rows on screen with it. When that row itself goes, the row
    /// that followed it takes its place. The default, as in SwiftUI.
    case topRow

    /// The offset keeps its value in lines: rows inserted above the top row
    /// push the rows on screen down, and rows removed above it pull them up.
    case offset
}

// MARK: - Environment

/// `@usableFromInline`, so internal rather than `private`, with its default: the
/// `@inlinable` accessor reads it (module split step A3).
@usableFromInline
struct ScrollWindowHoldKey: EnvironmentKey {
    @usableFromInline static let defaultValue: ScrollWindowHold = .topRow
}

extension EnvironmentValues {
    /// What the scrollables in this subtree keep in place when the content
    /// above the rows they show changes — see ``ScrollWindowHold``. Defaults to
    /// ``ScrollWindowHold/topRow``.
    ///
    /// `@inlinable`: `ItemListHandler` captures it with its frame inputs, in
    /// the Lists group (module split step A3).
    @inlinable
    public var scrollWindowHold: ScrollWindowHold {
        get { self[ScrollWindowHoldKey.self] }
        set { self[ScrollWindowHoldKey.self] = newValue }
    }
}

extension View {
    /// Sets what the scrollables in this subtree keep in place when rows are
    /// inserted, removed or resized above the ones they show — see
    /// ``ScrollWindowHold``.
    ///
    /// ```swift
    /// List(events) { EventRow($0) }
    ///     .scrollWindowHold(.offset)   // new rows above push the list down
    /// ```
    ///
    /// - Parameter hold: What stays in place.
    /// - Returns: A view whose scrollables keep `hold` in place.
    public func scrollWindowHold(_ hold: ScrollWindowHold) -> some View {
        environment(\.scrollWindowHold, hold)
    }
}
