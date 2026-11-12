//  🖥️ TUI — A Terminal UI framework for Swift
//  ItemListHandler+HorizontalScroll.swift
//
//  A table whose columns do not fit scrolls sideways, a column at a time: the
//  keys and the wheel that move it, and what the table hands over each frame
//  for them to move it by.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - What the table publishes

/// Where a `Table` whose columns' minimum widths do not fit is scrolled
/// sideways (decisions TABLE-HSCROLL).
///
/// It scrolls by whole columns: the first column drawn is always drawn from
/// its first cell, and the window starts at one of ``stops``. ``axis`` holds
/// the same position in cells, for the horizontal scrollbar, whose arrows,
/// track and thumb move it in cells; the table snaps what they ask for to a
/// stop when it next draws (`_TableCore.horizontalWindow`).
package struct TableHorizontalScroll {
    /// The position in cells, from the first column's first cell: what the
    /// horizontal scrollbar draws and drives.
    package let axis = ScrollAxis()

    /// Where each column the window may start at begins, in cells from the
    /// first column's first cell, in order — `[0]` and on to the last start
    /// that still fills the window. Empty while every column fits, which is
    /// what tells the keys and the wheel there is nothing to scroll.
    package var stops: [Int] = []

    /// The stop the window is at: the one the last frame was drawn from, or
    /// one a key or the wheel has moved it to since, in the same batch of
    /// input.
    package var drawnStart = 0

    /// The stop the last frame was drawn from, which input does not move:
    /// where the header's columns, as the frame published them
    /// (`ItemListHandler.headerColumns`), were measured from. A header drag
    /// later in the batch lays them out again from where the window is now.
    package var framedStart = 0

    /// The column, by key, a keyboard sort just made primary: the next frame
    /// scrolls its header into sight, and forgets it.
    package var pendingReveal: String?

    package init() {}

    /// Whether there is anything to scroll.
    package var scrolls: Bool { stops.count > 1 }

    /// The stop `delta` columns along from the one drawn, or `nil` at that edge.
    package func stop(steppingBy delta: Int) -> Int? {
        let current = stops.lastIndex { $0 <= drawnStart } ?? 0
        let next = max(0, min(stops.count - 1, current + delta))
        return next == current ? nil : stops[next]
    }
}

// MARK: - Keys and wheel

extension ItemListHandler {
    /// Scrolls a table that does not fit one column left or right, for Left
    /// or Right: `false` at the edge, or where nothing scrolls, so the key
    /// goes on as it did before the table could scroll.
    func stepColumnsSideways(_ event: KeyEvent) -> Bool {
        stepColumns(by: event.key == .left ? -1 : 1)
    }

    /// Moves the window `delta` columns, when it can go that way.
    @discardableResult
    func stepColumns(by delta: Int) -> Bool {
        guard var scroll = horizontalScroll, scroll.scrolls, let stop = scroll.stop(steppingBy: delta) else {
            return false
        }
        scroll.axis.scrollOffset = stop
        // Published at once, so a second key in the same batch steps on from
        // here rather than from the frame drawn before both.
        scroll.drawnStart = stop
        horizontalScroll = scroll
        return true
    }

    /// The wheel's sideways ticks — a horizontal wheel's, or the vertical
    /// wheel's with Shift held, as a `ScrollView` takes them — a column a
    /// tick: whether one moved the columns, `false` at an edge so the wheel
    /// goes on to whatever is around the table, as a `ScrollView`'s does; and
    /// `nil` for a tick that is not sideways, or a table that does not scroll
    /// sideways, which the rows' wheel takes. A Shift tick at an edge is not
    /// the rows': it never scrolls them.
    package func handleHorizontalWheel(_ event: MouseEvent) -> Bool? {
        guard horizontalScroll?.scrolls == true else { return nil }
        switch event.button {
        case .scrollLeft: return stepColumns(by: -1)
        case .scrollRight: return stepColumns(by: 1)
        case .scrollUp where event.shift: return stepColumns(by: -1)
        case .scrollDown where event.shift: return stepColumns(by: 1)
        default: return nil
        }
    }
}
