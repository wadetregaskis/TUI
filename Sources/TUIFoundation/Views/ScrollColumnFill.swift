//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollColumnFill.swift
//
//  SCROLL-FIT's fill engine, its column shape (design B-SCROLLFIT-12): the
//  scroll position is an anchor — a row and the lines of it above the
//  viewport (`ScrollContentAnchor`) — scroll input is walked from it as a
//  delta in row space, and the viewport is filled outward from it, measuring
//  only the rows it reaches. Written once, against the rows a column answers
//  for (`ScrollFillColumn`), so that every column that windows walks alike:
//  the lazy stack's anchored window today (`StackAnchoredWindow.swift`),
//  `List` and `Table` when they are pulled.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// The rows of a column, as the fill engine walks them: how many there are,
/// each one's pitch, and each one's key, with the anchor the walk moves.
///
/// A row's pitch is measured when the walk first asks for it and never before:
/// the engine asks only for the rows it reaches, which is what makes a frame
/// O(visible) whatever the row count.
@MainActor
protocol ScrollFillColumn: AnyObject {
    /// How many rows the column holds. O(1): a `ForEach` answers from its
    /// data's count.
    var rowCount: Int { get }

    /// Row `ordinal`'s pitch: its lines and the spacing below it (the last
    /// row has none), never below 1.
    func pitch(of ordinal: Int) -> Int

    /// Row `ordinal`'s stable key, read without building the row.
    func key(at ordinal: Int) -> String?

    /// The first row keyed `key`, by a scan of the keys — Ω(rows), no row
    /// built — or `nil` when no row is.
    func firstOrdinal(forKey key: String) -> Int?

    /// The rows the last frame drew, by key: the ladder an anchor whose row
    /// left the data falls on (§5f).
    var ladder: [String: Int] { get }

    /// The pitch a row never measured is priced at: what a jump of more than
    /// four screens lands by.
    var estimatedPitch: Int { get }

    /// The position the walk reads and moves.
    var anchor: ScrollContentAnchor { get }
}

extension ScrollFillColumn {
    /// Re-binds the persisted anchor ordinal to its stable key (§5f). The
    /// fast path — the key still lives at the remembered ordinal — is one
    /// key build. On a miss, the key is searched nearby first (data shifts
    /// are usually small), then everywhere (the documented Ω(n) id→ordinal
    /// cost, touching keys only). A key that left the data entirely falls
    /// to the LADDER: last frame's rendered rows, nearest survivor first,
    /// preserving the lines of it hidden (`within`). A dead ladder (the list was
    /// replaced) leaves the clamped index fallback — approximate, and
    /// correct at the ends (§5f).
    ///
    /// Only when `holdsRow`: the anchor is a designated row, followed wherever
    /// it goes. Otherwise the ordinal is kept — the position stays where it is
    /// in line coordinates, and an insert above shifts the content down —
    /// unless the row at the top is held this frame, from the memory every
    /// path keeps of it (`rebindingAnchor`). See
    /// `Documentation/Layout and scrolling/Scroll anchoring.md` §1.1 and §5.
    func rebindAnchor(holdsRow: Bool) {
        let count = rowCount
        guard count > 0 else { return }
        anchor.ordinal = min(max(0, anchor.ordinal), count - 1)
        guard holdsRow else { return }
        guard let anchorKey = anchor.key else { return }
        guard key(at: anchor.ordinal) != anchorKey else { return }

        if let found = locate(key: anchorKey) {
            anchor.ordinal = found
            return
        }
        // Nearest first, and of the two equally near — the rows either side of
        // a deleted one — the one below, which the delete moved into its place:
        // nothing else moves. Ordered by distance alone, the pair came in the
        // memo's order, which the process's hash seed sets, and which row took
        // the anchor, and so the frame, changed from one run to the next.
        let neighbours = ladder.sorted {
            let distances = (abs($0.value - anchor.ordinal), abs($1.value - anchor.ordinal))
            return distances.0 != distances.1 ? distances.0 < distances.1 : $0.value > $1.value
        }
        for (key, _) in neighbours where key != anchorKey {
            if let found = locate(key: key) {
                anchor.ordinal = found
                anchor.key = key
                return
            }
        }
    }

    /// The ordinal holding `key`: nearby ring search first, then the full
    /// key scan. Never builds a row view.
    private func locate(key: String) -> Int? {
        let count = rowCount
        let origin = anchor.ordinal
        for distance in 0...64 {
            for candidate in [origin - distance, origin + distance]
            where candidate >= 0 && candidate < count {
                if self.key(at: candidate) == key { return candidate }
            }
        }
        return firstOrdinal(forKey: key)
    }

    /// Applies a scroll offset to the persisted anchor. A big jump seeks by
    /// estimate (O(1), approximate — what a scrollbar drag means); a small
    /// delta walks rows until it is consumed (one line up looks at one row).
    ///
    /// `linesBelow` is what the scroll content draws below this stack — a
    /// section's footer (``ScrollContentWindow/linesBelow``) — which ends the
    /// content where this stack does not.
    func advanceAnchor(to offset: Int, viewportHeight: Int, linesBelow: Int) {
        let count = rowCount
        var anchor = min(self.anchor.ordinal, count - 1)
        var within = self.anchor.within
        let delta = offset - self.anchor.derivedOffset
        if abs(delta) > viewportHeight * 4, let reported = self.anchor.reportedTotal,
            offset + viewportHeight >= reported
        {
            // A jump to the very bottom of what this stack last reported — End,
            // a tail glue re-asserted after the total refined, a scrollbar
            // dragged down — means the LAST rows, whatever the running pitch
            // says. Mapped through the average instead, a tail of rows taller
            // than the rest (groups that grow down the list) lands short: the
            // average the tail itself raised divides the offset into an ordinal
            // far above it, and End showed the last row for a frame and then
            // settled mid-list. So the bottom is placed exactly, from the last
            // row up — the estimate is exact at the endpoints.
            //
            // At this stack's end, which is the viewport's bottom only when
            // nothing is drawn below the stack. A footer fills the viewport's
            // lines past the end: placed at the viewport's bottom, the last row
            // pushed the footer below it, and a jump to the content's end that
            // is not glued (`scrollTo(y:)` past it) stayed there, the footer
            // never shown.
            let pastEnd = min(offset + viewportHeight - reported, linesBelow)
            (anchor, within) = tailAnchor(endingAt: viewportHeight - pastEnd)
        } else if abs(delta) > viewportHeight * 4 {
            let estimate = estimatedPitch
            anchor = min(count - 1, max(0, offset / estimate))
            within = max(0, offset - anchor * estimate)
        } else if delta != 0 {
            within += delta
            while within < 0, anchor > 0 {
                anchor -= 1
                within += pitch(of: anchor)
            }
            if within < 0 { within = 0 }
            while anchor < count - 1, within >= pitch(of: anchor) {
                within -= pitch(of: anchor)
                anchor += 1
            }
        }
        // Clamp against the CURRENT pitch unconditionally — not just on the
        // frames that scrolled. A width change re-wraps rows and shrinks
        // pitches under a stale `within` (a viewport top that was a wrap
        // continuation line no longer exists), and without this the anchor
        // row silently drifts above the viewport on a resize frame whose
        // offset didn't move (§5e: the anchor row is pinned by construction).
        //
        // The last row alone may sit wholly above the viewport, when what is
        // drawn below this stack is taller than the viewport: at the content's
        // end the viewport's top is `linesBelow - viewportHeight` lines past
        // the stack's end. Held to the viewport, the last row's last line rode
        // down with every line scrolled, the footer under it, whose end was
        // never reached.
        let pastEnd = anchor == count - 1 ? max(0, linesBelow - viewportHeight + 1) : 0
        within = min(within, max(0, pitch(of: anchor) - 1 + pastEnd))
        // A negative offset is a viewport whose top shows what the scroll
        // content draws above this stack — a section's header
        // (`ScrollContentWindow/linesAbove`) — so the first row sits that many
        // lines down it. Every branch above floors `within` at 0, which would
        // have drawn row 0 at the viewport's top, over the header's lines.
        if offset < 0 {
            anchor = 0
            within = offset
        }
        self.anchor.ordinal = anchor
        self.anchor.within = within
        self.anchor.derivedOffset = offset
    }

    /// The anchor that puts the last row's bottom `line` lines below the
    /// viewport's top — at its bottom, or above a footer — walking up from the
    /// last row by exact pitches until those lines are covered: the row
    /// reached and how many of its lines sit above the viewport's top. At or
    /// above the top (`line <= 0`, a footer taller than the viewport) that is
    /// the last row, wholly above it. O(the rows one viewport shows).
    func tailAnchor(endingAt line: Int) -> (ordinal: Int, within: Int) {
        var ordinal = rowCount - 1
        var covered = pitch(of: ordinal)
        while covered < line, ordinal > 0 {
            ordinal -= 1
            covered += pitch(of: ordinal)
        }
        return (ordinal, max(0, covered - line))
    }

    /// Fills outward from the anchor: the anchor row sits exactly at
    /// (offset − offsetWithin); rows below fill until the viewport plus one
    /// margin row is covered; one margin row above (when it fits the
    /// absolute space). Returns the placements plus the deepest ordinal
    /// reached and the y just below it (the estimated-suffix base).
    func fill(window: ScrollContentWindow) -> (placed: [(ordinal: Int, y: Int)], last: Int, bottomY: Int) {
        let count = rowCount
        let anchor = self.anchor.ordinal
        let anchorY = window.offset - self.anchor.within
        var placed: [(ordinal: Int, y: Int)] = []
        var y = anchorY
        var ordinal = anchor
        let windowBottom = window.offset + window.viewportHeight
        while ordinal < count, y < windowBottom {
            placed.append((ordinal, y))
            y += pitch(of: ordinal)
            ordinal += 1
        }
        if ordinal < count {
            placed.append((ordinal, y))  // bottom margin row
            y += pitch(of: ordinal)
        }
        let last = placed.last?.ordinal ?? anchor
        // Fill upward from the anchor, covering the viewport top plus one
        // margin row for scroll-up reveal. With the implicit top anchor
        // (`anchor.within >= 0`, so `anchorY <= offset`) the anchor is
        // already the top-visible row, and this places exactly ONE row — the
        // margin above it — as the single-margin version did. A DESIGNATED row
        // held BELOW the top (`anchor.within < 0`, `anchorY > offset`)
        // also draws the now-visible rows between the top and the anchor.
        var upperY = anchorY
        var above = anchor - 1
        var reachedTop = anchorY <= window.offset
        while above >= 0 {
            let aboveY = upperY - pitch(of: above)
            if aboveY < 0 { break }  // absolute-space floor (full-height buffer)
            placed.append((above, aboveY))
            upperY = aboveY
            if reachedTop { break }  // just placed the one margin row above the top
            if aboveY <= window.offset { reachedTop = true }  // this row IS the top-visible one
            above -= 1
        }
        return (placed, last, y)
    }
}
