//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollContentAnchor.swift
//
//  The scroll position as a place in the content — a row, and how many of
//  its lines are hidden above the viewport — rather than as a number of
//  lines from the content's top ("Locating things without drawing them" §3,
//  SCROLL-FIT design B-SCROLLFIT-11).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// Where a scroll view's viewport stands in its content: the row at its top
/// (or a designated row held below it) and how many of that row's lines are
/// above the viewport's top — with the dead reckoning that keeps the scroll
/// view's offset in lines in step with it.
///
/// The scroll view holds it (``ScrollViewHandler/contentAnchor``): the anchor
/// is the scroll view's position, as SCROLL-FIT's pull needs it to be, and the
/// absolute offset it keeps is the reading the anchor is walked to and derived
/// against. The column that draws the rows writes it — a windowed lazy stack
/// at the content's origin, on its anchored walk (`StackAnchoredWindow.swift`)
/// — being the only one that can measure a row.
///
/// A class, not a value: the scroll view hands it down to its content in the
/// request (``ScrollContentWindow/anchor``), and the column writes it in place,
/// as it answers in ``ScrollContentReply``.
final class ScrollContentAnchor {
    /// The column whose row the anchor names — the head of the route to it
    /// (`ViewIdentity`; the row is the column's child at ``ordinal``, keyed
    /// ``key``) — or `nil` before any column has claimed it.
    private(set) var column: ViewIdentity?

    /// The window state of the column that claimed it. Weak, and compared by
    /// identity: a column whose state was let go and made afresh — not drawn
    /// for a frame, so its `StateStorage` box was pruned — finds its anchor
    /// gone, as it found it when the anchor lived in that box.
    private weak var holder: StackWindowState?

    /// The row the viewport is anchored on, by its ordinal among the column's
    /// rows.
    var ordinal = 0

    /// The anchored row's stable `ForEach` key (§5f): the anchor names a ROW,
    /// not a position. Data edits shift ordinals; each frame the ordinal is
    /// re-bound to this key before scroll input applies, so an insertion above
    /// the anchor moves nothing on screen (§6d) and a deleted anchor falls to
    /// its nearest surviving neighbour.
    var key: String?

    /// How many lines of the anchored row sit above the viewport's top:
    /// signed, negative for a designated row held that many lines BELOW it
    /// (`.anchorPosition(.row(id))`), and for a viewport whose top shows
    /// lines drawn above the column (a section's header).
    var within = 0

    /// The absolute offset the anchor was last derived against. Scroll input
    /// arrives as a new absolute offset; the DIFFERENCE is walked in row space
    /// (one line up looks at one row, §3), so estimates never move what's on
    /// screen — only the scrollbar.
    var derivedOffset = 0

    /// The content height the anchored walk last reported
    /// (``ScrollContentReply/sliceTotalHeight``) — the total the scroll view's
    /// offset is clamped against, and so the one an offset at the very bottom
    /// is measured from. `nil` before the first anchored frame.
    var reportedTotal: Int?

    init() {}

    /// This anchor, for the column at `column` whose window state is `state`
    /// to read and move: as it left it, or — for a column that did not leave
    /// it — afresh, as a new column's own anchor started (row 0, nothing
    /// hidden, nothing derived or reported).
    ///
    /// Afresh for another column, so a scroll view whose content changes from
    /// one lazy stack to another does not hand the second the first one's row;
    /// and afresh for the same column drawn anew, so the scroll view's holding
    /// it changes nothing the stack's holding it did (SCROLL-FIT P1 moved it
    /// here with no output changed).
    func claimed(byColumn column: ViewIdentity, state: StackWindowState) -> ScrollContentAnchor {
        if holder !== state || self.column != column {
            ordinal = 0
            key = nil
            within = 0
            derivedOffset = 0
            reportedTotal = nil
            holder = state
            self.column = column
        }
        return self
    }
}
