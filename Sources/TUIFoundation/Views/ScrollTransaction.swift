//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollTransaction.swift
//
//  The scroll members of `Transaction`: what a change made under one asks of
//  the scroll views it moves.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

// MARK: - Content offset adjustment

/// Whether a scroll view adjusts its own offset to keep its content in place.
/// Matches SwiftUI's type of the same name.
///
/// The adjustments are a declared anchor's: a view following its tail
/// (`.defaultScrollAnchor(.bottom)`) moves down as rows arrive, and a `List`,
/// a `Table` or a lazy stack holding a row (`.anchorPosition(.row(id))`)
/// keeps it on its line. ``disabled``, set on a ``Transaction``, suspends them
/// for the change that transaction carries — the rows a `withTransaction`
/// appends do not move the view, and a held row moves with the rows around
/// it — and the next change without it resumes from where the view then is:
/// the follow from there, the row held on the line the change left it on.
public struct ScrollContentOffsetAdjustmentBehavior: Hashable, Sendable {
    let disablesAdjustment: Bool

    /// Adjusts as the view's anchors say. The default.
    public static var automatic: Self { Self(disablesAdjustment: false) }

    /// Does not adjust.
    public static var disabled: Self { Self(disablesAdjustment: true) }
}

extension Transaction {
    /// Where a scroll view puts the row a `scrollTo` made under this
    /// transaction brings into view. Matches SwiftUI's property of the same
    /// name.
    ///
    /// ```swift
    /// var transaction = Transaction()
    /// transaction.scrollTargetAnchor = .bottom
    /// withTransaction(transaction) { position = items.last?.id }
    /// ```
    ///
    /// For a `.scrollPosition(id:anchor:)` binding it is preferred to the
    /// modifier's anchor, as SwiftUI documents. For a ``ScrollPosition``
    /// request or a ``ScrollViewProxy/scrollTo(_:anchor:)`` that names an anchor
    /// of its own, the call's anchor wins; one that names none takes this.
    public var scrollTargetAnchor: UnitPoint? {
        get { scrollTargetAnchorStorage.map { UnitPoint(x: $0.x, y: $0.y) } }
        set { scrollTargetAnchorStorage = newValue.map { (x: $0.x, y: $0.y) } }
    }

    /// Whether the scroll views a change made under this transaction moves
    /// adjust their own offset for it. Matches SwiftUI's property of the same
    /// name; see ``ScrollContentOffsetAdjustmentBehavior``.
    public var scrollContentOffsetAdjustmentBehavior: ScrollContentOffsetAdjustmentBehavior {
        get { disablesScrollContentOffsetAdjustment ? .disabled : .automatic }
        set { disablesScrollContentOffsetAdjustment = newValue.disablesAdjustment }
    }
}
