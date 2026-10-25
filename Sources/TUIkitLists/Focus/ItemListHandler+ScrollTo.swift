//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ItemListHandler+ScrollTo.swift
//
//  `ScrollViewProxy.scrollTo(_:anchor:)` reaching a `List` or a `Table`: the
//  handler is a ``ScrollToTarget``, and places the row the request names. And
//  a `.scrollPosition` bound above one: the row, edge or line it asks for is
//  placed the same way, and the row at its anchor is written back.
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

// MARK: - A bound scroll position

extension ItemListHandler {
    /// Records that the user scrolled the list (``ScrollableOffsetState``),
    /// for a bound `.scrollPosition` to hear at the next render and for
    /// `onScrollPhaseChange`, which reports it `.interacting`. It stops a
    /// programmatic glide where it stands, as a `ScrollView`'s does.
    package func noteUserScroll() {
        userScrolledSinceRender = true
        glide = nil
        phase = .interacting
        lastUserScrollNanos = phaseNow()
    }

    /// Places what a `.scrollPosition` bound above the list asks for on this
    /// frame, once, as a `ScrollView` does: a row, by the key `rowIndex`
    /// finds it under (``scroll(toRow:anchor:)``, so every anchor and the
    /// least move), the top or bottom edge as the first or last row, or a
    /// line of the content. A list does not scroll across, so the leading
    /// and trailing edges and an `x` move nothing. Before the offset settles.
    /// Made inside an animation, each glides there
    /// (``placeProgrammatically(landing:context:_:)``).
    @MainActor
    package func applyScrollPosition(rowIndex: (String) -> Int?, context: RenderContext) {
        guard !context.isMeasuring, let position = context.environment.scrollPositionBinding else { return }
        if let request = position.rowRequest(
            tracking: &positionTracking, transactionAnchor: context.environment.transaction.scrollTargetAnchor)
        {
            if let index = rowIndex(request.key) {
                placeProgrammatically(landing: .listSeek(request, row: index), context: context) {
                    scroll(toRow: index, anchor: request.anchor)
                }
            }
            return
        }
        switch position.placementRequest(tracking: &positionTracking) {
        case .edge(.top):
            placeProgrammatically(landing: .top, context: context) { scroll(toRow: 0, anchor: .top) }
        case .edge(.bottom):
            placeProgrammatically(landing: .bottom, context: context) { scroll(toRow: itemCount - 1, anchor: .bottom) }
        case .offset(_, let y?):
            placeProgrammatically(landing: .offset(y), context: context) { scroll(toLine: y) }
        default: break
        }
    }

    /// Writes the row at a bound `.scrollPosition`'s anchor back to it —
    /// named by `rowID`, nothing for a row it names nothing — and tells it
    /// the user scrolled, when they did, as a `ScrollView` does. After the
    /// offset settles.
    ///
    /// The frame's scroll is settled here, so this is also where a glide in
    /// flight asks for its next frame and the phase is reported
    /// (``finishScrollFrame(context:)``). Mid-glide the row is not written:
    /// a bound position is told the row the glide lands on, not each it
    /// passes, or each glide frame would draw the app's body again.
    @MainActor
    package func reportScrollPosition(rowID: (Int) -> AnyHashable?, context: RenderContext) {
        guard !context.isMeasuring else { return }
        finishScrollFrame(context: context)
        guard let position = context.environment.scrollPositionBinding else {
            userScrolledSinceRender = false
            return
        }
        if glide == nil,
            let row = row(atRowLine: Int((Double(rowLineBudget - 1) * position.anchor.y).rounded(.down))),
            let id = rowID(row)
        {
            position.report(id, tracking: &positionTracking)
        }
        if userScrolledSinceRender {
            userScrolledSinceRender = false
            position.reportPositionedByUser()
        }
    }

    /// Scrolls so the content's line `line` is the first the rows show.
    func scroll(toLine line: Int) {
        guard itemCount > 0 else { return }
        clearOverscroll()
        let rowHeight = self.rowHeight ?? { _ in 1 }
        var top = 0
        for row in 0..<itemCount {
            let height = max(1, rowHeight(row))
            if line < top + height || row == itemCount - 1 {
                place(row: row, linesAbove: -max(0, min(line - top, height - 1)), rowHeight: rowHeight)
                break
            }
            top += height
        }
        clampScrollOffset()
        clampTopClip()
    }

    /// The row on the rows' line `line`, counted from the first line they
    /// show, or `nil` past the last row.
    private func row(atRowLine line: Int) -> Int? {
        let rowHeight = self.rowHeight ?? { _ in 1 }
        var bottom = -scrollTopClipLines
        var row = scrollOffset
        while row < itemCount {
            bottom += max(1, rowHeight(row))
            if line < bottom { return row }
            row += 1
        }
        return itemCount > 0 ? itemCount - 1 : nil
    }
}
