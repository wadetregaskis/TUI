//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollContentWindow.swift
//
//  The ScrollView ↔ windowed-stack handshake: the visible slice travels
//  down as an environment value; the Stage-6 slice report travels back up
//  through the reply reference within the same render call.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

struct ScrollContentWindow: Sendable, Hashable {
    /// Equality and hashing deliberately **exclude** ``reply``.
    ///
    /// That slot is a per-render mailbox — `ScrollContentReply()` is freshly
    /// allocated on every pass — so synthesised conformance made two windows
    /// describing the *same* visible slice compare and hash differently every
    /// frame. Anything keyed on the environment (the render memo) therefore
    /// saw every subtree under a `ScrollView` change on every frame.
    ///
    /// A window is identified by what it *describes* — the offset, the
    /// viewport, whose content it addresses — not by which mailbox happens to
    /// be attached for the reply to travel back through.
    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.offset == rhs.offset, lhs.viewportHeight == rhs.viewportHeight,
            lhs.contentIdentity == rhs.contentIdentity, lhs.edgeInset == rhs.edgeInset,
            lhs.reportsIDAt == rhs.reportsIDAt, lhs.seek == rhs.seek, lhs.columnSeek == rhs.columnSeek,
            lhs.columnReport == rhs.columnReport,
            lhs.linesAbove == rhs.linesAbove, lhs.linesBelow == rhs.linesBelow
        else { return false }
        return lhs.reportsTargetLayout == rhs.reportsTargetLayout
            && lhs.reportsTargetVisibility == rhs.reportsTargetVisibility && lhs.topRowHold == rhs.topRowHold
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(offset)
        hasher.combine(viewportHeight)
        hasher.combine(contentIdentity)
        hasher.combine(edgeInset)
        hasher.combine(reportsIDAt)
        hasher.combine(seek)
        hasher.combine(columnSeek)
        hasher.combine(columnReport)
        hasher.combine(linesAbove)
        hasher.combine(linesBelow)
        hasher.combine(reportsTargetLayout)
        hasher.combine(reportsTargetVisibility)
        hasher.combine(topRowHold)
    }

    /// The scroll offset in the coordinates of the stack that consumes this
    /// window: the scroll view's offset less ``linesAbove``. So it is negative
    /// while any line drawn above the stack is on screen, and every stack path
    /// takes a negative offset as "the band starts at row 0".
    var offset: Int
    var viewportHeight: Int

    /// The identity of the ScrollView's direct content. A windowed stack
    /// consumes this window only when its own identity is a single-child
    /// descent from here (`ViewIdentity/isDirectDescent(from:)`): a stack
    /// that is one sibling among several is NOT at the scroll origin, and
    /// windowing there would blank the wrong rows. `nil` (tests, direct
    /// injection) means "trust the publisher" and consume unconditionally.
    var contentIdentity: ViewIdentity?

    /// Whether a view at `identity` is reached from the scroll view's content
    /// by single-child steps (``contentIdentity``), and so is at the content's
    /// origin: a stack there consumes this window, and a view drawing lines
    /// around its content there relays it (`ScrollWindowRelay`).
    func isAtOrigin(_ identity: ViewIdentity) -> Bool {
        guard let contentIdentity else { return true }
        return identity.isDirectDescent(from: contentIdentity)
    }

    /// The render-pass reply slot (Stage 6): the stack reports the compact
    /// slice it actually rendered, so the ScrollView can clip a band
    /// instead of a full-height canvas. `nil` (tests, measure passes) keeps
    /// the stack emitting the classic full-height buffer.
    var reply: ScrollContentReply?

    /// One line of headroom per edge when the "N more above/below" indicators
    /// can replace the viewport's first/last line — the same reservation
    /// ``ScrollToRequest/topInset`` makes for seeks, carried on the window
    /// because a DESIGNATED anchor reveals rows with no request to stamp.
    /// Without it, designating an off-screen row lands it exactly under an
    /// indicator, where it is invisible however correctly it was placed.
    var edgeInset = 0

    /// Where in the viewport to sample the row whose id is reported back
    /// through ``ScrollContentReply/anchorID``, or `nil` to sample nothing.
    ///
    /// The row reported is the first whose bottom lies past the sampled line
    /// (``sampleY(at:contentBelow:)``), on every path a stack takes: a line in
    /// the gap between two rows belongs to the row below it.
    ///
    /// Set only when something is actually listening (a `.scrollPosition(id:)`
    /// binding): the sample costs an `anyID(at:)` per frame, and a scroll view
    /// nobody is asking should not pay it.
    var reportsIDAt: UnitPoint?

    /// The content-space y that `unit` names within the VISIBLE band.
    ///
    /// Not simply `offset + unit.y × height`: the "N more above/below"
    /// indicators overwrite the viewport's first and last line, so those rows
    /// are on the canvas but not on the screen. Reporting one as "the row you
    /// are looking at" would name a row nobody can see — which is exactly the
    /// row a `.top` seek deliberately steps past.
    ///
    /// Only where they DO overwrite, which is what `edgeInset` says. Under
    /// `.visible` the pair is reserved outside this window, whose
    /// `viewportHeight` is then just the lines between them; under three lines
    /// neither is drawn. Either way the inset is `0` and nothing is charged here.
    ///
    /// Each indicator is charged only when it actually SHOWS: the top one
    /// when scrolled down, the bottom one when the caller says content
    /// remains below. At the very bottom the last viewport line is readable
    /// content — charging it anyway sampled one row too high, so a
    /// bottom-anchored `.scrollPosition` never reported the final row.
    ///
    /// Asked in the scroll view's content, not the stack's: the top indicator
    /// shows whenever the CONTENT is scrolled, a section's header included
    /// (``linesAbove``), and `contentBelow` counts a footer below the stack
    /// (``hasContentBelow(stackBottom:)``). The line it returns is the stack's.
    func sampleY(at unit: UnitPoint, contentBelow: Bool) -> Int {
        let topPad = (edgeInset > 0 && offset + linesAbove > 0) ? 1 : 0
        let bottomPad = (edgeInset > 0 && contentBelow) ? 1 : 0
        let usable = max(1, viewportHeight - topPad - bottomPad)
        return offset + topPad + Int((Double(usable - 1) * unit.y).rounded(.down))
    }

    /// A pending programmatic scroll (``ScrollViewProxy/scrollTo(_:anchor:)``).
    /// The stack that locates the key renders AT the request's resolved
    /// offset — so the very frame that carries the request shows the target
    /// — and reports the offset via ``ScrollContentReply/seekResolvedOffset``
    /// for the ScrollView to adopt.
    var seek: ScrollToRequest?

    /// A pending programmatic scroll on a purely HORIZONTAL scroll view, which
    /// names a column, not a row: the horizontal stack at the content's origin
    /// that holds the key reports where that column sits
    /// (``ScrollContentReply/seekResolvedColumn``), and the scroll view moves
    /// its horizontal offset to it. `nil` wherever ``seek`` is set — a view that
    /// scrolls vertically seeks rows — and whenever nothing is sought.
    var columnSeek: ScrollToRequest?

    /// Where a purely HORIZONTAL scroll view samples the column it reports to
    /// `.scrollPosition(id:)`: its horizontal offset, its viewport's width and
    /// the anchor's `x`. The horizontal stack at the content's origin reports
    /// the column there (``ScrollContentReply/anchorID``), as a vertical
    /// stack reports the row at ``reportsIDAt``. `nil` on a view that scrolls
    /// vertically, which reports rows, and when nothing is listening.
    var columnReport: ColumnReport?

    /// See ``columnReport``.
    struct ColumnReport: Hashable {
        var offset: Int
        var viewportWidth: Int
        var unitX: Double

        /// The content-space column the anchor names within the viewport.
        var sampleX: Int {
            let lastColumn = Double(max(1, viewportWidth) - 1)
            let across = (lastColumn * unitX).rounded(.down)
            return offset + Int(across)
        }
    }

    /// The scroll content's lines above the stack that consumes this window,
    /// and below it: a `Section`'s header and footer, which the section draws
    /// around a lazy stack at its own identity, so the stack is still reached
    /// from the content by single-child steps and still bands itself. `0` for a
    /// stack that is the whole content.
    ///
    /// The section hands its content this window moved into the stack's
    /// coordinates (``beneath(linesAbove:linesBelow:reply:)``) and moves the
    /// reply back into its own. Until it did, the stack banded itself as if it
    /// were all the content: under a header every row was drawn a line below
    /// where the window put it and the content's last line was never shown,
    /// and over a footer the scroll view took the stack's height for the
    /// content's and never showed the footer.
    ///
    /// These are what the stack cannot see and a seek, the read-back sample and
    /// a held row must: whether the content is scrolled at all, whether any of
    /// it lies below the viewport, and how far it can scroll — each asked of
    /// the content (``sampleY(at:contentBelow:)``,
    /// ``offset(realising:targetY:rowHeight:stackHeight:)``,
    /// ``scrollableOffsets(stackHeight:)``). Asked of the stack alone, a `.top`
    /// seek to the first row under a header left it under the "more above"
    /// indicator, and a seek could not scroll the header or the footer into
    /// view. The anchored window reads ``linesBelow`` at its end as well: the
    /// footer, not the viewport's bottom, is where a jump to the end puts the
    /// last row, and a footer taller than the viewport may take that row off
    /// screen.
    var linesAbove = 0
    var linesBelow = 0

    /// Whether the stack that consumes this window reports its rows' or
    /// columns' extents (``ScrollContentReply/targetLayoutRows``,
    /// ``ScrollContentReply/targetLayoutColumns``) — when it is marked
    /// with `scrollTargetLayout()`. Asked only by a scroll view with a scroll
    /// target behaviour, which is what settles on them
    /// (``ViewAlignedScrollTargetBehavior``); every other scroll view pays
    /// nothing for it.
    var reportsTargetLayout = false

    /// Whether the stack that consumes this window reports its rows' or
    /// columns' extents and how to name each (``ScrollContentReply/targetVisibleRows``,
    /// ``ScrollContentReply/targetVisibleColumns``, ``ScrollContentReply/targetIDs``),
    /// marked or not — for the scroll view to tell
    /// `onScrollTargetVisibilityChange` which it shows. Asked only by a
    /// scroll view such an observer is stated above.
    var reportsTargetVisibility = false

    /// What the stack that consumes this window does about the row at the
    /// viewport's top (``ScrollWindowHold``): nothing, keep track of it, or
    /// keep track of it and hold it in place this frame. The scroll view
    /// decides, being the one that knows what else moves its offset — it
    /// holds nothing while at its top, while following its tail, for a seek
    /// or a position request, or for a change made under "no adjustment" —
    /// and asks a frame's first drawing to hold, and any later drawing of the
    /// same frame only to keep track. A window made by anything else (a test
    /// injecting one) asks nothing.
    var topRowHold = TopRowHold.off

    /// Whether any of the scroll content lies below the viewport, for a stack
    /// whose own content ends at `stackBottom` (in its coordinates): its rows,
    /// or what is drawn below it (``linesBelow``).
    func hasContentBelow(stackBottom: Int) -> Bool {
        offset + viewportHeight < stackBottom + linesBelow
    }

    /// The offsets the scroll content can take, in the stack's coordinates:
    /// from the top of what is drawn above the stack to the viewport's last
    /// full screen of what is drawn below it.
    func scrollableOffsets(stackHeight: Int) -> ClosedRange<Int> {
        -linesAbove...max(-linesAbove, stackHeight + linesBelow - viewportHeight)
    }

    /// The offset that realises `seek` for a row of `rowHeight` whose top is at
    /// `targetY`, both in the stack's coordinates — asked of the whole scroll
    /// content (``ScrollToRequest/windowOffset(targetY:rowHeight:currentOffset:viewportHeight:totalHeight:)``,
    /// whose indicator headroom and clamp are the content's) and answered in
    /// the stack's.
    func offset(
        realising seek: ScrollToRequest, targetY: Int, rowHeight: Int, stackHeight: Int
    ) -> Int {
        seek.windowOffset(
            targetY: targetY + linesAbove, rowHeight: rowHeight,
            currentOffset: offset + linesAbove, viewportHeight: viewportHeight,
            totalHeight: linesAbove + stackHeight + linesBelow) - linesAbove
    }

    /// This window as content drawn `above` lines further down, with `below`
    /// lines drawn under it, sees it — a section's content, between its header
    /// and its footer — answering into `reply`.
    func beneath(linesAbove above: Int, linesBelow below: Int, reply: ScrollContentReply?) -> Self {
        var window = self
        window.offset -= above
        window.linesAbove += above
        window.linesBelow += below
        window.reply = reply
        return window
    }
}

/// What a windowed stack does about the row at the top of the viewport — see
/// ``ScrollContentWindow/topRowHold``.
enum TopRowHold: UInt8, Sendable, Hashable {
    /// Nothing, and what is remembered is left as it is: the scroll view keeps
    /// its offset in lines (``ScrollWindowHold/offset``), or does not scroll
    /// vertically.
    case off

    /// Remember which row is at the top, so a later frame can hold it, but
    /// move nothing this frame — asked too of every drawing of a frame after
    /// its first (a snap or a re-glue moved the offset after it), so the row
    /// remembered is the one the frame ends up showing.
    case tracking

    /// Move the offset by however far the content above moved the row
    /// remembered at the top, so it keeps its line.
    case holding
}

/// The Stage-6 reply channel from a windowed stack back to its ScrollView:
/// reference semantics deliberately — the environment value travels down,
/// the slice report travels back up within the same render call. Main-loop
/// rendering only (`@unchecked`: never crosses threads).
final class ScrollContentReply: @unchecked Sendable, Hashable {
    /// Content-space y of the first line the buffer holds.
    var sliceOriginY: Int?
    /// The full content height the slice was cut from (estimated for
    /// never-measured suffixes — the §3 scrollbar trade).
    var sliceTotalHeight: Int?
    /// Whether ``sliceTotalHeight`` involves ESTIMATED extents (the anchored
    /// path's unmeasured remainder at the running pitch average, and its
    /// estimate-drifted absolute origin). The ScrollView surfaces this in
    /// the "N more" indicators — "~200M more below" — so the chrome doesn't
    /// assert precision the geometry doesn't have. The uniform path's
    /// arithmetic totals are hypothesis-exact and leave this `false`.
    var sliceTotalIsEstimate = false
    /// Whether the slice starts with the stack's first row, and whether it
    /// ends with its last: what a view drawing lines of its own around the
    /// stack reads to know whether they join the band (`ScrollWindowRelay`).
    /// The origin cannot say it: the anchored window places its rows from an
    /// anchor, by estimate — a row held by `.anchorPosition(.row)` among them
    /// — so its first row need not sit at 0, nor the row at 0 be its first.
    var sliceHoldsFirstRow = false
    var sliceHoldsLastRow = false
    /// The id of the row under ``ScrollContentWindow/reportsIDAt``, when one
    /// was asked for and the provider has ids to give. This is the READ half
    /// of `.scrollPosition(id:)`: the seek machinery matches on stringified
    /// keys, but a binding has to be handed the value back.
    var anchorID: AnyHashable?

    /// The window offset the stack rendered at in answer to
    /// ``ScrollContentWindow/seek`` — the ScrollView adopts it as its
    /// scroll position. `nil` when there was no request or the key wasn't
    /// found (an unknown id is a no-op, as in SwiftUI).
    var seekResolvedOffset: Int?

    /// Whether ``seekResolvedOffset`` is the top-row hold's
    /// (``ScrollContentWindow/topRowHold``): the content above the rows on
    /// screen changed and the offset moved with it, at no one's request. The
    /// scroll view adopts it as it adopts a seek's, but still reveals a focus
    /// move made in the same frame, which a seek's offset or a designated
    /// row's overrules.
    var resolvedOffsetIsHold = false

    /// Reports `offset`, when there is one, as the offset the stack rendered
    /// at (``seekResolvedOffset``), and whether it is the top-row hold's.
    func reportResolvedOffset(_ offset: Int?, isHold: Bool) {
        guard let offset else { return }
        seekResolvedOffset = offset
        resolvedOffsetIsHold = isHold
    }

    /// The content lines a FULL-HEIGHT reply drew for real, when it drew only
    /// some: the full walk under 256 rows (`renderViewportWindow`) returns the
    /// whole canvas, but only the rows around the offset it was given are
    /// drawn and the rest are blank placeholders. A slice needs no such
    /// report — its buffer IS the band — so this is set only when
    /// ``sliceOriginY`` is not.
    ///
    /// What lets the ScrollView see that an offset it moved AFTER the render —
    /// the bottom re-glue on a terminal that shrank, a focus snap — shows lines
    /// the canvas never drew, and draw them (`coverSnappedViewport`). Without
    /// it that frame showed blank lines where the rows belong, and no later
    /// frame came to draw them unless something else changed.
    ///
    /// Open-ended past the last row (`Int.max`): below it there is nothing to
    /// draw, so a line there is drawn correctly by being blank.
    var drawnLines: Range<Int>?

    /// The extents of the rows of a stack marked with `scrollTargetLayout()`,
    /// in the content's coordinates, when the window asked
    /// (``ScrollContentWindow/reportsTargetLayout``): every row where the
    /// stack knows every row's place — a uniform stack's arithmetic, the full
    /// walk's slots, an eager stack's layout — and the band's rows on the
    /// anchored path, which knows no more.
    var targetLayoutRows: TargetLayoutSpans?

    /// The extents of the columns of a horizontal stack marked with
    /// `scrollTargetLayout()` — eager or lazy, which both lay every column out
    /// — in the content's coordinates, when the window asked.
    var targetLayoutColumns: TargetLayoutSpans?

    /// The extents of the rows of the stack that is the content, marked or
    /// not, each with its ordinal, when the window asked
    /// (``ScrollContentWindow/reportsTargetVisibility``): what the scroll view
    /// measures against its viewport for `onScrollTargetVisibilityChange`.
    /// As ``targetLayoutRows`` reports them, which the anchored window knows
    /// only for its band — the rows on screen.
    var targetVisibleRows: TargetLayoutSpans?

    /// The same for the columns of a horizontal stack.
    var targetVisibleColumns: TargetLayoutSpans?

    /// A relay a wrapper drawing lines around its content set up on its way
    /// down (`PaddingModifier`), waiting for the wrapper to answer it once
    /// its content has drawn — the wrapper's two passes share this reply and
    /// nothing else.
    var pendingRelay: ScrollWindowRelay?

    /// The id of the row or column at an ordinal of ``targetVisibleRows`` or
    /// ``targetVisibleColumns`` — its element's `id`, or its `.id(_:)` tag
    /// (`StackRowIDs`) — asked only for the ones on screen.
    var targetIDs: (@MainActor (Int) -> AnyHashable?)?

    /// Where the column ``ScrollContentWindow/columnSeek`` names sits, in the
    /// content's coordinates — `nil` when nothing was sought or no column
    /// holds the key (an unknown id is a no-op, as in SwiftUI).
    var seekResolvedColumn: TargetLayoutSpans.Span?

    /// Whether this render refuted what the content's measure answered with
    /// before it: the uniform window's hypothesis that every row is as tall as
    /// the first (`renderUniformSeekWindow`). The canvas the ScrollView offered
    /// was that measure's height, so the lines past it — the true height's
    /// excess — were cut from the buffer, and an offset the render resolved
    /// among them was clamped back into the canvas: in 200 rows of one line
    /// with row 190 sixty lines tall, `scrollTo(191)` came to rest in row
    /// 190, and row 191 was never shown. The ScrollView measures again and
    /// draws once more (`renderedContent`).
    var measureWentStale = false

    static func == (lhs: ScrollContentReply, rhs: ScrollContentReply) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

// MARK: - Scroll-To Requests

/// One programmatic scroll request: the target row's stable identity key
/// (a `ForEach` element id, stringified exactly as identity keys are) and
/// the SwiftUI-parity anchor. Created by ``ScrollViewProxy/scrollTo(_:anchor:)``,
/// parked on the ``ScrollViewHandler`` until the next render pass, then
/// carried down inside ``ScrollContentWindow``.
package struct ScrollToRequest: Sendable, Hashable {
    /// The target row's stable identity key.
    package var key: String

    /// Where the target lands in the viewport: `nil` is SwiftUI's "minimal
    /// movement to make it visible — none if it already is"; otherwise the
    /// anchor's `y` aligns the row's unit point with the viewport's
    /// (0 = top, 0.5 = centre, 1 = bottom).
    package var anchor: UnitPoint?

    /// One row of headroom per edge when the ScrollView's "N more
    /// above/below" indicators can replace the viewport's first/last line
    /// (drawn, and drawn OVER the content: not a scrollbar, and not the pair
    /// `.visible` reserves outside it) — without it, a `.top` seek lands
    /// the target exactly under the indicator. Stamped by the ScrollView;
    /// the reveal snap applies the same reservation.
    var topInset = 0
    var bottomInset = 0

    /// The horizontal offset that realises this request for a column of
    /// `width` cells whose leading edge sits at content-space `targetX`, in a
    /// viewport `viewportWidth` wide over content `totalWidth` wide, clamped to
    /// the scrollable range: the anchor's `x` aligns the column's unit point
    /// with the viewport's (0 = leading, 0.5 = centre, 1 = trailing), and no
    /// anchor moves as little as shows the whole column — not at all if it
    /// already shows. A horizontal view draws no indicator over its first or
    /// last column, so nothing is reserved for one.
    func columnOffset(targetX: Int, width: Int, currentOffset: Int, viewportWidth: Int, totalWidth: Int) -> Int {
        let raw: Int
        if let anchor {
            raw = targetX - Int((Double(viewportWidth - width) * anchor.x).rounded())
        } else if targetX < currentOffset {
            raw = targetX
        } else if targetX + width > currentOffset + viewportWidth {
            raw = targetX + width - viewportWidth
        } else {
            raw = currentOffset
        }
        return max(0, min(raw, max(0, totalWidth - viewportWidth)))
    }

    /// The window offset that realises this request for a row of
    /// `rowHeight` cells whose top sits at content-space `targetY`,
    /// clamped to the scrollable range. Shared by every seek path so the
    /// anchor semantics cannot drift between them.
    func windowOffset(
        targetY: Int, rowHeight: Int, currentOffset: Int,
        viewportHeight: Int, totalHeight: Int
    ) -> Int {
        // Indicator headroom mirrors the reveal snap: a pad is charged only
        // when that edge's indicator will actually show at the destination
        // (offset 0 has no "more above"; the very bottom no "more below").
        let topPad = (topInset > 0 && targetY > 0) ? 1 : 0
        let bottomBase = targetY + rowHeight - viewportHeight
        let bottomPad = (bottomInset > 0 && bottomBase + viewportHeight < totalHeight) ? 1 : 0
        let raw: Int
        if let anchor {
            let slack = viewportHeight - topPad - bottomPad - rowHeight
            raw = targetY - topPad - Int((Double(slack) * anchor.y).rounded())
        } else {
            // Minimal movement: visible means within the CURRENT frame's
            // indicator-clipped band, exactly as the reveal fire condition
            // defines it.
            let topShown = (topInset > 0 && currentOffset > 0) ? 1 : 0
            let bottomShown =
                (bottomInset > 0 && currentOffset + viewportHeight < totalHeight) ? 1 : 0
            if targetY < currentOffset + topShown {
                raw = targetY - topPad
            } else if targetY + rowHeight > currentOffset + viewportHeight - bottomShown {
                raw = bottomBase + bottomPad
            } else {
                raw = currentOffset
            }
        }
        return max(0, min(raw, max(0, totalHeight - viewportHeight)))
    }
}
