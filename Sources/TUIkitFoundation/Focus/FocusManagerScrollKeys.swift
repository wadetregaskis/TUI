//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusManagerScrollKeys.swift
//
//  Page Up, Page Down, Home and End that the focused control did not take:
//  the active section's one scroll container moves by them.
//
//  Created by Wade Tregaskis
//  License: MIT

extension FocusManager {
    /// Scrolls the active section's enclosing scroll container for a
    /// page/home/end key the focused element didn't consume.
    ///
    /// Scrolls the viewport directly through ``ScrollableOffsetState`` (so it
    /// never disturbs a list's selection — it is a viewport move, not a focus
    /// move), and only when the active section has exactly one scroller that can
    /// currently move. That one-scroller guard keeps it unambiguous (the common
    /// "a single ScrollView/List wraps the page" case) and avoids scrolling the
    /// wrong container when several are on screen.
    ///
    /// - Returns: `true` if a scroll container was moved.
    ///
    /// Not private: a Home/End that runs out of laid-out rows sends the
    /// container to the same end, from `FocusManagerSubtreeJump.swift`.
    func scrollActiveSection(for key: Key) -> Bool {
        guard let section = activeSection else { return false }
        let focusedID = currentFocused?.focusID
        let scrollers = section.focusables.compactMap { focusable -> (any ScrollableOffsetState)? in
            guard focusable.focusID != focusedID,
                let scroller = focusable as? any ScrollableOffsetState,
                // A gesture, so `.scrollDisabled` applies — the scroller's own
                // key handler already declines these keys under it, and this
                // fallback must not scroll it from the outside instead.
                scroller.isScrollEnabled,
                scroller.maxOffset > 0
            else { return nil }
            return scroller
        }
        guard scrollers.count == 1, let scroller = scrollers.first else { return false }

        // These are USER scrolls, so they go through the user entry points —
        // raw `scroll(by:)`/`scrollOffset` writes bypassed the shadow anchor
        // and the sub-row clip: a bound anchor stayed engaged (snapping the
        // viewport straight back on the next frame, so PageDown appeared
        // dead), Home left a wheel's partial top clip in place, and End
        // neither engaged bottom-follow nor set a ScrollView's tail seek —
        // all of which the scroller's OWN key handler gets right.
        // The one definition of a page, in the scroller's own stepping unit.
        let page = scroller.pageDistance
        // The offset before, so the caller can be told whether anything
        // actually moved. "A scroller exists" is not movement, and a jump that
        // resumes itself while the container is still travelling needs to know
        // the difference — see `moveFocus(inSubtreeAt:jump:)`.
        let before = scroller.scrollOffset
        switch key {
        // A page moves the PICTURE by a page — `pageDelta(_:)` re-bases it on
        // the offset the rows were drawn from, which near the top edge is not
        // always `scrollOffset`. Home/End below name absolute positions and so
        // need no re-basing; a single step must never be re-based at all (see
        // `ScrollableOffsetState.pageDelta(_:)`).
        case .pageUp: scroller.userScrollFine(by: scroller.pageDelta(-page))
        case .pageDown: scroller.userScrollFine(by: scroller.pageDelta(page))
        case .home: scroller.userScrollToTop()
        case .end: scroller.userScrollToBottom()
        default: return false
        }
        return scroller.scrollOffset != before
    }
}
