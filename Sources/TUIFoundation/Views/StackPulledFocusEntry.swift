//  🖥️ TUI — A Terminal UI framework for Swift
//  StackPulledFocusEntry.swift
//
//  The children of a pulled column beside the focus, and the ones the focus
//  comes into by an edge of theirs, walked inward from it (split out of
//  `StackFocusReach.swift`, whose probe the walk asks with).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

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
