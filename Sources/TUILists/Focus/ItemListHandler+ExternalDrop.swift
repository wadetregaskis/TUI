//  🖥️ TUI — A Terminal UI framework for Swift
//  ItemListHandler+ExternalDrop.swift
//
//  Where a drag from ANOTHER view would land in this list, and how that answer
//  is kept true while the rows move underneath it.
//
//  The pointer's position is only reported when it MOVES, and edge auto-scroll
//  is by definition the case where it holds still: the rows stream past a
//  motionless cursor. So the line the pointer last named is remembered, and the
//  question is asked again from it every frame the rows are republished — the
//  same shape, and the same reason, as the reorder retarget next door.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension ItemListHandler {
    /// Points the incoming-drop slot at `contentY`, and remembers the line.
    ///
    /// The rule is one method rather than three lines at each of the two call
    /// sites (a `List`'s and a `Table`'s drop destination) because it has to
    /// stay the same rule in both: past the last row the drop appends, above
    /// the first it lands before that row, the slot is clamped so a list that
    /// shrank under the pointer cannot strand it, and the line is kept so
    /// ``publishRowBands(_:)`` can ask the question again against the next
    /// frame's rows.
    package func hoverExternalDrop(atContentY contentY: Int) {
        lastExternalDropContentY = contentY
        // Past the rows, a pointer that is simply resting there means "append"
        // — the conventional answer, and the one a short list has always given.
        // Only the auto-scroll retarget below reads it differently, because
        // there the rows are moving and "the end of the data" is an answer about
        // somewhere the cursor is not.
        //
        // ABOVE the rows is not "past" them, and "no band here" cannot tell the
        // two apart. The drop target's rectangle is the whole control, so a
        // pointer arriving from above crosses the top border and a `Table`'s
        // column header first — negative lines in this space, which no band
        // covers. Falling through to `itemCount` there drew the gap below the
        // last visible row while the pointer sat on the header, and a release
        // handed the app the end of the data. The retarget has always answered
        // that line with the first row, but it runs only while auto-scroll
        // drives, and scrolling UP needs content above: a list at rest, one
        // whose rows all fit and a `.scrollDisabled` one never got the
        // correction. So the hover gives the same answer, through the same
        // helper, instead of leaving it to a pass that may never come.
        let target = dropTarget(atContentY: contentY)
        setExternalDropSlot(target ?? dropIndexAboveTheRows(atContentY: contentY) ?? itemCount)
        // Whether the retarget gets a run against this position turns on
        // WHETHER THE POINTER LANDED ON A BAND, and nothing else.
        //
        // On one, this has just answered from the pointer's own position, which
        // is the best answer there is: the retarget can only replace it with a
        // derived one, and its past-the-rows rule does exactly that at the
        // bottom of a list whose rows fill it — the gap the pointer is resting
        // on is itself the last band, so "past the rows" is true of a cursor
        // sitting squarely on it, and the gap is pulled one line up off the
        // pointer. Re-arming on a changed line (which is what this was) merely
        // slowed the 2026-08-24 flip from every frame to every mouse movement:
        // the two rules still disagreed, and the render still had the last word
        // over the pointer.
        //
        // Off one — the hot margin is chrome, and that is where a drag held at
        // the edge rests — the fallback above answers for an END of the rows,
        // not for the pointer: below them "append" is about the end of the data
        // rather than anywhere near the cursor, and above them the first row is
        // only the first row of THIS frame. Carrying either along as the rows
        // scroll is what the retarget exists for, so it is armed, and the
        // correction lands on the very next frame rather than a scroll step
        // later.
        externalDropResolvedOffset = target == nil ? nil : scrollOffset
    }

    /// Points the slot at `contentY` WITHOUT remembering the line.
    ///
    /// Split from ``hoverExternalDrop(atContentY:)`` because the auto-scroll
    /// retarget calls it every frame with the SAME remembered line: storing
    /// what it resolves would mean storing a derivative of the pointer's
    /// position, and the true position is gone after the first tick. The same
    /// split, for the same reason, as `resolveReorderTarget` versus
    /// `dragReorder`.
    ///
    /// Past the rows drawn, the drop lands on the nearest one rather than at
    /// the end of the data: while the list scrolls under a motionless pointer
    /// that is the whole question, and "append" is an answer about a row
    /// nowhere near the cursor.
    ///
    /// Onto the last row rather than after it, which looks like the off-by-one
    /// and is not. The gap occupies a line, so where it sits decides which row
    /// is drawn last; resolving "after the last row drawn" therefore moves the
    /// row that the next frame's answer is measured from, and the gap flips
    /// above and below the bottom row on alternate frames. Landing ON it is a
    /// fixed point, and puts the gap at the viewport's leading edge — the same
    /// place a reorder's slot rides, for the same reason.
    func retargetExternalDrop(atContentY contentY: Int) {
        // Answered for THIS offset. The caller will not ask again until the
        // rows have moved — see ``ItemListHandler/externalDropResolvedOffset``.
        externalDropResolvedOffset = scrollOffset
        let rows = visibleRowBands.compactMap { band -> (band: RowBand, index: Int)? in
            guard band.isContent, let index = band.dropIndex else { return nil }
            return (band, index)
        }
        guard let last = rows.last else {
            setExternalDropSlot(dropTarget(atContentY: contentY) ?? itemCount)
            return
        }
        if let above = dropIndexAboveTheRows(atContentY: contentY) {
            setExternalDropSlot(above)
        } else if contentY >= last.band.yStart + max(1, last.band.height) {
            setExternalDropSlot(last.index)
        } else {
            setExternalDropSlot(dropTarget(atContentY: contentY) ?? itemCount)
        }
    }

    /// The lines the slot a drag from another view opens is drawn in: one for
    /// each row the drag would land, as a reorder's slot makes room for the
    /// block it carries. Showing less promised less than the drop does, and the
    /// rows landed over the ones below it.
    ///
    /// One line a row whatever the rows' heights, which only their source knows,
    /// as a reorder's pads the rows it cannot see. And never more than half the
    /// rows' area, however many are carried: the pointer resting on the gap holds
    /// the gap where it is, so a gap that took the whole list would leave no row
    /// to aim at. Asked of ``contentHeight``, the frame's area, because the rows'
    /// own window is what this line count takes from.
    package var externalDropSlotLines: Int {
        guard externalDropSlot != nil, let drag = dragSession?.active else { return 1 }
        return min(DragAndDropSession.items(of: drag.payload).count, max(1, (contentHeight ?? 1) / 2))
    }

    /// Consumes the slot for a drop that is happening now: the clamped index
    /// to insert at, with the hover state cleared.
    ///
    /// The clamp is here and not only in ``setExternalDropSlot(_:)`` because
    /// the two are answers to different questions. That one keeps a *hover*
    /// truthful as rows come and go; this one is read at the moment of
    /// insertion, and between the last hover and the drop the data can shrink
    /// with no pointer event to re-clamp on — a filter narrowing, a sibling
    /// view taking the item, the drag's own source removing it. The documented
    /// use of this index is `insert(contentsOf:at:)`, which traps rather than
    /// clamping, so the read side has to be sure on its own.
    package func takeExternalDropSlot() -> Int {
        let slot = externalDropSlot ?? itemCount
        externalDropSlot = nil
        return min(max(0, slot), itemCount)
    }

    /// The slot, clamped to the list's own bounds — a list that shrank under
    /// the pointer must not strand it past the end — or none, where the
    /// destination refuses a drop there (``externalDropTakes``).
    ///
    /// A refused slot opens no gap, and the drop the pointer would make there
    /// finds no slot and is refused. The line the pointer named is kept, as
    /// for a slot taken: rows scrolling under a still pointer may bring one
    /// the destination takes, which the auto-scroll retarget then finds.
    private func setExternalDropSlot(_ slot: Int) {
        let slot = min(max(0, slot), itemCount)
        guard let takes = externalDropTakes, !takes(slot) else {
            externalDropSlot = slot
            return
        }
        // Clearing the slot forgets the line it was found from; it is put
        // back, since only the slot is refused.
        let (line, resolvedOffset) = (lastExternalDropContentY, externalDropResolvedOffset)
        externalDropSlot = nil
        lastExternalDropContentY = line
        externalDropResolvedOffset = resolvedOffset
    }

    /// The drop index of the first band drawn that takes one, when `contentY`
    /// is above it — on the border, a `Table`'s column header, a scroll
    /// indicator drawn over the rows — and `nil` anywhere else.
    ///
    /// One helper for the hover and the auto-scroll retarget because they
    /// answer the same line, and did so differently: the retarget said "the
    /// first row" and the hover said "append", so on an unscrolled list the gap
    /// sat at the bottom while the pointer was on the header.
    ///
    /// The gap's own band counts, and has to. A row's drop index is its DRAWN
    /// position (``reorderDrawnPosition(of:)``), so once the gap opens above the
    /// first row, that row names the position after itself. Passing over the
    /// gap to read the row walked the slot down one row on the pointer's next
    /// report over the header. The gap carries `externalDropSlot`, so when it is
    /// drawn first the answer is the slot it already has: a fixed point.
    /// Section headers and other chrome publish no drop index, and are passed
    /// over.
    private func dropIndexAboveTheRows(atContentY contentY: Int) -> Int? {
        guard let first = visibleRowBands.first(where: { $0.dropIndex != nil }),
            contentY < first.yStart
        else { return nil }
        return first.dropIndex
    }
}
