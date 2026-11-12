//  🖥️ TUI — A Terminal UI framework for Swift
//  StackAnchoredWindow.swift
//
//  The variable-height anchor walk of "Locating things without drawing
//  them" (§5e, §6a): when rows are NOT uniform, the scroll position is a
//  persisted anchor — a row ordinal plus the cells of it hidden above the
//  viewport top — and scroll input is applied as a DELTA walked in row
//  space: one line up looks at one row. The frame then fills outward from
//  the anchor, measuring only the rows it draws. Estimated extents cover
//  only what is never measured — the blank suffix that feeds the scrollbar
//  and the seek target of a big jump — so an estimate being wrong can move
//  the thumb, never the content: the anchor row is pinned to the offset the
//  clip will show, by construction.
//
//  Small stacks keep the exact full walk (their O(N) is trivial and their
//  absolute space stays exact); this path takes over above
//  `anchoredWindowThreshold` rows, where O(N)-per-frame is the bug.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// MARK: - Per-frame measurer

/// One anchored frame's measuring state: memoises each touched row's pitch
/// (height + the spacing charged before a non-first row), keeps the built
/// child for the render step, and feeds every measurement into the running
/// estimate. One measure per touched row per frame. The walk itself — the
/// anchor moved by a scroll, the rows filled outward from it — is the fill
/// engine's (`ScrollColumnFill.swift`), which this frame answers as a column.
@MainActor
private final class AnchoredWindowFrame {
    let children: ChildViewCollection
    let spacing: Int
    let state: StackWindowState
    /// The scroll position this walk reads and moves.
    let anchor: ScrollContentAnchor
    let proposal: ProposedViewSize
    let context: RenderContext

    private(set) var sawSpacer = false
    private var pitchCache: [Int: Int] = [:]
    private var widthCache: [Int: Int] = [:]
    private var built: [Int: ChildView] = [:]

    init(
        children: ChildViewCollection, spacing: Int, state: StackWindowState, anchor: ScrollContentAnchor,
        proposal: ProposedViewSize, context: RenderContext
    ) {
        self.children = children
        self.spacing = spacing
        self.state = state
        self.anchor = anchor
        self.proposal = proposal
        self.context = context
    }

    func pitch(of ordinal: Int) -> Int {
        if let cached = pitchCache[ordinal] { return cached }
        let child = children[ordinal]
        if child.isSpacer { sawSpacer = true }
        let measured = child.measure(proposal: proposal, context: context)
        // Keep a measure-only row's memo entries alive across the pass GC:
        // an off-window row touched only by this pitch walk never renders,
        // so nothing else marks it — and unmarked entries are pruned at the
        // end of every pass, forcing a full re-measure every frame. Bounded
        // by the rows this frame touches, unlike marking inside the memo
        // itself (which is O(tree) on eager stacks).
        context.renderCache?.markActive(child.identity(under: context))
        // AFTER-spacing semantics: a row's pitch is its height plus the gap
        // BELOW it (every row but the last has one). `fill` advances by the
        // pitch of the row it just placed, so the gap must ride the row
        // ABOVE it — the before-spacing convention dropped exactly the
        // row 0 → row 1 gap (row 0's pitch carried no spacing) and shifted
        // the whole tail up one line per spacing unit.
        let value = max(1, measured.height) + (ordinal < children.count - 1 ? spacing : 0)
        pitchCache[ordinal] = value
        widthCache[ordinal] = measured.width
        built[ordinal] = child
        state.recordMeasuredPitch(value)
        // Filed, as the uniform render files the rows it draws, so a row that
        // fills goes on counting at the measure's ask after it scrolls away
        // (`anchoredSizeThatFits`): the measure samples only the first rows.
        if !context.isMeasuring { state.rowWidths.note(ordinal: ordinal, size: measured) }
        return value
    }

    func child(at ordinal: Int) -> ChildView {
        built[ordinal] ?? children[ordinal]
    }

    /// The measured width of a row the pitch walk has already touched.
    ///
    /// What a `.gradientExtent(.subtree)` ramp aligns a row by: the RENDERED
    /// width does not exist until after the render the ramp has to colour, and
    /// the pitch walk measured this one anyway. `nil` for a row this frame
    /// never measured — an off-band graft, whose cells are not drawn.
    func measuredWidth(of ordinal: Int) -> Int? {
        widthCache[ordinal]
    }
}

// The column the fill engine walks (`ScrollColumnFill.swift`): the stack's rows,
// measured as the walk reaches them.
extension AnchoredWindowFrame: ScrollFillColumn {
    var rowCount: Int { children.count }

    func key(at ordinal: Int) -> String? { children.key(at: ordinal) }

    func firstOrdinal(forKey key: String) -> Int? { children.firstOrdinal(forKey: key) }

    var ladder: [String: Int] { state.rowOrdinalMemo }

    var estimatedPitch: Int { state.estimatedPitch(spacing: spacing) }

    /// Every row priced at the running pitch, less the gap after the last.
    var estimatedTotal: Int { children.count * estimatedPitch - spacing }
}

// MARK: - The anchored render

@MainActor extension _VStackCore {
    /// Row counts above this use the anchored walk once uniform arithmetic
    /// is unavailable; at or below it, the exact full walk is cheap and
    /// keeps small stacks byte-exact in absolute space.
    static var anchoredWindowThreshold: Int { 256 }

    /// How many leading rows the anchored estimate measures for its pitch (and,
    /// within the budget's reach, its width). The uniform seek's width records
    /// seed from the same count, so the two paths answer alike.
    static var anchoredWidthSampleCount: Int { 16 }

    /// Applies a DESIGNATED row anchor (`.anchorPosition(.row(id))`), which
    /// replaces the implicit top-visible anchor, and returns its key (or `nil`
    /// when no designation is in force).
    ///
    /// The key is re-asserted every frame — that stickiness IS the hold, since
    /// `rebindAnchor` then finds wherever the row has moved to, so an insert or
    /// delete around it shifts the scroll position rather than the row. When
    /// the designation CHANGES the row is *adopted*: it keeps the screen line
    /// it currently occupies (`adoptDesignatedRow`), so designating — or, via
    /// the §1.2 shadow switch, selecting — a visible row does not jerk the
    /// viewport to the top.
    ///
    /// A row that is not in the data is not designated yet: nothing is held,
    /// the frame is drawn as with no designation, and the row is adopted on
    /// the frame it arrives, as the other two paths adopt it
    /// (`offsetHoldingDesignatedRow`) — and as a `scrollTo` of it moves
    /// nothing. Held from the start, the row at the anchor stood in for it at
    /// the viewport's top, and since a designation owns the anchor, the offset
    /// no longer moved it: a `.scrollPosition` scroll moved the scrollbar and
    /// not the rows. Once adopted, a row that leaves the data is held by its
    /// nearest neighbour (the ladder, `rebindAnchor`).
    private func applyDesignatedAnchor(
        frame: AnchoredWindowFrame, state: StackWindowState,
        window: ScrollContentWindow, context: RenderContext, mode: ScrollAnchorMode
    ) -> String? {
        guard mode == .row,
            let key = context.environment.anchorPosition?.wrappedValue?.rowKey
        else {
            state.designatedAnchorKey = nil
            return nil
        }
        // A change made under "no adjustment" lets the held row go: it is
        // adopted afresh below, walked to from the anchor as last drawn —
        // still on the row's old ordinal, not yet re-bound — so it is held on
        // the line the change moved it to.
        let letGo = state.letGoOfHeldRow(key, context: context)
        if state.designatedAnchorKey != key {
            guard
                let designated = resolveOrdinal(
                    forKey: key, children: frame.children, state: state)
            else {
                state.designatedAnchorKey = nil
                return nil
            }
            state.designatedAnchorKey = key
            adoptDesignatedRow(
                frame: frame, state: state, window: window, designated: designated, letGo: letGo)
        }
        frame.anchor.key = key
        return key
    }

    /// Adopts a newly designated row: it becomes the anchor at the screen line
    /// it currently occupies, encoded as a SIGNED `within` —
    /// negative meaning the anchor sits that many lines BELOW the viewport top,
    /// which `fill` renders by walking upward from it. (The implicit top anchor
    /// keeps a non-negative `within`: cells hidden ABOVE the top.)
    ///
    /// `letGo` is whether the row was already held and a change made under "no
    /// adjustment" let it go (`StackWindowState/letGoOfHeldRow`).
    private func adoptDesignatedRow(
        frame: AnchoredWindowFrame, state: StackWindowState,
        window: ScrollContentWindow, designated: Int, letGo: Bool
    ) {
        let line = adoptedHeldLine(
            frame: frame, state: state, window: window, designated: designated, letGo: letGo)
        frame.anchor.ordinal = designated
        frame.anchor.within = -line
    }

    /// The screen line the designated row occupies right now, so adoption holds
    /// it there rather than at the top. Walked from the current anchor — bounded,
    /// since a visible row is at most a viewport of rows away. A row farther than
    /// that is off-screen: there is no line to preserve, so it is revealed at the
    /// top edge (minimal-movement reveal, as `scrollTo(_:anchor: nil)` does). The
    /// result is clamped into the viewport, reserving the indicator lines, so an
    /// off-by-a-little visible row still lands on a real line.
    ///
    /// A row a change under "no adjustment" let go (`letGo`) and carried that far
    /// is left on the line in view nearest where the change put it — the bottom
    /// one when the rows it put above the row moved it down — as the other two
    /// paths leave it (`offsetHoldingDesignatedRow`) and as the walk's clamp
    /// leaves a row it carried a little way off. Put on the top line, as it
    /// was, a row that rows inserted above had carried below the screen landed
    /// at the bottom on the other paths and at the top on this one.
    ///
    /// The anchor is walked from as `rebindAnchor` will clamp it, into the rows
    /// there now: adoption runs before that clamp, and the anchor is still last
    /// frame's. Walked from as it was, a change that took rows away left it
    /// past the end of the data, and the walk asked for a row that is not
    /// there — a trap: the last of 300 rows held, two rows above it removed and
    /// the row let go (`letGoOfHeldRow`), or another row designated in the same
    /// change.
    private func adoptedHeldLine(
        frame: AnchoredWindowFrame, state: StackWindowState,
        window: ScrollContentWindow, designated: Int, letGo: Bool
    ) -> Int {
        let anchor = min(max(0, frame.anchor.ordinal), frame.children.count - 1)
        func lastLine() -> Int {
            let rowHeight =
                frame.pitch(of: designated) - (designated < frame.children.count - 1 ? spacing : 0)
            return max(window.edgeInset, window.viewportHeight - rowHeight - window.edgeInset)
        }
        guard abs(designated - anchor) <= window.viewportHeight + 2 else {
            return letGo && designated > anchor ? lastLine() : window.edgeInset
        }
        var line = -frame.anchor.within
        if designated >= anchor {
            for ordinal in anchor..<designated { line += frame.pitch(of: ordinal) }
        } else {
            for ordinal in designated..<anchor { line -= frame.pitch(of: ordinal) }
        }
        return min(max(line, window.edgeInset), lastLine())
    }

    /// Sticky top for a below-top hold: a held row cannot sit lower on screen
    /// than the content above it can fill. Bounded by the held line (≤ one
    /// viewport).
    ///
    /// When the rows above it run out before its line, every one of them has
    /// been measured, so the row's place in the stack is exact — `available`
    /// lines down — and so is the offset that holds it on its line: that place
    /// less the line, as the other two paths hold a row
    /// (`offsetHoldingDesignatedRow`), but no higher than the content's top,
    /// the first line of what the scroll content draws above this stack — a
    /// section's header (`ScrollContentWindow/scrollableOffsets(stackHeight:)`).
    /// There the row rides up until the content's first line meets the
    /// viewport's, and is re-anchored where it lands. The offset is returned
    /// for the scroll view to adopt. Riding up at the offset it had, the row
    /// kept the rows above it on screen but not the offset: scrolled down when
    /// rows above it were deleted, the first row was drawn where the offset
    /// was — under "N more lines above", with nothing above it. And ridden up
    /// by the header's lines on screen at the offset it was handed, a row held
    /// under a header of two lines or more is drawn off its line — rows placed
    /// above the stack's top, which the fill drops — when a row is inserted
    /// above it or the header grows, and a scroll that takes a header line off
    /// screen rides the row up rather than leaving it on its line.
    ///
    /// When the rows above the held row fill its line, the topmost of them
    /// must start at the stack's top or below it — the highest the fill places
    /// a row — so an offset that would put it higher is raised to where it
    /// starts at the top, and returned likewise. Left alone, the fill's floor
    /// stopped that row, the band started lower than the viewport's top, and
    /// the scroll view showed it from its first line: the held row sat that
    /// many lines above its line. A row designated off screen from the top,
    /// under the "more above" line, showed on line 0 when the row above it was
    /// taller than one line, and under the indicator itself once the view
    /// scrolled a line; under a section's header (a negative offset, none of
    /// the header on screen once the rows fill the line) it showed on line 0
    /// whatever the row above.
    private func clampDesignatedHold(
        frame: AnchoredWindowFrame, state: StackWindowState, window: inout ScrollContentWindow
    ) -> Int? {
        sinkDesignatedHold(frame: frame, state: state, window: window)
        let heldLine = -frame.anchor.within
        var available = 0
        var ordinal = frame.anchor.ordinal - 1
        while ordinal >= 0, available < heldLine {
            available += frame.pitch(of: ordinal)
            ordinal -= 1
        }
        if available < heldLine {
            let offset = max(available - heldLine, -window.linesAbove)
            frame.anchor.within = offset - available
            guard offset != window.offset else { return nil }
            window.offset = offset
            return offset
        }
        guard window.offset < available - heldLine else { return nil }
        window.offset = available - heldLine
        return window.offset
    }

    /// Sticky bottom, the other end of the same rule: a held row cannot sit
    /// higher on screen than the rows below it — with what the scroll content
    /// draws below this stack, a section's footer — can fill, down to the
    /// viewport's bottom. Within a screen of the end of the data there are not
    /// enough of them, and the row rides down until the content's last line
    /// meets the viewport's, where the other two paths' clamp to the scrollable
    /// range puts it (`offsetHoldingDesignatedRow`). It is re-anchored there,
    /// as they re-anchor, and does not spring back up when rows arrive below
    /// it. Bounded by the viewport. Runs first, so the rows above fill the line
    /// it lands on (`clampDesignatedHold`).
    ///
    /// Held higher, the band ended above the viewport's bottom, the content
    /// the scroll view was told of was shorter than the offset needed, and it
    /// pulled the offset back and drew the band from its first line: a row
    /// designated within a screen of the end, from near the top, was drawn off
    /// its line over blank lines, with nothing to scroll.
    private func sinkDesignatedHold(
        frame: AnchoredWindowFrame, state: StackWindowState, window: ScrollContentWindow
    ) {
        let needed = window.viewportHeight + frame.anchor.within
        var below = window.linesBelow
        var ordinal = frame.anchor.ordinal
        while ordinal < frame.children.count, below < needed {
            below += frame.pitch(of: ordinal)
            ordinal += 1
        }
        if below < needed { frame.anchor.within = below - window.viewportHeight }
    }

    /// Resolves a pending `scrollTo` against the anchored geometry: pins the
    /// anchor to the TARGET (§5e — seek by anchor, not by absolute offset) and
    /// re-aims `window.offset`, returning the offset to report (or `nil` when
    /// there is no request or its key is absent). The estimated y positions
    /// only the scrollbar and the clamp; the target row itself lands exactly
    /// where the anchor walk puts it, estimates notwithstanding — and near the
    /// top, where the walk can be overruled, its y is exact (`seekTargetY`),
    /// and so the clamp and a minimal-movement seek's edge are read from it.
    ///
    /// `anchorFollowsOffset` is whether the anchor walk to the offset follows
    /// the seek (`advanceAnchor`) — every frame but one whose designated row
    /// owns the anchor, which a near seek leaves alone and a far one pins at
    /// the target's top, as they always have (`anchorSeekTarget`).
    private func resolveAnchoredSeek(
        frame: AnchoredWindowFrame, state: StackWindowState,
        window: inout ScrollContentWindow, children: ChildViewCollection,
        anchorFollowsOffset: Bool
    ) -> Int? {
        guard let seek = window.seek else { return nil }
        window.seek = nil
        guard let ordinal = seekOrdinal(seek, children: children, state: state, context: frame.context)
        else {
            guard seek.focusID == nil else { return nil }
            return resolveNestedAnchoredSeek(
                seek, frame: frame, state: state, window: &window, anchorFollowsOffset: anchorFollowsOffset)
        }
        // Nil anchor near the window resolves in WALKED row space: an
        // already-visible target moves NOTHING, a nearby one moves minimally.
        // The estimate path below judges visibility by estimate-space y against
        // the walked offset — two coordinate spaces that drift apart — and
        // teleported the view (and the scrollbar) for a plainly on-screen row.
        if seek.anchor == nil,
            let near = nilAnchorSeekOffset(
                target: ordinal, frame: frame, state: state,
                window: window, seek: seek, count: children.count)
        {
            // A move pins the anchor to the target, as a far seek does, so the
            // walk to the offset after the seek (`advanceAnchor`) starts from
            // the row this placed exactly. Started from the anchor the target
            // was measured from, the move — up to twenty rows, of any height —
            // could be more than four screens, which that walk takes for a
            // scrollbar jump and places by the running pitch: row 278 of rows
            // of two lines, from the end, was drawn a line low, and on the
            // frame the list grew onto this path, rows 226 to 229 were.
            if anchorFollowsOffset, near.offset != window.offset {
                anchorSeekTarget(
                    ordinal, top: near.targetTop, offset: near.offset, frame: frame,
                    state: state, children: children)
            }
            window.offset = near.offset
            return near.offset
        }
        let estimate = state.estimatedPitch(spacing: spacing)
        let targetY = seekTargetY(ordinal: ordinal, estimate: estimate, frame: frame, window: window)
        let rowHeight = frame.pitch(of: ordinal) - (ordinal < children.count - 1 ? spacing : 0)
        // What the seek asks of the target's place is read in its coordinates,
        // which near the top are exact (`seekTargetY`):
        //
        // - The clamp. The stack runs on from the target at the running pitch.
        //   Priced whole at that pitch, it could end above the target's exact
        //   place: the offset was clamped back, and the walk from the target
        //   took the gap for a jump and placed the rows by estimate
        //   (`advanceAnchor`). A `.top` seek to row 7 under seven rows of sixty
        //   lines, the rest priced at one, drew rows 29 to 36.
        // - A minimal-movement seek's edge. A far target (`nilAnchorSeekOffset`
        //   answers a near one) is off screen: above it when its ordinal is
        //   before the anchor's, below it when after (the anchor at this
        //   frame's offset, walked there first: `renderAnchoredWindow`).
        //   Moving as little as it can puts it on that edge — `.top` or
        //   `.bottom`, whose offsets are the minimal movement's
        //   (`ScrollToRequest/windowOffset`).
        //   Compared with the offset, which is at the pitch, the exact place
        //   fell on the wrong side of it: from line 30 (rows 30 to 37), row 7
        //   under seven rows of ten lines was put on the bottom line, and
        //   under rows of five, on line 5, the offset unmoved.
        var request = seek
        if request.anchor == nil { request.anchor = ordinal < frame.anchor.ordinal ? .top : .bottom }
        let newOffset = window.offset(
            realising: request, targetY: targetY, rowHeight: rowHeight,
            stackHeight: max(children.count * estimate, targetY + (children.count - ordinal) * estimate)
                - spacing)
        // Under a designated row the hold follows, not the walk
        // (`clampDesignatedHold`), and the target stands at its top as before.
        anchorSeekTarget(
            ordinal, top: targetY, offset: anchorFollowsOffset ? newOffset : targetY, frame: frame,
            state: state, children: children)
        window.offset = newOffset
        return newOffset
    }

    /// A seek whose key lies below one of this stack's rows, drawn whole
    /// (`StackNestedSeek.swift`): aimed at the key's place in that row, the
    /// row then anchored as a seek's own target is. A minimal-movement seek to
    /// a place on screen moves nothing; off it, it moves to the edge it is
    /// past, read from the anchor as the near seek reads it.
    private func resolveNestedAnchoredSeek(
        _ seek: ScrollToRequest, frame: AnchoredWindowFrame, state: StackWindowState,
        window: inout ScrollContentWindow, anchorFollowsOffset: Bool
    ) -> Int? {
        let children = frame.children
        guard
            let target = NestedSeek.target(
                holding: seek.key, count: children.count, child: frame.child(at:),
                width: frame.proposal.width ?? frame.context.availableWidth,
                rowHeight: { frame.pitch(of: $0) - ($0 < children.count - 1 ? spacing : 0) }, context: frame.context)
        else { return nil }
        let estimate = state.estimatedPitch(spacing: spacing)
        let rowTop = seekTargetY(ordinal: target.ordinal, estimate: estimate, frame: frame, window: window)
        let current = frame.viewportLine(ofRow: target.ordinal, viewportHeight: window.viewportHeight) + target.y
        var request = seek
        if request.anchor == nil {
            let line = NestedSeek.line(
                for: seek, height: target.height, current: current, viewportHeight: window.viewportHeight)
            guard line != current else { return window.offset }
            request.anchor = current < line ? .top : .bottom
        }
        let newOffset = window.offset(
            realising: request, targetY: rowTop + target.y, rowHeight: target.height,
            stackHeight: max(children.count * estimate, rowTop + (children.count - target.ordinal) * estimate)
                - spacing)
        anchorSeekTarget(
            target.ordinal, top: rowTop, offset: anchorFollowsOffset ? newOffset : rowTop, frame: frame,
            state: state, children: children)
        window.offset = newOffset
        return newOffset
    }

    /// Re-binds the anchor when something holds a row: a designated row, by
    /// its key (`rebindAnchor`); with none — a designation naming no row is
    /// none (`applyDesignatedAnchor`) — the row at the top, when the scroll
    /// view asks for the top-row hold this frame
    /// (``ScrollContentWindow/topRowHold``), and the anchor is left on its
    /// ordinal otherwise.
    ///
    /// The row at the top is the one every path remembers when it draws a
    /// frame (``StackWindowState/heldTopRow``), found where the change put it
    /// (``StackWindowState/heldTopRowPlace(in:)``): it becomes the anchor, with
    /// as many of its lines above the viewport's top as the last frame showed —
    /// whichever path drew it. Held by this walk's own anchor, a stack that
    /// crossed 256 rows lost the row the exact walk had remembered, and one
    /// that crossed back was held from a frame drawn long before.
    ///
    /// The offset follows the row by the running pitch, so the scrollbar and
    /// "N more above" keep up with the rows the change put above it — exact
    /// when it is the first row — and the anchor's `derivedOffset` is the remembered
    /// top moved with it, so the walk sees only a scroll made since the last
    /// frame. Returns that offset, to report, or `nil`.
    private func rebindingAnchor(
        frame: AnchoredWindowFrame, state: StackWindowState, window: inout ScrollContentWindow,
        designatedKey: String?
    ) -> Int? {
        frame.rebindAnchor(holdsRow: designatedKey != nil)
        let children = frame.children
        guard designatedKey == nil, window.topRowHold == .holding, window.seek == nil, window.offset >= 0,
            let held = state.heldTopRow,
            let place = state.heldTopRowPlace(in: RowKeys(count: children.count, key: { children.key(at: $0) }))
        else { return nil }
        let moved = place.ordinal - held.ordinal
        frame.anchor.ordinal = place.ordinal
        frame.anchor.within = held.top - held.y
        let followed: Int
        if moved == 0 {
            followed = window.offset
        } else if place.ordinal == 0 {
            followed = frame.anchor.within
        } else {
            followed = max(1, window.offset + moved * state.estimatedPitch(spacing: spacing))
        }
        frame.anchor.derivedOffset = held.top + followed - window.offset
        guard followed != window.offset else { return nil }
        window.offset = followed
        return followed
    }

    /// Makes a seek's target the anchor: its top at `top`, and `offset` the
    /// offset the seek moved to. The anchor walk that follows (`advanceAnchor`)
    /// moves from there to the offset, so the lines of the target the offset
    /// puts above the viewport's top — the end of a row taller than the screen,
    /// which a `.bottom` or `.center` seek shows — are hidden here, and the
    /// walk only moves up from the target's top, at most a screen.
    ///
    /// Left at the target's top, the walk moved down those lines, and past four
    /// screens took them for a scrollbar jump and placed the rows by the running
    /// pitch (`advanceAnchor`): a `.bottom` seek to the end of a sixty-line row
    /// showed one-line rows past it.
    ///
    /// An offset past the target's end — a custom anchor whose y is below 0, or
    /// above 1 on a row taller than the screen (`windowOffset` does not clamp
    /// it) — names rows after it, which the target's lines cannot hide: its
    /// pitch clamped them away and the target was drawn on line 0. The anchor
    /// is then the row after it, so the walk covers only the lines past the
    /// target, by `advanceAnchor`'s own rule: exactly within four screens, by
    /// estimate beyond, as any jump that far is.
    private func anchorSeekTarget(
        _ ordinal: Int, top: Int, offset: Int, frame: AnchoredWindowFrame,
        state: StackWindowState, children: ChildViewCollection
    ) {
        let within = max(0, offset - top)
        let pitch = frame.pitch(of: ordinal)
        if within >= pitch, ordinal < children.count - 1 {
            frame.anchor.ordinal = ordinal + 1
            frame.anchor.key = children.key(at: ordinal + 1)
            frame.anchor.within = 0
            frame.anchor.derivedOffset = top + pitch
            return
        }
        frame.anchor.ordinal = ordinal
        frame.anchor.key = children.key(at: ordinal)
        frame.anchor.within = within
        frame.anchor.derivedOffset = top + within
    }

    /// Where a seek takes its target row's top to be: at the running pitch
    /// (§5e), except for a row fewer than a viewport of rows from the top,
    /// whose rows above are few and measured exactly — as the end is placed
    /// exactly from the last row up (`tailAnchor(endingAt:)`).
    ///
    /// Only those rows can have their seek's offset above the stack's top,
    /// where the anchor walk that places the target by exact pitches from its
    /// priced place (`advanceAnchor`) is overruled: an offset there shows the
    /// lines drawn above the stack — a section's header — and takes the rows
    /// from row 0. Priced from rows taller than the running pitch, a `.bottom`
    /// or `.center` seek to such a row landed in the header, and the row was
    /// drawn where rows 0 up put it, off screen: row 3 under three rows of five
    /// lines, at 8 lines, was nowhere on screen. With nothing above the stack
    /// the offset clamps to its top, and the walk from the priced place drew
    /// the row lines above where a column of the same rows puts it.
    private func seekTargetY(
        ordinal: Int, estimate: Int, frame: AnchoredWindowFrame, window: ScrollContentWindow
    ) -> Int {
        guard ordinal < window.viewportHeight else { return ordinal * estimate }
        return (0..<ordinal).reduce(0) { $0 + frame.pitch(of: $1) }
    }

    /// Renders the window by anchored outward fill, or returns `nil` when a
    /// touched row is a spacer (spacer distribution needs the full walk).
    func renderAnchoredWindow(
        _ children: ChildViewCollection, window: ScrollContentWindow, context: RenderContext
    ) -> FrameBuffer? {
        let state = uniformWindowState(context: context)
        guard !children.isEmpty else { return FrameBuffer() }

        // An explicit `.alignmentGuide` needs the whole run to place a row, and
        // materialising the whole run is exactly what this arithmetic path
        // exists to avoid. Decline instead, and let the exact slot walk — which
        // measures every row anyway — do the placement. Row 0 answers for all of
        // them: this path only runs over a uniformly keyed collection, whose
        // rows are built by one closure.
        guard !children[0].mayHaveExplicitGuide(.horizontal(alignment)) else { return nil }

        // Off-window rows leave the WINDOW, not the tree (§5h).
        context.stateStorage?.retainSubtree(context.identity)

        var childContext = context
        childContext.leaveScrollOrigin()
        let width = context.availableWidth
        let frame = AnchoredWindowFrame(
            children: children, spacing: spacing, state: state,
            // The scroll view's position, which this walk moves; its own only
            // where a window came with none (a test injecting one).
            anchor: window.anchor?.claimed(byColumn: context.identity, state: state) ?? state.ownAnchor,
            proposal: ProposedViewSize(width: width, height: nil), context: childContext)

        let declaredMode = context.environment.declaredAnchorModes.standing
        let anchorMode = ScrollAnchorMode.effective(
            boundAnchor: context.environment.anchorPosition?.wrappedValue, declared: declaredMode)
        // A stack a column pulls (``ScrollContentWindow/isPulled``) holds no
        // row of the scroll view's unless the column hands it the held row,
        // as the child the viewport's top lies in.
        let designatedKey =
            window.isPulled && !window.holdsDesignatedRow
            ? nil
            : applyDesignatedAnchor(frame: frame, state: state, window: window, context: context, mode: anchorMode)

        var window = window
        frame.enter(edgeOf: &window, estimatedEnd: frame.anchor.reportedTotal ?? frame.estimatedTotal)
        let topRowOffset = rebindingAnchor(
            frame: frame, state: state, window: &window, designatedKey: designatedKey)

        // A seek moves from the rows on screen, and reads them from the anchor:
        // a near target is walked to from it (`nilAnchorSeekOffset`), a far one
        // takes the edge its ordinal is on (`resolveAnchoredSeek`). The anchor
        // is walked to the offset below, after the seek, so until then it is
        // where the last anchored frame left it — the rows on screen only if
        // the offset has not moved since. On the frame a stack first takes
        // this path (grown past 256 rows: the exact walk keeps no anchor, so it
        // was row 0), or whose offset jumped with the seek, a `scrollTo` of a
        // far row above the screen put it on the bottom line, and of a near one
        // moved the offset away from it. So a seek's frame walks the anchor to
        // the offset first, as it would with no seek. A designated row owns the
        // anchor, and is on screen by construction.
        if designatedKey == nil, window.seek != nil {
            frame.advanceAnchor(
                to: window.offset, viewportHeight: window.viewportHeight,
                linesBelow: window.linesBelow)
        }
        let resolvedSeek = resolveAnchoredSeek(
            frame: frame, state: state, window: &window, children: children,
            anchorFollowsOffset: designatedKey == nil)

        var heldOffset: Int?
        if designatedKey == nil {
            frame.advanceAnchor(
                to: window.offset, viewportHeight: window.viewportHeight,
                linesBelow: window.linesBelow)
            frame.anchor.key = children.key(at: frame.anchor.ordinal)
        } else {
            // A DESIGNATED row owns the anchor: the scroll position follows the
            // ROW, not the other way round. So neither walk the anchor by the
            // offset delta (that is how user scrolling moves it) nor re-derive
            // the key from whatever ordinal the offset implies — both would
            // drag the anchor off the designated row every frame, which is
            // exactly what made `.row` behave as "hold the top visible row".
            // A below-top hold rides up when the content above it shrinks past
            // its held line: once the rows above it run out, its place is exact
            // and the offset is the one that holds it, the row riding up only
            // past the content's top; while they fill its line, the offset
            // moves down when they would start above the stack's top.
            // The anchor's `derivedOffset` is still synced so no phantom delta
            // accumulates if the designation is later cleared.
            heldOffset = clampDesignatedHold(frame: frame, state: state, window: &window)
            frame.anchor.derivedOffset = window.offset
        }
        if window.isPulled { window.reply?.pulledPosition = window.offset }
        var (placed, lastPlaced, bottomY) = frame.fill(window: window)
        // The rows the fill drew, before any focus target joins them.
        let drawn = ordinalSpan(of: placed.map(\.ordinal))

        // Focus / pending targets, wherever they are (§5d): estimated
        // positions relative to the anchor — the reveal snap converges on
        // them, and "already visible → do nothing" ends the chase. In band
        // mode (a reply channel) a far target must not stretch the band —
        // the gap would materialise as O(distance) blank lines — so it is
        // grafted out-of-band instead; classic mode keeps it inline in the
        // full-height canvas.
        var grafts: [(ordinal: Int, y: Int)] = []
        if let focusManager = context.environment.focusManager {
            let anchorY = window.offset - frame.anchor.within
            let estimate = state.estimatedPitch(spacing: spacing)
            let placedOrdinals = Set(placed.map(\.ordinal))
            for target in [focusManager.currentFocusedID, focusManager.pendingFocusID] {
                guard
                    let ordinal = targetOrdinal(
                        for: target, children: children, state: state, context: context),
                    !placedOrdinals.contains(ordinal)
                else { continue }
                // Clamped, never dropped: an above-window target's estimate
                // routinely goes negative, and dropping it meant the row
                // never rendered, never registered, and upward reveal never
                // happened. At y 0 the region still tells the snap "scroll
                // up", which is all convergence needs.
                let estimatedY = anchorY + (ordinal - frame.anchor.ordinal) * estimate
                if window.reply == nil {
                    placed.append((ordinal, max(0, estimatedY)))
                } else {
                    grafts.append((ordinal, max(0, estimatedY)))
                }
            }
        }
        // Ring continuation (see StackFocusReach.swift): the nearest
        // focusable row past a non-focusable run adjacent to focus must
        // render too, or Tab dead-ends at the run. Positioned like any
        // other off-window target: estimated y relative to the anchor.
        // And the row a focused control just past an edge of this stack steps
        // to (``ScrollContentWindow/focusBeyond``), the same way.
        let focusedOrdinal = targetOrdinal(
            for: context.environment.focusManager?.currentFocusedID,
            children: children, state: state, context: context)
        if focusedOrdinal != nil || window.focusBeyond != nil {
            let anchorY = window.offset - frame.anchor.within
            let estimate = state.estimatedPitch(spacing: spacing)
            let covered = Set(placed.map(\.ordinal)).union(grafts.map(\.ordinal))
            for stop in focusRingStops(
                focusedOrdinal: focusedOrdinal, beyond: window.focusBeyond, count: children.count,
                child: { frame.child(at: $0) }, width: width,
                viewportHeight: window.viewportHeight, context: childContext)
            where !covered.contains(stop) {
                let estimatedY = anchorY + (stop - frame.anchor.ordinal) * estimate
                if window.reply == nil {
                    placed.append((stop, max(0, estimatedY)))
                } else {
                    grafts.append((stop, max(0, estimatedY)))
                }
            }
        }
        // Grafts render after the band; keep them in ascending row order so
        // the focus ring (registration order) stays in data order.
        grafts.sort { $0.ordinal < $1.ordinal }
        guard !frame.sawSpacer else { return nil }

        let buffer = assembleAnchoredBuffer(
            placed: placed, grafts: grafts, lastPlaced: lastPlaced, bottomY: bottomY,
            frame: frame, window: window, width: width, context: childContext)
        // Answer the seek only on success: a nil (spacer bail) falls to the
        // exact path, which re-resolves against its own geometry. A hold that
        // moved the offset after the seek has the last word.
        if buffer != nil {
            window.reply?.reportResolvedOffset(
                heldOffset ?? resolvedSeek ?? topRowOffset, isHold: heldOffset == nil && resolvedSeek == nil)
        }
        if buffer != nil {
            recordDrawnRows(
                band: drawn, all: placed.map(\.ordinal) + grafts.map(\.ordinal), of: children, state: state,
                context: context)
            rememberAnchoredTopRow(state: state, anchor: frame.anchor, window: window, children: children)
        }
        return buffer
    }

    /// Assembles the full-height buffer: rendered rows at their y, exact
    /// blank blocks between, and the estimated suffix (exact when the fill
    /// reached the tail) that feeds contentHeight and so the scrollbar.
    /// Estimated-position rows that would overlap real ones are pushed down
    /// — their exact place is unknowable without the prefix sum nobody
    /// computes (§3).
    private func assembleAnchoredBuffer(
        placed: [(ordinal: Int, y: Int)], grafts: [(ordinal: Int, y: Int)],
        lastPlaced: Int, bottomY: Int,
        frame: AnchoredWindowFrame, window: ScrollContentWindow, width: Int,
        context: RenderContext
    ) -> FrameBuffer? {
        let state = frame.state
        var sorted = placed
        sorted.sort { $0.y < $1.y }

        // With a reply channel (Stage 6) the buffer is the rendered band
        // only; prefix/suffix become metadata. See the uniform assembly.
        // A ramp spanning this stack runs across the whole CONTENT. Every
        // number on this path is an estimate — the rows' positions from the
        // anchor outward, the height from the running pitch average (§3) — so
        // the ramp is estimated with them, and converges as the walk learns
        // the real pitch. Exact would mean the full prefix sum this path
        // exists in order not to compute.
        let gradientFrame = context.gradientContentFrame(
            width: width,
            height: max(1, frame.children.count * state.estimatedPitch(spacing: spacing)
                - (frame.children.count > 1 ? spacing : 0)))
        let drawGraft = { (ordinal: Int, y: Int) in
            self.drawAnchoredGraft(
                frame.child(at: ordinal), measuredWidth: frame.measuredWidth(of: ordinal), y: y,
                gradient: gradientFrame, width: width, viewportHeight: window.viewportHeight, context: context)
        }
        // Drawn ahead of the band, as each stands above it (`drawOffBandRow`).
        let firstPlaced = sorted.first?.ordinal ?? .min
        let drawnAbove = Dictionary(
            grafts.filter { $0.ordinal < firstPlaced }.map { ($0.ordinal, drawGraft($0.ordinal, $0.y)) },
            uniquingKeysWith: { first, _ in first })

        var result = FrameBuffer()
        let sliceOrigin = window.reply != nil ? (sorted.first?.y ?? 0) : 0
        var cursor = sliceOrigin
        var memo: [String: Int] = [:]
        // The line whose row is reported back, in this stack's coordinates,
        // and the row found there (see ``ScrollContentWindow/reportsIDAt``):
        // the first whose bottom lies past the line, as on the other two
        // paths. A line of a section's header above this stack (a negative
        // offset) reports the first row, as the exact paths do.
        let sampleY = window.sampleY(
            at: window.reportsIDAt ?? .top,
            contentBelow: lastPlaced < frame.children.count - 1
                || window.hasContentBelow(stackBottom: bottomY))
        var sampledOrdinal: Int?
        // The band's rows as placed, for a scroll view settling on them (this
        // path knows no row's place outside the band) — collected only when one
        // asks, which almost none does: `nil` otherwise.
        let spanRequest = targetSpanRequest(window: window, context: context)
        var placedSpans: [TargetLayoutSpans.Span]? = spanRequest != nil ? [] : nil
        placedSpans?.reserveCapacity(sorted.count)
        // A row the change put in fades in; one with a removal of its own
        // plays it where it was (`WindowedRowFade`), kept in the content's
        // coordinates, which the band's origin does not move.
        var fade = WindowedRowFade(context: context)
        var zOrder = WindowedZOrder()
        for (ordinal, y) in sorted {
            let rowHeight =
                frame.pitch(of: ordinal)
                - (ordinal < frame.children.count - 1 ? spacing : 0)
            let slotY = max(y, cursor)
            placedSpans?.append(.init(origin: slotY, length: rowHeight, ordinal: ordinal))
            if slotY > cursor {
                result.appendVertically(FrameBuffer(emptyWithHeight: slotY - cursor), spacing: 0)
            }
            // At the height it was measured at, not the viewport's: the pitch
            // walk measured it at its ideal height, and a row taller than the
            // viewport drawn at the viewport's was cut to its first screenful
            // and padded out with blank lines — the rest of it never drawn,
            // however far the scroll view moved over it.
            let child = frame.child(at: ordinal)
            var rendered = child.render(
                width: width, height: rowHeight,
                context: context.placingChild(
                    gradient: gradientFrame,
                    x: Self.gradientX(
                        childWidth: frame.measuredWidth(of: ordinal) ?? width,
                        extent: width, alignment: alignment),
                    y: slotY))
            rendered = fade.drawn(
                rendered, WindowedRow(child, under: context.identity, ordinal: ordinal),
                x: Self.gradientX(childWidth: rendered.width, extent: width, alignment: alignment), y: slotY
            ).horizontallyAligned(toWidth: width, alignment: alignment)
            zOrder.append(Self.slot(of: rendered, extent: rowHeight, width: width), of: child, to: &result, spacing: 0)
            // Rows are variable-height here, so unlike the uniform path this
            // cannot be a division — but the spans are being walked anyway. A
            // line in the gap between two rows belongs to the row below it;
            // taken only inside a row, that line named no row at all.
            if window.reportsIDAt != nil, sampledOrdinal == nil, sampleY < slotY + rowHeight {
                sampledOrdinal = ordinal
            }
            cursor = slotY + rowHeight
            if let key = frame.children.key(at: ordinal) { memo[key] = ordinal }
        }
        // Drawn again in ascending z-index where a drawn row has one of its
        // own (`WindowedZOrder`) — before the off-band grafts, which draw
        // nothing in the band.
        result = zOrder.finish(result, context: context)
        guard !frame.sawSpacer else { return nil }
        // A line past every row drawn lies below the last row — the fill
        // covers the viewport while rows remain — over what the scroll content
        // draws below this stack: a section's footer. It reports the last row,
        // as the other two paths clamp their sample to it; it named none, and
        // the binding kept a stale id or none.
        if window.reportsIDAt != nil, sampledOrdinal == nil {
            sampledOrdinal = sorted.last?.ordinal
        }
        for (ordinal, y) in grafts {
            // The graft's y is an ESTIMATE (ordinal distance × running pitch
            // average), and on this path's whole domain — variable-height
            // rows — it can land INSIDE the rendered band, where the grafted
            // row's hit regions would overlay a visible row's and steal its
            // clicks. An off-band row is outside the band by definition, so
            // clamp a wayward estimate to the nearest edge OUTSIDE on its
            // true side (known from the ordinal): the reveal math keeps the
            // direction and the viewport clip drops the regions, exactly as
            // the accurate-estimate case always behaved.
            var bandLocalY = y - sliceOrigin
            let bandHeight = cursor - sliceOrigin
            if ordinal < firstPlaced {
                // A full viewport height clear of the band top: the grafted
                // regions are at most viewportHeight tall (the row renders at
                // that height), so nothing can poke past 0 — a row-pitch
                // margin was not enough when the region outlived the pitch.
                bandLocalY = min(bandLocalY, -window.viewportHeight)
            } else {
                // Below — or BETWEEN placed runs, where the estimate is
                // ambiguous: out of the band is the contract either way.
                bandLocalY = max(bandLocalY, bandHeight)
            }
            graftOffBandRow(drawnAbove[ordinal] ?? drawGraft(ordinal, y), into: &result, bandLocalY: bandLocalY)
            if let key = frame.children.key(at: ordinal) { memo[key] = ordinal }
        }
        state.rowOrdinalMemo = memo
        result = fade.finish(
            drawingOver: result, shiftedUpBy: sliceOrigin, isRow: WindowedRow.isAmong(frame.children, under: context.identity))

        let remaining = frame.children.count - 1 - lastPlaced
        let estimate = state.estimatedPitch(spacing: spacing)
        // The estimate prices each remaining row at height + below-gap; the
        // actual last row has no below-gap, so an estimated suffix carries
        // one spacing too many.
        let total =
            max(cursor, bottomY) + max(0, remaining) * estimate
            - (remaining > 0 ? spacing : 0)
        frame.anchor.reportedTotal = total
        if let reply = window.reply {
            reply.sliceOriginY = sliceOrigin
            reply.sliceTotalHeight = total
            reply.sliceHoldsFirstRow = (sorted.first?.ordinal ?? 0) == 0
            reply.sliceHoldsLastRow = remaining <= 0
            // Anchored absolute space is estimate-derived: the unmeasured
            // remainder is priced at the running pitch average, and the band
            // origin itself drifts with past estimates. Even at the tail
            // (remaining == 0) the prefix above is estimated.
            reply.sliceTotalIsEstimate = true
            reportTargetLayout(
                placedSpans, request: spanRequest, children: frame.children, into: reply, context: context)
            if let sampledOrdinal {
                reply.anchorID = frame.children.reportedID(
                    at: sampledOrdinal, content: content, sectionsWhole: context.keepsSectionsWhole)
            }
        } else if total > cursor {
            result.appendVertically(FrameBuffer(emptyWithHeight: total - cursor), spacing: 0)
        }
        return result
    }

    /// Resolves a nil-anchor ("minimal movement") seek in WALKED row space,
    /// for targets near the current window: the exact pitch walk gives the
    /// target's true viewport-local position, so an already-visible target
    /// (within the indicator-clipped band, as the reveal snap defines it)
    /// moves nothing and a nearby one moves just enough. Far targets return
    /// `nil` — minimality is meaningless hundreds of rows away, and the
    /// estimate seek handles them.
    ///
    /// Returns the offset, and the target's top in the same lines, which the
    /// seek pins the anchor at (`anchorSeekTarget`).
    private func nilAnchorSeekOffset(
        target: Int, frame: AnchoredWindowFrame, state: StackWindowState,
        window: ScrollContentWindow, seek: ScrollToRequest, count: Int
    ) -> (offset: Int, targetTop: Int)? {
        let anchor = frame.anchor.ordinal
        guard abs(target - anchor) <= window.viewportHeight * 2 + 4 else { return nil }
        var y = -frame.anchor.within
        if target >= anchor {
            for ordinal in anchor..<target { y += frame.pitch(of: ordinal) }
        } else {
            for ordinal in target..<anchor { y -= frame.pitch(of: ordinal) }
        }
        let rowHeight = frame.pitch(of: target) - (target < count - 1 ? spacing : 0)

        // The indicators are the scroll content's: a section's header above
        // this stack is content above, its footer content below
        // (`ScrollContentWindow/linesAbove`, `linesBelow`).
        let above = window.linesAbove
        let topShown = (seek.topInset > 0 && window.offset + above > 0) ? 1 : 0
        var lastVisible = anchor
        var walked = -frame.anchor.within
        while lastVisible < count - 1,
            walked + frame.pitch(of: lastVisible) < window.viewportHeight
        {
            walked += frame.pitch(of: lastVisible)
            lastVisible += 1
        }
        let lastHeight =
            frame.pitch(of: lastVisible) - (lastVisible < count - 1 ? spacing : 0)
        let contentBelow =
            lastVisible < count - 1
            || walked + lastHeight + window.linesBelow > window.viewportHeight
        let bottomShown = (seek.bottomInset > 0 && contentBelow) ? 1 : 0

        // The first row's top is the stack's, 0, whatever the walk says:
        // walked from an anchor placed by an estimate, rows near the top can
        // sit a line or two off it. Under a section's header that line was the
        // header's — the seek scrolled to the first row and left the header
        // hidden, where the same seek in a column shows it. The anchor is
        // pinned there too: at the walk's place, 63 lines above the stack's
        // top after a jump near rows of ten lines, row 0 was drawn from its
        // tenth line.
        let top = target == 0 ? 0 : window.offset + y
        if y >= topShown, y + rowHeight <= window.viewportHeight - bottomShown {
            return (window.offset, top)  // fully visible: strict no-op
        }
        if y < topShown {
            let topPad = (seek.topInset > 0 && top + above > 0) ? 1 : 0
            return (max(-above, top - topPad), top)
        }
        let bottomPad =
            (seek.bottomInset > 0 && (target < count - 1 || window.linesBelow > 0)) ? 1 : 0
        return (max(-above, window.offset + y + rowHeight - window.viewportHeight + bottomPad), top)
    }

    /// `renderWindow`'s seek ladder: a pulled column's band; else, under a
    /// request, uniform arithmetic, then for large variable-height content the
    /// anchored walk (§5e); `nil` from all of them (no request, small N,
    /// spacers, a first frame with no hypothesis) leaves the exact paths.
    func renderWindowedLadder(context: RenderContext) -> FrameBuffer? {
        // Checked BEFORE `renderWindow`'s eager resolve (which would build
        // every row of a huge ForEach just to count spacers):
        // uniform arithmetic first; for large variable-height content, the
        // anchored walk (§5e); a nil from both (small N, spacers, a first
        // frame with no hypothesis) falls through to the exact paths.
        // A column holding a pulled child places its rows outward from its
        // anchor (`StackPulledColumn.swift`), whatever their count.
        if let pulled = renderPulledRows(context: context) { return pulled }
        if var window = consumableScrollWindow(context: context), !context.isMeasuring {
            let collection = resolveChildViewCollection(from: content, context: context)
            if collection.isUniformlyKeyed {
                // Both windowed paths refine the pitch this stack's measure
                // estimates unmeasured rows at, so a measure the pass memoized
                // before this render is no longer what a fresh one says. Moved
                // is rare — the rounded average of the rows touched — and then
                // the pass's sizes are dropped rather than served stale. So
                // they are when the uniform hypothesis the measure answered
                // from is refuted, once in the stack's life: the ScrollView
                // measures again (``ScrollContentReply/measureWentStale``),
                // and must not be handed the answer the render refuted.
                let state = uniformWindowState(context: context)
                let before = (state.measuredEstimate(spacing: spacing), state.broken)
                defer {
                    if (state.measuredEstimate(spacing: spacing), state.broken) != before {
                        context.renderCache?.forgetPassMeasures()
                        forgetKeptSizes(context: context)
                    }
                }
                resolveUniformPullEdge(&window, count: collection.count, state: state)
                if window.edge != .end,
                    let fast = renderUniformWindowReporting(collection, window: window, context: context)
                {
                    return fast
                }
                if collection.count > Self.anchoredWindowThreshold,
                    let anchored = renderAnchoredWindow(collection, window: window, context: context)
                {
                    return anchored
                }
            }
        }
        return nil
    }

    /// Memo hit, else one key scan (never builds a row view). Shared by the
    /// anchored and uniform paths (focus targets and scrollTo seeks alike).
    func resolveOrdinal(
        forKey key: String, children: ChildViewCollection, state: StackWindowState
    ) -> Int? {
        if let memoised = state.rowOrdinalMemo[key],
            memoised < children.count, children.key(at: memoised) == key
        {
            // The first of the views a `ForEach` row of several hands over
            // under its key (decisions B15), as the scan below finds: the memo
            // may hold any of them. One key read for a row of one view.
            var first = memoised
            while first > 0, children.key(at: first - 1) == key { first -= 1 }
            return first
        }
        return children.seekOrdinal(forKey: key)
    }
}
