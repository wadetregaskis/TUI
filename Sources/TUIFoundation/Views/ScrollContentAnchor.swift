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
/// Written by the column that draws the rows — a windowed lazy stack, on its
/// anchored walk (`StackAnchoredWindow.swift`) — which is the only one that can
/// measure a row; the absolute offset the scroll view keeps is the reading the
/// anchor is walked to and derived against.
///
/// A class, not a value: the scroll view hands it down to its content in the
/// request (``ScrollContentWindow/anchor``), and the column writes it in place,
/// as it answers in ``ScrollContentReply``.
final class ScrollContentAnchor {
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
}
