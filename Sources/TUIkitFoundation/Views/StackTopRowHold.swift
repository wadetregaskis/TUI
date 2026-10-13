//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StackTopRowHold.swift
//
//  The top-row hold of `Documentation/Layout and scrolling/Scroll anchoring.md`
//  §5 (``ScrollWindowHold/topRow``): with nothing else holding a scroll view,
//  rows inserted, removed or resized above the row at the top of its viewport
//  leave that row — and the rows on screen with it — where they are, as
//  SwiftUI's lazy stacks do.
//
//  The anchored walk gets this structurally: its anchor IS the row at the top,
//  re-bound to its key each frame (`rebindAnchor`). The uniform and exact
//  paths place rows at absolute content y, so there holding the row means
//  moving the OFFSET by however far the change moved it — remembered here as
//  the row's key and y when a frame is drawn, and compared on the next one.
//  The correction travels up the Stage-6 reply channel as `seekResolvedOffset`,
//  as a designated row's does (`StackDesignatedAnchor.swift`).
//
//  It is a SHIFT, not a placement: the offset the frame was asked for moves by
//  the distance the remembered row moved. So a scroll made since the last
//  frame is kept — a wheel tick and an insertion above in one frame move the
//  view by the tick — and a frame whose content above did not change moves
//  nothing, whatever its offset. Its cost on such a frame is one key read.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// The row at the top of the viewport when a windowed stack last drew a frame
/// — what ``ScrollWindowHold/topRow`` keeps in place on the next one.
struct HeldTopRow {
    /// The row's stable key, and which of the views a `ForEach` row of several
    /// hands over under that one key it is (decisions B15) — `0` for a row of
    /// one view, which is nearly every row.
    var key: String
    var runIndex: Int

    /// Where it was: its ordinal and its top, in the stack's coordinates.
    var ordinal: Int
    var y: Int

    /// The key of the row after it, which takes its place if it leaves the
    /// data, as the anchored walk's ladder hands the anchor to the row below a
    /// deleted one. `nil` for the last row.
    var nextKey: String?
}

/// How a stack's path reads its rows for the hold: how many, each one's key
/// (which never builds a row for a lazy `ForEach`), and each one's top in the
/// stack's coordinates — arithmetic for equal rows, the walked slot for the
/// exact walk.
struct TopRowGeometry {
    let count: Int
    let key: (Int) -> String?
    let y: (Int) -> Int
}

extension StackWindowState {

    /// How far the content above moved the row remembered at the top since the
    /// last frame — `0` when nothing above it changed, which costs one key read
    /// — and whether it was found at its ordinal; `nil` when there is no row
    /// to hold: none remembered, or neither it nor the row after it is in the
    /// data any more (the rows were replaced).
    ///
    /// A remembered row found at its ordinal was moved by a height change above
    /// it alone, which only the exact walk's slots can see; one found elsewhere
    /// was moved by rows inserted or removed above it. One gone is replaced by
    /// the row after it, put where it was.
    func heldTopRowShift(in rows: TopRowGeometry) -> (shift: Int, inPlace: Bool)? {
        guard let held = heldTopRow else { return nil }
        if held.ordinal < rows.count, rows.key(held.ordinal) == held.key {
            return (rows.y(held.ordinal) - held.y, true)
        }
        if let ordinal = Self.ordinal(of: held.key, runIndex: held.runIndex, near: held.ordinal, in: rows) {
            return (rows.y(ordinal) - held.y, false)
        }
        if let next = held.nextKey, let ordinal = Self.ordinal(of: next, runIndex: 0, near: held.ordinal, in: rows) {
            return (rows.y(ordinal) - held.y, false)
        }
        return nil
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
        rememberTopRow(atOrdinal: line > 0 && line < extent ? ordinal(line) : -1, in: rows, verified: verified)
    }

    /// Remembers the row at line `offset` of the stack — the top of the
    /// viewport this frame was drawn at — for the next frame's hold. Nothing
    /// is read when it is the row already remembered, at the same place, and
    /// this frame's ``heldTopRowShift(in:)`` found it there (`verified`); and
    /// nothing is kept at the top (an `ordinal` of `-1`), where nothing is
    /// held, so a stack at rest there pays nothing at all.
    func rememberTopRow(atOrdinal ordinal: Int, in rows: TopRowGeometry, verified: Bool) {
        guard ordinal >= 0, ordinal < rows.count else {
            heldTopRow = nil
            return
        }
        let y = rows.y(ordinal)
        if verified, let held = heldTopRow, held.ordinal == ordinal, held.y == y { return }
        guard let key = rows.key(ordinal) else {
            heldTopRow = nil
            return
        }
        var first = ordinal
        while first > 0, rows.key(first - 1) == key { first -= 1 }
        var next = ordinal + 1
        while next < rows.count, rows.key(next) == key { next += 1 }
        heldTopRow = HeldTopRow(
            key: key, runIndex: ordinal - first, ordinal: ordinal, y: y,
            nextKey: next < rows.count ? rows.key(next) : nil)
    }

    /// The ordinal holding the `runIndex`-th view of `key`'s row: found by a
    /// search outward from where it was (data shifts are usually small), then
    /// over every key — the documented Ω(n) id→ordinal cost, paid only on a
    /// frame whose content above the top row changed.
    private static func ordinal(of key: String, runIndex: Int, near origin: Int, in rows: TopRowGeometry) -> Int? {
        var found: Int?
        search: for distance in 0...64 {
            for candidate in [origin - distance, origin + distance]
            where candidate >= 0 && candidate < rows.count && rows.key(candidate) == key {
                found = candidate
                break search
            }
        }
        if found == nil {
            found = (0..<rows.count).first { rows.key($0) == key }
        }
        guard var first = found else { return nil }
        while first > 0, rows.key(first - 1) == key { first -= 1 }
        var ordinal = first
        while ordinal - first < runIndex, ordinal + 1 < rows.count, rows.key(ordinal + 1) == key { ordinal += 1 }
        return ordinal
    }
}

extension _VStackCore {
    /// The uniform path's placement after its seek: a designated row held
    /// (`holdingDesignatedRow`), or else the row at the top. Returns the
    /// offset to report — the designation's, which wins over the seek's (the
    /// seek chose a row and the designation then held it, so the corrected
    /// offset is the one drawn), the seek's, or the hold's — and whether the
    /// row at the top was found where it was.
    func holdingRow(
        after seeking: (window: ScrollContentWindow, resolved: Int?), children: ChildViewCollection,
        state: StackWindowState, rows: TopRowGeometry, rowHeight: Int, totalHeight: Int,
        context: RenderContext
    ) -> (window: ScrollContentWindow, resolved: Int?, verified: Bool) {
        var (window, designated) = holdingDesignatedRow(
            in: seeking.window, children: children, state: state, rowY: rows.y, rowHeight: rowHeight,
            totalHeight: totalHeight, context: context)
        if let resolved = designated ?? seeking.resolved { return (window, resolved, false) }
        let topRow = holdingTopRow(in: &window, rows: rows, state: state)
        return (window, topRow.resolved, topRow.verified)
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
        if let resolved = topRow.resolved { window.reply?.seekResolvedOffset = resolved }
        return (window, topRow.verified)
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
