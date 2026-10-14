//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ItemListHandler+ScrollTo.swift
//
//  `ScrollViewProxy.scrollTo(_:anchor:)` reaching a `List` or a `Table`: the
//  handler is a ``ScrollToTarget``, and places the row the request names.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

extension ItemListHandler: ScrollToTarget {}

extension ItemListHandler {
    /// Scrolls so the row at `index` sits where `anchor` says — the row's own
    /// point at the anchor's `y` lined up with the viewport's, `.top` on the
    /// first line, `.bottom` on the last, `.center` between — or, with no
    /// anchor, by the least that shows it all, and not at all where it is
    /// already shown: ``ScrollViewProxy/scrollTo(_:anchor:)``'s rule, as a
    /// `ScrollView` applies it. The focus and the selection do not move.
    package func scroll(toRow index: Int, anchor: UnitPoint?) {
        guard index >= 0, index < itemCount else { return }
        clearOverscroll()
        let rowHeight = self.rowHeight ?? { _ in 1 }
        let height = max(1, rowHeight(index))
        let slack = max(0, rowLineBudget - height)
        let linesAbove: Int
        if let anchor {
            linesAbove = Int((Double(slack) * min(1, max(0, anchor.y))).rounded(.down))
        } else if index < scrollOffset || (index == scrollOffset && scrollTopClipLines > 0) {
            linesAbove = 0
        } else if linesFromTop(to: index, rowHeight: rowHeight, within: slack) <= slack {
            return
        } else {
            linesAbove = slack
        }
        place(row: index, linesAbove: linesAbove, rowHeight: rowHeight)
        clampScrollOffset()
        clampTopClip()
    }

    /// The content lines from the viewport's top line to the first line of the
    /// row at `index`, a row below the top one — counted no further than past
    /// `limit`, so a far row costs a viewport's walk, not the list's.
    private func linesFromTop(to index: Int, rowHeight: (Int) -> Int, within limit: Int) -> Int {
        var lines = -scrollTopClipLines
        var row = scrollOffset
        while row < index, lines <= limit {
            lines += max(1, rowHeight(row))
            row += 1
        }
        return lines
    }
}
