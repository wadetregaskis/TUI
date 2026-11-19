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
    /// dispatcher is gone — built once per walk by its two callers, which is
    /// why this is private. Row state behaves as for any other
    /// rendered-but-off-screen row; neither the real ring nor any live input
    /// service is touched, and no `onAppear` runs.
    /// Returns `nil` when nothing within `cap` rows registers; with no cap,
    /// the walk goes on to the end of `rows`.
    private func nearestFocusableRow(
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
    private func probeContext(_ context: RenderContext) -> RenderContext {
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

    /// The focusable row nearest this stack's `edge`, which the focus comes
    /// into the stack at from just past that edge — from outside the scroll
    /// view or from a neighbour in a pulled column — or `nil` when no row has
    /// anything to focus.
    ///
    /// Walked in from the edge row by row, with no cap, however far the first
    /// row that registers a focusable lies, and holding the frame while it
    /// does (owner, 2026-11-17: synchronous, no time cap, nothing carried to a
    /// later frame; revisit only with a real case that needs it). The
    /// continuations beside the focused row keep their cap: they run on every
    /// frame the focus is in the stack, this only on the frames the focus
    /// stands just outside it.
    ///
    /// Two things keep the walk from being repeated for nothing:
    /// - A stack with nothing to focus is walked once, not on every Tab past
    ///   it: the walk that finds nothing has asked every row, and the answer
    ///   is kept for the rows' data (``StackWindowState/focuslessRows``, by
    ///   ``StackWindowState/rowsVersion``) until it changes. Rows that only
    ///   grew (a log, `0..<n` with `n` rising) walk only the rows they gained.
    ///   A row that comes to hold a focusable with its data unchanged (one
    ///   enabled by state outside the rows) is not seen until then. Rows
    ///   with no data signature (data that is not `Equatable`, a flow
    ///   layout's lines) are kept by their count, since nothing else names
    ///   them: walked again on every frame, a flow of 10,000 items under a
    ///   focused scroll view built all 10,000 for every wheel step.
    /// - A row found is kept for the rows' data too
    ///   (``StackWindowState/edgeStopsByVersion``): the walk is asked on every
    ///   frame the focus stands beside the stack (owner, 2026-11-18: "(b)", the
    ///   walk made before the key), and walked each time it went from the edge
    ///   to the row again. Only that row is asked again, to see it still has
    ///   something to focus; a row before it that comes to have something with
    ///   the data unchanged is not seen until the data changes, as for a stack
    ///   with nothing to focus. Rows with no data signature are walked each
    ///   time.
    /// - The scroll view may draw its content more than once in a frame (a
    ///   reveal, a band that did not cover the offset), and each drawing asks
    ///   again: the answer is kept for the frame
    ///   (``StackWindowState/edgeStopsOfFrame``).
    func edgeFocusStop(
        _ edge: VerticalEdge, count: Int, child: (Int) -> ChildView, width: Int, viewportHeight: Int,
        state: StackWindowState, rows: AnyEquatableBox?, context: RenderContext
    ) -> Int? {
        guard count > 0 else { return nil }
        let version = rows.map { state.rowsVersion.token(for: $0) }
        // The rows known to have nothing to focus: all of them, or the ones
        // these rows began with.
        var known = 0
        if let kept = state.focuslessRows {
            if kept.version == version, version != nil || kept.count == count { return nil }
            if let rows, let keptRows = kept.rows, kept.count <= count, rows.extends(keptRows) { known = kept.count }
        }
        let frame = context.environment.focusManager?.focusRenderGeneration
        if let frame, let kept = state.edgeStopsOfFrame, kept.frame == frame, kept.count == count,
            let stop = kept.stops[edge]
        {
            return stop
        }
        let isolated = probeContext(context)
        let direction = edge == .top ? 1 : -1
        var stop: Int?
        if let version, let kept = state.edgeStopsByVersion[edge], kept.version == version, kept.count == count {
            // The row found for these rows, if it still has something to focus.
            stop = nearestFocusableRow(
                from: kept.stop - direction, direction: direction, within: kept.stop..<(kept.stop + 1), cap: 1,
                child: child, width: width, viewportHeight: viewportHeight, isolated: isolated)
        }
        if stop == nil {
            stop = nearestFocusableRow(
                from: edge == .top ? known - 1 : count, direction: direction, within: known..<count, cap: nil,
                child: child, width: width, viewportHeight: viewportHeight, isolated: isolated)
        }
        if stop == nil { state.focuslessRows = (version, rows, count) }
        state.edgeStopsByVersion[edge] = version.flatMap { version in stop.map { (version, count, $0) } }
        if let frame {
            var kept = state.edgeStopsOfFrame.flatMap { $0.frame == frame && $0.count == count ? $0 : nil }
                ?? (frame: frame, count: count, stops: [:])
            kept.stops[edge] = .some(stop)
            state.edgeStopsOfFrame = kept
        }
        return stop
    }

    /// The row of this stack's a seek names: by its key, or — a focus reveal
    /// (``ScrollToRequest/focusID``) — the row the focused control lies in,
    /// by its route (``targetOrdinal(for:children:state:context:)``).
    func seekOrdinal(
        _ seek: ScrollToRequest, children: ChildViewCollection, state: StackWindowState, context: RenderContext
    ) -> Int? {
        guard let focusID = seek.focusID else {
            return resolveOrdinal(forKey: seek.key, children: children, state: state)
        }
        return targetOrdinal(for: focusID, children: children, state: state, context: context)
    }

    /// The ordinal of the row a focus ID addresses below this stack: memo
    /// hit, else one key scan (never builds a row view). Shared by the
    /// uniform and anchored paths (targets, seeks, and ring continuation).
    /// An explicit ID is found by where its control registered
    /// (``focusAddress(_:belowStackPath:context:)``).
    func targetOrdinal(
        for focusID: String?, children: ChildViewCollection,
        state: StackWindowState, context: RenderContext
    ) -> Int? {
        guard let focusID else { return nil }
        let stackPath = context.identity.path
        let address = Self.focusAddress(focusID, belowStackPath: stackPath, context: context)
        guard let key = Self.rowKey(inFocusID: address, belowStackPath: stackPath),
            let ordinal = resolveOrdinal(forKey: key, children: children, state: state)
        else { return nil }
        return Self.memberOrdinal(near: ordinal, key: key, addressedBy: address, children: children)
    }

    /// What finds the control `focusID` names below the stack at `stackPath`:
    /// the id itself when it embeds the stack's path, as a default id does
    /// (`"button-<path>"`), else the identity path the control last
    /// registered at (``FocusManager/identityPath(of:)``).
    ///
    /// An explicit `.focusID(_:)` embeds no path, and found by the id alone a
    /// row whose control had one was never found: neither the focused row's
    /// neighbours nor the rows past a run with nothing to focus were drawn for
    /// it, so the arrows and Tab left the stack early for the control outside
    /// it (found by the geometric arrows' lane, 2026-11-17). Its registration
    /// knows where it is.
    static func focusAddress(_ focusID: String, belowStackPath stackPath: String, context: RenderContext) -> String {
        guard !focusID.contains(stackPath), let focusManager = context.environment.focusManager else { return focusID }
        return focusManager.identityPath(of: focusID)
    }

    /// The ordinal, among the children keyed `key` around `ordinal`, of the
    /// one `focusID` addresses.
    ///
    /// A key names one child for a row of one view, and this is `ordinal`
    /// after two key reads. The views of a `ForEach` row of several (decisions
    /// B15) share their row's key, each at an identity of its own below the
    /// row's, so the run of them is walked and the one whose identity the ID
    /// names is taken: the key alone named the run's first, or whichever the
    /// ordinal memo last saw, and the focused view itself went unrendered —
    /// so it registered nothing, and the focus moved to a row in the band.
    static func memberOrdinal(
        near ordinal: Int, key: String, addressedBy focusID: String, children: ChildViewCollection
    ) -> Int {
        let sharesBefore = ordinal > 0 && children.key(at: ordinal - 1) == key
        let sharesAfter = ordinal + 1 < children.count && children.key(at: ordinal + 1) == key
        guard sharesBefore || sharesAfter else { return ordinal }
        var start = ordinal
        while start > 0, children.key(at: start - 1) == key { start -= 1 }
        var member = start
        while member < children.count, children.key(at: member) == key {
            if let identity = children[member].pinnedIdentity,
                FocusManager.focusID(focusID, addressesSubtreeAt: identity.path)
            {
                return member
            }
            member += 1
        }
        return ordinal
    }
}

// MARK: - Beside the focus, in a pulled column

@MainActor extension _VStackCore {
    /// The children of a pulled column that stand beside the focused control,
    /// by the edges of theirs it stands past (``ScrollContentWindow/focusBeyond``):
    /// the children before and after the one it lies in, and the first or last
    /// when the column itself stands beside it (`beyond`, from the column
    /// above). Each draws its focusable nearest the focus, off its band if need
    /// be, so Tab and Shift-Tab step into it as they would were it drawn whole.
    func pulledFocusNeighbours(
        frame: PulledColumnFrame, beyond: VerticalEdge.Set, context: RenderContext
    ) -> [Int: VerticalEdge.Set] {
        var neighbours = Self.edgeChildren(beyond, count: frame.rowCount)
        let count = frame.rowCount
        guard let focusID = context.environment.focusManager?.currentFocusedID,
            let focused = pulledChild(holding: focusID, frame: frame, context: context)
        else { return neighbours }
        if focused > 0 { neighbours[focused - 1, default: []].insert(.bottom) }
        if focused + 1 < count { neighbours[focused + 1, default: []].insert(.top) }
        return neighbours
    }

    /// The children of a pulled column the focus comes into by an edge of
    /// theirs (``ScrollContentWindow/focusEntry``), walked inward from it
    /// (``entryWalk(from:_:frame:viewportHeight:focusManager:)``): from
    /// outside the scroll view, by the column's own edge; past the child the
    /// focus lies in, by the top (bottom) of the children after (before) it,
    /// where last frame's ring says Tab (Shift-Tab) from the focused control
    /// leaves that child (owner, 2026-11-18: "(b)", the walk made before the
    /// key); and in the frame after a Tab that left a control in one of its
    /// children for one outside that child, likewise. A Tab coming in passes
    /// every child with nothing to focus, so a lazy stack under a header with
    /// nothing to focus — `VStack { Text("Header"); LazyVStack { … } }` — walks
    /// in from its edge as it does when it is the content itself: handed only
    /// to the column's first child, the edge reached the header, and Tab
    /// stopped on the scroll view. A header with a control keeps the edge to
    /// itself, so the focus stays on the control Tab lands on; and from that
    /// control the stack below is handed the edge before the next Tab, which
    /// lands on the row it finds.
    func entryChildren(
        _ edges: VerticalEdge.Set, frame: PulledColumnFrame, viewportHeight: Int, context: RenderContext
    ) -> [Int: VerticalEdge.Set] {
        let count = frame.rowCount
        guard count > 0, let focusManager = context.environment.focusManager else {
            return Self.edgeChildren(edges, count: count)
        }
        var children: [Int: VerticalEdge.Set] = [:]
        let inward = { (start: Int, edge: VerticalEdge) in
            for ordinal in self.entryWalk(
                from: start, edge, frame: frame, viewportHeight: viewportHeight, focusManager: focusManager)
            {
                children[ordinal, default: []].insert(VerticalEdge.Set(edge))
            }
        }
        if edges.contains(.top) { inward(0, .top) }
        if edges.contains(.bottom) { inward(count - 1, .bottom) }
        if let focused = focusManager.currentFocusedID,
            let holder = pulledChild(holding: focused, frame: frame, context: context)
        {
            let exits = focusManager.lastFrameTabExits(
                fromSubtreeAt: frame.child(at: holder).identity(under: frame.context).path)
            if exits.contains(.top) { inward(holder + 1, .top) }
            if exits.contains(.bottom) { inward(holder - 1, .bottom) }
        }
        if let move = focusManager.tabMoveIntoThisFrame,
            let left = pulledChild(holding: move.from, frame: frame, context: context),
            focusManager.currentFocusedID.flatMap({ pulledChild(holding: $0, frame: frame, context: context) }) != left
        {
            let edge: VerticalEdge = move.forward ? .top : .bottom
            inward(move.forward ? left + 1 : left - 1, edge)
            focusManager.noteArrival(into: context.identity.path, by: edge)
        }
        return children
    }

    /// The children of a pulled column a Tab coming in by `edge` reaches from
    /// `start` inward, up to and including the first with something to focus:
    /// one that had something last frame
    /// (``FocusManager/heldFocusableLastFrame(inSubtreeAt:)``), or one asked
    /// as a row of a stack's walk is (``nearestFocusableRow``). A pulled child
    /// is handed the edge, to walk its own rows in from it, and the walk goes
    /// on past it when it had nothing to focus last frame; a child with
    /// nothing to focus is passed by and not drawn. However many children
    /// that passes (LAZY-EDGE, owner 2026-11-17: no cap).
    ///
    /// Kept for the children's data (``StackWindowState/entryWalks``, by
    /// ``StackWindowState/rowsVersion``), since it is asked on every frame the
    /// focus stands beside the column: a column of ten thousand lines of text
    /// under a focused button asked each of them every frame. A child that
    /// comes to have something to focus with the data unchanged is not seen
    /// until the data changes, as for a stack's rows (``edgeFocusStop``).
    /// Children with no data signature, a column of a few views, are walked
    /// each time.
    private func entryWalk(
        from start: Int, _ edge: VerticalEdge, frame: PulledColumnFrame, viewportHeight: Int,
        focusManager: FocusManager
    ) -> [Int] {
        let state = frame.state
        let version = frame.children.dataSignature.map { state.rowsVersion.token(for: $0) }
        let key = StackWindowState.EntryWalkStart(start: start, edge: edge)
        if let version, let kept = state.entryWalks, kept.version == version, let walk = kept.walks[key] {
            return walk
        }
        let count = frame.rowCount
        let step = edge == .top ? 1 : -1
        var isolated: RenderContext?
        var reached: [Int] = []
        var ordinal = start
        while (0..<count).contains(ordinal) {
            let path = frame.child(at: ordinal).identity(under: frame.context).path
            if focusManager.heldFocusableLastFrame(inSubtreeAt: path) {
                reached.append(ordinal)
                break
            }
            if frame.isPulled(ordinal) {
                reached.append(ordinal)
            } else {
                let probe = isolated ?? probeContext(frame.context)
                isolated = probe
                if nearestFocusableRow(
                    from: ordinal - step, direction: step, within: ordinal..<(ordinal + 1), cap: 1,
                    child: { frame.child(at: $0) }, width: frame.proposal.width ?? frame.context.availableWidth,
                    viewportHeight: viewportHeight, isolated: probe) != nil
                {
                    reached.append(ordinal)
                    break
                }
            }
            ordinal += step
        }
        if let version {
            var walks = state.entryWalks.flatMap { $0.version == version ? $0.walks : nil } ?? [:]
            walks[key] = reached
            state.entryWalks = (version, walks)
        }
        return reached
    }

    /// A column's first child for its top edge, and its last for its bottom.
    static func edgeChildren(_ edges: VerticalEdge.Set, count: Int) -> [Int: VerticalEdge.Set] {
        var children: [Int: VerticalEdge.Set] = [:]
        guard count > 0 else { return children }
        if edges.contains(.top) { children[0, default: []].insert(.top) }
        if edges.contains(.bottom) { children[count - 1, default: []].insert(.bottom) }
        return children
    }

    /// The child of a pulled column the control `focusID` names lies in: found
    /// by its key, or — a column of a few children not keyed, `VStack {
    /// header; LazyVStack; footer }` — by its path. Past the windowing
    /// threshold, unkeyed, it is not looked for.
    func pulledChild(holding focusID: String, frame: PulledColumnFrame, context: RenderContext) -> Int? {
        let stackPath = context.identity.path
        let address = Self.focusAddress(focusID, belowStackPath: stackPath, context: context)
        guard address.contains(stackPath) else { return nil }
        if let ordinal = targetOrdinal(for: address, children: frame.children, state: frame.state, context: context) {
            return ordinal
        }
        guard frame.rowCount <= Self.anchoredWindowThreshold else { return nil }
        return (0..<frame.rowCount).first {
            FocusManager.focusID(address, addressesSubtreeAt: frame.child(at: $0).identity(under: frame.context).path)
        }
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

// MARK: - The row a focus ID addresses

@MainActor extension _VStackCore {
    /// The slot index of the row whose subtree a focus ID addresses, when the
    /// addressed control lives under one of this stack's rows: by the path a
    /// default (identity-path-derived) ID embeds, or the one an explicit ID's
    /// control registered at (``focusAddress(_:belowStackPath:context:)``).
    ///
    /// Cheap rejection first: unless that path is below this stack's own,
    /// no row can match and no per-row path is materialised. When it does,
    /// the scan renders each row's identity path — O(rows) string work, only
    /// on frames where focus (or a pending target) is inside this stack.
    func rowIndex(
        addressedBy focusID: String?, slots: [RowSlot], context: RenderContext
    ) -> Int? {
        guard let focusID else { return nil }
        let stackPath = context.identity.path
        let address = Self.focusAddress(focusID, belowStackPath: stackPath, context: context)
        guard address.contains(stackPath) else { return nil }
        return slots.firstIndex { slot in
            FocusManager.focusID(address, addressesSubtreeAt: slot.child.identity(under: context).path)
        }
    }
}
