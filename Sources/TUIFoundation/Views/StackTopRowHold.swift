//  🖥️ TUI — A Terminal UI framework for Swift
//  StackTopRowHold.swift
//
//  The top-row hold of `Documentation/Layout and scrolling/Scroll anchoring.md`
//  §5 (``ScrollWindowHold/topRow``): with nothing else holding a scroll view,
//  rows inserted, removed or resized above the row at the top of its viewport
//  leave that row — and the rows on screen with it — where they are, as
//  SwiftUI's lazy stacks do.
//
//  Every path remembers the row at the top here when it draws a frame — its
//  key, its ordinal, its top, and the line of the viewport's top — and finds
//  where it went on the next one (`heldTopRowPlace`), so the hold survives a
//  stack crossing from one path to another. The uniform and exact paths place
//  rows at absolute content y, so there holding the row means moving the
//  OFFSET by however far the change moved it; the correction travels up the
//  Stage-6 reply channel as `seekResolvedOffset`, as a designated row's does
//  (`StackDesignatedAnchor.swift`). The anchored walk places rows from its
//  anchor, so there the row found becomes the anchor (`rebindingAnchor`).
//
//  It is a SHIFT, not a placement: the offset the frame was asked for moves by
//  the distance the remembered row moved. So a scroll made since the last
//  frame is kept — a wheel tick and an insertion above in one frame move the
//  view by the tick — and a frame whose content above did not change moves
//  nothing, whatever its offset. Its cost on such a frame is one key read.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// The row at the top of the viewport when a windowed stack last drew a frame
/// — what ``ScrollWindowHold/topRow`` keeps in place on the next one.
struct HeldTopRow {
    /// The row's stable key, and which of the views a `ForEach` row of several
    /// hands over under that one key it is (decisions B15) — `0` for a row of
    /// one view, which is nearly every row.
    var key: String
    var runIndex: Int

    /// Where it was: its ordinal and its top, in the stack's coordinates —
    /// the anchored walk's own, which place rows from its anchor by estimate,
    /// when that path drew it.
    var ordinal: Int
    var y: Int

    /// The stack's line at the viewport's top when it was remembered: `top - y`
    /// lines of the row lie above the viewport's top — fewer than none for a
    /// row held below it, a designated one on the anchored walk. What the
    /// anchored walk takes its anchor from when it holds the row, whichever
    /// path drew the frame before (`rebindingAnchor`).
    var top: Int

    /// The key of the row after it, which takes its place if it leaves the
    /// data, as the anchored walk's ladder hands the anchor to the row below a
    /// deleted one, and how many ordinals after it it was. `nil` for the last
    /// row.
    var nextKey: String?
    var nextOffset: Int

    /// The key of the row before it, and how many ordinals before it its last
    /// view was. `nil` for the first row. With the row after it, what tells a
    /// change above from a sort (``StackWindowState/heldTopRowPlace(in:)``).
    var previousKey: String?
    var previousOffset: Int

    /// How many rows the stack had when the neighbours were read. A frame
    /// that finds the row where it was reads nothing — unless the count has
    /// changed since, when a row may have been inserted or removed beside it,
    /// and the neighbours are read again (``StackWindowState/rememberTopRow(atOrdinal:y:top:in:verified:)``).
    var count: Int
}

/// How a stack's path reads its rows for the hold: how many, each one's key
/// (which never builds a row for a lazy `ForEach`), and each one's top in the
/// stack's coordinates — arithmetic for equal rows, the walked slot for the
/// exact walk.
struct TopRowGeometry {
    let keys: RowKeys
    let y: (Int) -> Int

    init(count: Int, key: @escaping (Int) -> String?, y: @escaping (Int) -> Int) {
        keys = RowKeys(count: count, key: key)
        self.y = y
    }
}

extension StackWindowState {

    /// The ordinal that holds the place of the row remembered at the top —
    /// its own, found where the content above moved it, which costs one key
    /// read when nothing above it changed — and whether it was found at the
    /// ordinal it had; `nil` when there is no row to hold: none remembered, or
    /// neither it nor the row after it is in the data any more (the rows were
    /// replaced).
    ///
    /// A remembered row found elsewhere with the row before it or the row
    /// after it still beside it was moved by rows inserted or removed above
    /// it — and maybe a row inserted or removed beside it in the same change,
    /// which moves one of the two only. One found elsewhere WITHOUT either was
    /// moved by the rows being rearranged — a sort — and is not followed:
    /// SwiftUI holds no row through a reorder (measured,
    /// `Tools/SwiftUIProbes/Scroll anchoring/reorder.out`), and following one
    /// would scroll a sorted list to wherever its top row went. Asked of the
    /// row after it alone, a change that inserted rows above it and one just
    /// after it, or removed the row after it, was taken for a sort and let the
    /// rows move.
    ///
    /// One gone is replaced by the row after it, put where it was — unless
    /// the row before it is still right before the place the row after it
    /// marks, or the row after it still as far after the place it had (the
    /// row before it renamed too, or a first row, which has none), and the
    /// row before it is not right before the row after it, the top row gone
    /// from between them: then the place is still there and
    /// only the row in it changed, its id
    /// changed where it stands (`ForEach(names, id: \.self)` with the name at
    /// the top edited), and nothing above moved it: nothing moves, as in
    /// SwiftUI (measured, `Tools/SwiftUIProbes/Scroll anchoring/beside.out`
    /// case 1). Taken for the row gone, the row after it was put where it was,
    /// and the view moved down a row.
    func heldTopRowPlace(in keys: RowKeys) -> (ordinal: Int, inPlace: Bool)? {
        guard let held = heldTopRow else { return nil }
        if keys[held.ordinal] == held.key { return (held.ordinal, true) }
        if let ordinal = keys.ordinal(of: held.key, runIndex: held.runIndex, near: held.ordinal) {
            guard keepsANeighbour(held, at: ordinal, in: keys) else { return nil }
            return (ordinal, false)
        }
        if let next = held.nextKey,
            let ordinal = keys.ordinal(of: next, runIndex: 0, near: held.ordinal + held.nextOffset)
        {
            // Not kept when the row before it is now right before the row
            // after it: the top row went from between them. Asked of the row
            // before it alone, the top row renamed with the row above it took
            // the place for gone; asked of "still where the place was" alone,
            // the top row removed with exactly one row inserted above took it
            // for kept, and put the row from above the screen on top.
            let place = ordinal - held.nextOffset
            let closedUp = held.previousKey.map { keys[ordinal - 1] == $0 } ?? false
            let placeKept =
                !closedUp
                && (place == held.ordinal || held.previousKey.map { keys[place - held.previousOffset] == $0 } == true)
            return (placeKept ? place : ordinal, false)
        }
        return nil
    }

    /// Whether the row before `held` or the row after it is still beside it,
    /// now that it is at `ordinal` — or it had neither (the only row).
    private func keepsANeighbour(_ held: HeldTopRow, at ordinal: Int, in keys: RowKeys) -> Bool {
        let previous = held.previousKey.map { keys[ordinal - held.previousOffset] == $0 }
        let next = held.nextKey.map { keys[ordinal + held.nextOffset] == $0 }
        return previous == true || next == true || (previous == nil && next == nil)
    }

    /// How far the content above moved the row remembered at the top since the
    /// last frame (``heldTopRowPlace(in:)``): `0` when nothing above it
    /// changed. A row found at its ordinal (`inPlace`) was moved by a height
    /// change above it alone, which only the exact walk's slots can see — or
    /// it was remembered in the anchored walk's lines, and this is the frame
    /// the stack left that path on: the shift takes it from those to these.
    func heldTopRowShift(in rows: TopRowGeometry) -> (shift: Int, inPlace: Bool)? {
        guard let held = heldTopRow, let place = heldTopRowPlace(in: rows.keys) else {
            return nil
        }
        return (rows.y(place.ordinal) - held.y, place.inPlace)
    }

    /// Remembers the row at `line` of the stack — the top of the viewport the
    /// frame was drawn at, found by `ordinal(_:)` — when the scroll view asks
    /// for the hold at all (`hold`); nothing at the top, or past the stack's
    /// `extent`.
    func rememberTopRow(
        atLine line: Int, of extent: Int, hold: TopRowHold, ordinal: (Int) -> Int,
        in rows: TopRowGeometry, verified: Bool
    ) {
        guard hold != .off else { return }
        let found = line > 0 && line < extent ? ordinal(line) : -1
        guard found >= 0, found < rows.keys.count else {
            heldTopRow = nil
            return
        }
        rememberTopRow(atOrdinal: found, y: rows.y(found), top: line, in: rows.keys, verified: verified)
    }

    /// Remembers the row at `ordinal`, its top at `y` and the viewport's top at
    /// line `top` of the stack — the frame being drawn — for the next frame's
    /// hold. Nothing is read when it is the
    /// row already remembered, at the same place, and this frame found it there
    /// (`verified`), with as many rows as when its neighbours were read; and
    /// nothing is kept at the top (an `ordinal` of `-1`, or
    /// none), where nothing is held, so a stack at rest there pays nothing at
    /// all.
    ///
    /// The count is what keeps the neighbours fresh. A row inserted just after
    /// the top row, or the row after it removed, leaves the top row where it
    /// was; unread, the row after it was a frame stale, and the top row renamed
    /// later put the row two after it on top (the SCROLLANCHOR review, S3).
    func rememberTopRow(atOrdinal ordinal: Int, y: Int, top: Int, in keys: RowKeys, verified: Bool) {
        guard ordinal >= 0, ordinal < keys.count else {
            heldTopRow = nil
            return
        }
        if verified, let held = heldTopRow, held.ordinal == ordinal, held.y == y, held.count == keys.count {
            heldTopRow?.top = top
            return
        }
        guard let rowKey = keys[ordinal] else {
            heldTopRow = nil
            return
        }
        var first = ordinal
        var previousKey = keys[first - 1]
        while previousKey == rowKey {
            first -= 1
            previousKey = keys[first - 1]
        }
        var next = ordinal + 1
        var nextKey = keys[next]
        while nextKey == rowKey {
            next += 1
            nextKey = keys[next]
        }
        heldTopRow = HeldTopRow(
            key: rowKey, runIndex: ordinal - first, ordinal: ordinal, y: y, top: top,
            nextKey: nextKey, nextOffset: next - ordinal,
            previousKey: previousKey, previousOffset: ordinal - first + 1, count: keys.count)
    }
}

/// A stack's rows as the top-row hold reads them: `count` of them, each one's
/// key read by `key` (which never builds a row for a lazy `ForEach`), `nil`
/// past either end.
struct RowKeys {
    let count: Int
    let key: (Int) -> String?

    subscript(ordinal: Int) -> String? { ordinal >= 0 && ordinal < count ? key(ordinal) : nil }

    /// The ordinal holding the `runIndex`-th view of `key`'s row: found by a
    /// search outward from where it was (data shifts are usually small), then
    /// over every key — the documented Ω(n) id→ordinal cost, paid only on a
    /// frame whose content above the top row changed.
    ///
    /// What that comes to: a row moved by k places, k up to 64, is found in
    /// about 2k key reads. One moved further — a "load earlier" of a hundred
    /// rows — costs 130 reads and then the scan, which reads from the first
    /// key and stops at it: O(the row's position), not O(k). A key that is
    /// nowhere — the top row removed, or its id changed — costs 130 reads and
    /// a scan of every key: O(n), every row of a stack scrolled anywhere.
    func ordinal(of rowKey: String, runIndex: Int, near origin: Int) -> Int? {
        var found: Int?
        search: for distance in 0...64 {
            for candidate in [origin - distance, origin + distance] where self[candidate] == rowKey {
                found = candidate
                break search
            }
        }
        if found == nil {
            found = (0..<count).first { self[$0] == rowKey }
        }
        guard var first = found else { return nil }
        while self[first - 1] == rowKey { first -= 1 }
        var ordinal = first
        while ordinal - first < runIndex, self[ordinal + 1] == rowKey { ordinal += 1 }
        return ordinal
    }
}

@MainActor extension _VStackCore {
    /// The uniform path's placement after its seek: a designated row held
    /// (`holdingDesignatedRow`), or else the row at the top. Returns the
    /// offset to report — the designation's, which wins over the seek's (the
    /// seek chose a row and the designation then held it, so the corrected
    /// offset is the one drawn), the seek's, or the hold's — whether it is the
    /// hold's (``ScrollContentReply/resolvedOffsetIsHold``), and whether the
    /// row at the top was found where it was.
    func holdingRow(
        after seeking: (window: ScrollContentWindow, resolved: Int?), children: ChildViewCollection,
        state: StackWindowState, rows: TopRowGeometry, rowHeight: Int, totalHeight: Int,
        context: RenderContext
    ) -> (window: ScrollContentWindow, resolved: Int?, isHold: Bool, verified: Bool) {
        var (window, designated) = holdingDesignatedRow(
            in: seeking.window, children: children, state: state, rowY: rows.y, rowHeight: rowHeight,
            totalHeight: totalHeight, context: context)
        if let resolved = designated ?? seeking.resolved { return (window, resolved, false, false) }
        let topRow = holdingTopRow(in: &window, rows: rows, state: state)
        return (window, topRow.resolved, true, topRow.verified)
    }

    /// The exact walk's placement: a pending seek re-aims the window — exact
    /// here, the slots carrying every row's true y — and is reported so the
    /// scroll view adopts it this frame; a designated row then keeps its line
    /// as rows come and go around it (`holdDesignatedRow`); with neither, the
    /// row at the top keeps its line, through rows inserted, removed or resized
    /// above it alike. Returns the window, and whether the row at the top was
    /// found where it was.
    func placingExactWalk(
        _ window: ScrollContentWindow, slots: [RowSlot], rows: TopRowGeometry, context: RenderContext
    ) -> (window: ScrollContentWindow, verified: Bool) {
        var window = window
        var sought = false
        if let seek = window.seek {
            window.seek = nil
            if let index = slots.firstIndex(where: { $0.child.matchesSeekKey(seek.key) }) {
                let total = slots.last.map { $0.y + $0.height } ?? 0
                let newOffset = window.offset(
                    realising: seek, targetY: slots[index].y, rowHeight: slots[index].height,
                    stackHeight: total)
                window.offset = newOffset
                window.reply?.seekResolvedOffset = newOffset
                sought = true
            }
        }
        guard !holdDesignatedRow(slots: slots, window: &window, context: context), !sought else {
            return (window, false)
        }
        let topRow = holdingTopRow(in: &window, rows: rows, state: uniformWindowState(context: context))
        window.reply?.reportResolvedOffset(topRow.resolved, isHold: true)
        return (window, topRow.verified)
    }

    /// Remembers the anchored walk's anchor — the row at the top, or a
    /// designated row held below it — for the next frame's top-row hold,
    /// whichever path draws it
    /// (``StackWindowState/rememberTopRow(atOrdinal:y:top:in:verified:)``): its
    /// top in this walk's lines is the offset less the lines of it above the
    /// viewport's top. Nothing is read when it is the row remembered, where it
    /// was; nothing at all at the top, nor when the scroll view keeps its
    /// offset in lines.
    func rememberAnchoredTopRow(
        state: StackWindowState, window: ScrollContentWindow, children: ChildViewCollection
    ) {
        guard window.topRowHold != .off else { return }
        guard window.offset > 0 else {
            state.heldTopRow = nil
            return
        }
        let held = state.heldTopRow
        state.rememberTopRow(
            atOrdinal: state.anchorOrdinal, y: window.offset - state.anchorOffsetWithin, top: window.offset,
            in: RowKeys(count: children.count, key: { children.key(at: $0) }),
            verified: held?.key == state.anchorKey && held?.ordinal == state.anchorOrdinal)
    }

    /// The slot whose row — or the spacing above it — holds line `y` of the
    /// stack: the last one starting at or above it. Binary, the slots being in
    /// order.
    static func slotIndex(at y: Int, in slots: [RowSlot]) -> Int {
        var low = 0
        var high = slots.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if slots[middle].y - slots[middle].spacingBefore <= y { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// Moves `window`'s offset by however far the content above moved the row
    /// at the viewport's top since the last frame, when the scroll view asks
    /// for the hold this frame (``ScrollContentWindow/topRowHold``), and
    /// returns the offset to report, or `nil` when it moved nothing.
    ///
    /// `verified` comes back `true` when the remembered row was found where it
    /// was, so ``StackWindowState/rememberTopRow(atOrdinal:in:verified:)``
    /// need not read it again.
    func holdingTopRow(
        in window: inout ScrollContentWindow, rows: TopRowGeometry, state: StackWindowState
    ) -> (resolved: Int?, verified: Bool) {
        guard window.topRowHold != .off else { return (nil, false) }
        guard let found = state.heldTopRowShift(in: rows) else { return (nil, false) }
        guard found.shift != 0, window.topRowHold == .holding else {
            return (nil, found.inPlace && found.shift == 0)
        }
        window.offset += found.shift
        return (window.offset, false)
    }
}
