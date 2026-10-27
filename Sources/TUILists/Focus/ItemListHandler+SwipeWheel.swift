//  🖥️ TUI — A Terminal UI framework for Swift
//  ItemListHandler+SwipeWheel.swift
//
//  A row's swipe actions revealed by the horizontal wheel: what a trackpad's
//  sideways swipe sends where a terminal reports it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension ItemListHandler {
    /// How far apart two wheel ticks may come and still be one swipe: a
    /// trackpad's swipe arrives as a burst of ticks a few milliseconds apart,
    /// and a pause longer than this starts another (estimated, owner question
    /// A48: "roughly 150–300 ms, unmeasured").
    static var swipeBurstGapNanos: UInt64 { 250_000_000 }

    /// Takes a horizontal wheel tick over list row `row` at `now` as part of a
    /// swipe, and answers whether it did. A burst of ticks is one gesture:
    /// the first tick of a burst toward an edge with actions reveals them (the
    /// ticks moving the content right, `.scrollLeft`, reveal the leading edge,
    /// as a swipe to the right does); a second burst the same way is the full
    /// swipe, where allowed, and a burst the other way slides them away.
    ///
    /// Ticks only where there is something to reveal or to slide away, so a
    /// list whose rows have no actions leaves the wheel to whatever is around
    /// it; and none while a vertical scroll is under way, which a trackpad
    /// leaks sideways ticks into (the axis it started on holds for the burst).
    /// A vertical tick, which this never takes, is noted for that.
    @MainActor
    package func handleSwipeWheel(_ event: MouseEvent, row: Int?, now: UInt64) -> Bool {
        let edge: HorizontalEdge
        switch event.button {
        case .scrollUp, .scrollDown:
            swipeWheel.lastVerticalTick = now
            return false
        case .scrollLeft: edge = .leading
        case .scrollRight: edge = .trailing
        default: return false
        }
        if let vertical = swipeWheel.lastVerticalTick, now &- vertical < Self.swipeBurstGapNanos { return false }
        if let burst = swipeWheel.burst, burst.edge == edge, now &- burst.lastTick < Self.swipeBurstGapNanos {
            swipeWheel.burst = (edge, now)
            return true
        }
        if let revealed = revealedSwipe {
            swipeWheel.burst = (edge, now)
            if revealed.edge == edge, swipeEdges[revealed.row]?[edge] == true { swipeFullSwipe?() }
            revealedSwipe = nil
            return true
        }
        guard let row, swipeEdges[row]?[edge] != nil else { return false }
        swipeWheel.burst = (edge, now)
        focusedIndex = row
        revealedSwipe = (row, edge)
        focusLeavesForRowMenu = true
        return true
    }
}

/// Where the horizontal wheel's swipe is: the burst in progress, and the last
/// vertical tick, which locks a burst to the axis it started on.
package struct SwipeWheelState {
    /// The edge the burst in progress is toward, and its last tick.
    package var burst: (edge: HorizontalEdge, lastTick: UInt64)?
    /// When the last vertical wheel tick came.
    package var lastVerticalTick: UInt64?

    package init() {}
}
