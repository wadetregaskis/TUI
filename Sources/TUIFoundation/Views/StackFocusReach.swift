//  🖥️ TUI — A Terminal UI framework for Swift
//  StackFocusReach.swift
//
//  Ring continuation past non-focusable rows for the windowed stack paths.
//  The focus ring holds exactly what REGISTERED this pass, in render order,
//  and a windowed stack renders only the band plus the focused row's
//  immediate neighbours — so when a neighbour renders without registering
//  (a disabled control, a plain-text row), the ring simply ends at the
//  focused row and Tab wraps back into the band instead of advancing: every
//  row beyond the non-focusable run is unreachable by keyboard.
//
//  Whether a row registers is only observable by rendering it (disabled-ness
//  lives in the row's own content and environment), and the ring's order is
//  registration order — so the next focusable row must be found BEFORE the
//  main render sweep and injected into it at its ascending position. The
//  probe below renders candidate rows against a scratch FocusManager (real
//  state, no ring side effects) and throwaway key channels (no input side
//  effects either) until one registers.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

@MainActor extension _VStackCore {
    /// How far past the focused row the continuation probe reaches, per
    /// direction, when the focus is IN the stack. A run of more than this many
    /// consecutive non-focusable rows stops the Tab walk at the run (focus
    /// then wraps) — pathological, and the cap keeps the per-frame probe
    /// bounded. The walk in from an edge, when the focus stands just outside
    /// the stack, has no cap (``edgeFocusStop(_:count:child:width:viewportHeight:state:rows:context:)``).
    static var focusReachProbeCap: Int { 64 }

    /// The nearest row beyond `origin` in `direction` (+1 down, −1 up) that
    /// registers a focusable when rendered, within `cap` rows — the focus
    /// ring's required next stop. Probing renders rows against a scratch
    /// `FocusManager` over `isolated` (``probeContext(_:)``), whose key
    /// channels and lifecycle are already throwaways and whose mouse
    /// dispatcher is gone — built once per walk by its callers (the
    /// continuations here, the edge walk in `StackEdgeFocusStop.swift` and a
    /// pulled column's entry walk in `StackPulledFocusEntry.swift`), not once
    /// per row. Row state behaves as for any other
    /// rendered-but-off-screen row; neither the real ring nor any live input
    /// service is touched, and no `onAppear` runs.
    /// Returns `nil` when nothing within `cap` rows registers; with no cap,
    /// the walk goes on to the end of `rows`.
    func nearestFocusableRow(
        from origin: Int, direction: Int, within rows: Range<Int>, cap: Int?,
        child: (Int) -> ChildView, width: Int, viewportHeight: Int,
        isolated: RenderContext
    ) -> Int? {
        var probe = origin + direction
        var steps = 0
        while rows.contains(probe), steps < cap ?? Int.max {
            let scratch = FocusManager()
            // The scratch manager must not FOCUS anything. It is throwaway, but
            // the rows it registers are not: the probe shares the live
            // `StateStorage`, so each one resolves the app's real persisted
            // `Focusable` — and `register` auto-focuses the first focusable
            // element on an empty manager, which called `onFocusReceived()` on
            // a row nobody had focused, every frame, for as many rows as the
            // probe walked. A `TextField` reached that way began editing.
            scratch.suppressesAutoFocus = true
            var probeContext = isolated
            probeContext.environment.focusManager = scratch
            _ = child(probe).render(
                width: width, height: viewportHeight, context: probeContext)
            // Asked directly now, rather than inferred from the side effect of
            // an auto-focus. A disabled control still REGISTERS (with
            // `canBeFocused` false — the ring filters it at move time), so
            // "registered anything" would be the wrong question.
            if scratch.hasFocusableElement { return probe }
            probe += direction
            steps += 1
        }
        return nil
    }

    /// The focused row's continuation stops in both directions — the rows
    /// the render sweep must include (at their ascending positions) so the
    /// ring continues past any non-focusable run adjacent to focus.
    func focusRingContinuations(
        focusedOrdinal: Int?, count: Int,
        child: (Int) -> ChildView, width: Int, viewportHeight: Int,
        context: RenderContext
    ) -> [Int] {
        guard let focused = focusedOrdinal else { return [] }
        let isolated = probeContext(context)
        var stops: [Int] = []
        for direction in [-1, 1] {
            if let stop = nearestFocusableRow(
                from: focused, direction: direction, within: 0..<count, cap: Self.focusReachProbeCap,
                child: child, width: width, viewportHeight: viewportHeight,
                isolated: isolated)
            {
                stops.append(stop)
            }
        }
        return stops
    }

    /// The context a probe renders rows in: every channel a key can arrive on
    /// goes to a throwaway, not just the focus ring. A probe is a RENDER —
    /// `isMeasuring` is false — so each row it asks performs every
    /// render-pass registration it has, and the live dispatcher keeps every
    /// handler it is handed until the next frame. With only the focus manager
    /// swapped, a row the walk merely counted (never drawn, never in the
    /// sweep) held a live `onKeyEvent`, a `.hidden()` button's
    /// `.keyboardShortcut` — hidden registers no focusable, so the walk goes
    /// straight past it — and `.statusBarItems` that stood on the bar whenever
    /// no drawn row declared its own, all for the whole frame. And the focused
    /// row's neighbours, which the probe always asks first and the sweep draws
    /// anyway, registered twice: a declining handler beside the focus ran
    /// twice per keypress. Built once per walk, not per probed row: what these
    /// collect is never read.
    ///
    /// The rows' lifecycle too (``RenderContext/withThrowawayLifecycle()``):
    /// a row the walk looked at is not on screen, and its `onAppear` — a "load
    /// more" on a stack's last row — must not run because Tab looked for a
    /// row to land on (LAZY-EDGE, owner 2026-11-17).
    func probeContext(_ context: RenderContext) -> RenderContext {
        var isolated = context.withThrowawayKeyChannels().withThrowawayLifecycle()
        isolated.environment.mouseEventDispatcher = nil
        // A row's `.toolbar` too: its items are drawn by the window's bars,
        // which would draw them live for a row the frame never shows.
        isolated.environment.windowChrome = nil
        return isolated
    }

    /// The rows the render sweep draws off the band for the focus ring, in
    /// order: the focused row's continuations
    /// (``focusRingContinuations(focusedOrdinal:count:child:width:viewportHeight:context:)``),
    /// and the rows the focus comes into this stack at from just past its
    /// edges (``RingEdges``) — its last focusable row past its end, its first
    /// before its top, however far, from a pulled column's neighbour
    /// (``ScrollContentWindow/focusBeyond``) or from outside the scroll view
    /// (``ScrollContentWindow/focusEntry``) alike, by the one walk
    /// (``edgeFocusStop(_:count:child:width:viewportHeight:state:rows:context:)``).
    func focusRingStops(
        focusedOrdinal: Int?, edges: RingEdges,
        count: Int, child: (Int) -> ChildView, width: Int, viewportHeight: Int, context: RenderContext
    ) -> [Int] {
        var stops = focusRingContinuations(
            focusedOrdinal: focusedOrdinal, count: count, child: child, width: width,
            viewportHeight: viewportHeight, context: context)
        // A neighbour's edge walks in as far as the way in from outside the
        // scroll view does (LAZY-EDGE, owner 2026-11-17: no cap) — Tab from a
        // header's button went no further than 64 rows into the stack under
        // it — and, like it, before the key only where last frame's Tab order
        // says the key comes in. Where the rows on screen have nothing to
        // focus, the column hands the stack the edge as an entry instead,
        // where Tab from the focused control would pass over it
        // (`entryChildren`; owner, 2026-11-18: "(b)").
        var walked = edges.entry
        let beyond = edges.beyond.subtracting(edges.entry)
        if !beyond.isEmpty, let focusManager = context.environment.focusManager {
            walked.formUnion(beyond.intersection(focusManager.lastFrameTabEdges(intoSubtreeAt: context.identity.path)))
        }
        for edge in VerticalEdge.allCases where walked.contains(VerticalEdge.Set(edge)) {
            guard let stop = edgeFocusStop(
                edge, count: count, child: child, width: width, viewportHeight: viewportHeight,
                state: edges.state, rows: edges.rows, context: context)
            else { continue }
            stops.append(stop)
            if edges.entry.contains(VerticalEdge.Set(edge)) {
                // Where a Tab that came into the content by this edge goes on to.
                context.environment.focusManager?.noteEdgeStop(
                    edge, row: child(stop).identity(under: context).path, stackPath: context.identity.path)
            }
        }
        return Set(stops).sorted()
    }
}

// MARK: - The edges a stack is come into by

/// The edges of a windowed stack the focus is coming into it by, from its
/// window (``ScrollContentWindow/focusBeyond``, ``ScrollContentWindow/focusEntry``),
/// with the stack's window state and its rows' data signature, which keep a
/// stack with nothing to focus from being walked again.
struct RingEdges {
    let beyond: VerticalEdge.Set
    let entry: VerticalEdge.Set
    let state: StackWindowState
    let rows: AnyEquatableBox?

    init(_ window: ScrollContentWindow, state: StackWindowState, rows: AnyEquatableBox?) {
        beyond = window.focusBeyond
        entry = window.focusEntry
        self.state = state
        self.rows = rows
    }

    /// Whether the focus comes in by any edge.
    var isEmpty: Bool { beyond.isEmpty && entry.isEmpty }
}

// MARK: - The exact walk's ring stops

@MainActor extension _VStackCore {
    /// The exact walk's rows drawn off its window for the focus ring, marked
    /// in `rendersRow`: the focused row's continuations — a disabled
    /// neighbour registers nothing, so the nearest focusable row past it must
    /// render too or Tab dead-ends at the run — and the row the focus comes
    /// into the stack at from just past an edge of it
    /// (``ScrollContentWindow/focusBeyond``), as on the other two paths.
    /// These rows carry no data signature to keep a stack with nothing to
    /// focus by, so such a stack is walked each time.
    ///
    /// - Returns: The rows marked here and by nothing before, which are drawn
    ///   only for the ring and which nobody sees
    ///   (``RenderContext/withThrowawayLifecycle()``).
    func markRingStops(
        _ rendersRow: inout [Bool], slots: [RowSlot], focusedID: String?, window: ScrollContentWindow, width: Int,
        context: RenderContext, childContext: RenderContext
    ) -> Set<Int> {
        var unseen: Set<Int> = []
        for stop in focusRingStops(
            focusedOrdinal: rowIndex(addressedBy: focusedID, slots: slots, context: childContext),
            edges: RingEdges(window, state: uniformWindowState(context: context), rows: nil),
            count: slots.count, child: { slots[$0].child }, width: width, viewportHeight: window.viewportHeight,
            context: childContext)
        where !rendersRow[stop] {
            rendersRow[stop] = true
            unseen.insert(stop)
        }
        return unseen
    }
}
