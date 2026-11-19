//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusManager+TabEntry.swift
//
//  Whether the next Tab or Shift-Tab will bring the focus into a subtree from
//  outside it, asked while a frame is drawn, by the ring of the frame before.
//
//  A scroll view's windowed lazy stack draws only the rows on screen, so a
//  Tab coming into it from the control before the scroll view landed on the
//  first row on screen rather than the stack's first row (LAZY-EDGE). The
//  stack can draw its first or last focusable row off screen for the ring
//  (`StackFocusReach.swift`), but only if something tells it, before it draws,
//  that the focus is about to come in. Tab moves through the ring the frame
//  registers, which is not complete until the frame has been drawn, so the
//  question is put to last frame's ring instead (owner, 2026-11-17: "use last
//  frame's Tab order"): it differs from this frame's only by what this frame
//  has added or dropped, which is the rows the stack is about to draw. Where
//  the rows on screen have nothing to focus, the ring has nothing of the
//  stack's, and it is the control the key would land on past it that says the
//  key passes over it: the stack then walks in all the same, before the key
//  (owner, 2026-11-18: "(b)"), so the key lands on the row it finds. A Tab
//  last frame's ring could not foresee is still taken on by the frame after it
//  (`tabEntryEdges`).
//
//  Created by Wade Tregaskis
//  License: MIT

/// What the focus manager keeps between a Tab and the frame after it, for a
/// lazy stack the Tab should have come into (``FocusManager/tabEntryEdges(intoSubtreeAt:ownStopAt:)``).
struct TabEntryState {
    /// The last Tab (`forward`) or Shift-Tab, the control it left, and the
    /// render generation it was pressed in: read by the frame after it alone.
    var move: (forward: Bool, from: String, generation: UInt64)?
    /// The content the last move came into, or passed over, by `edge`, and the
    /// rows the stacks in it found nearest that edge with something to focus:
    /// the one of them first in the ring for the top edge, last for the
    /// bottom, is where the end of the pass takes the focus.
    var arrival: (content: String, edge: VerticalEdge, rows: [String])?
}

extension FocusManager {
    /// The edges of the subtree at `path` the focus is coming into it by from
    /// outside it: the edges a windowed stack in it walks in from to its first
    /// or last row with something to focus (``ScrollContentWindow/focusBeyond``).
    ///
    /// Two questions, one asked before the key and one after:
    ///
    /// - **Before** (owner, 2026-11-17: "use last frame's Tab order"; and
    ///   2026-11-18: "(b)"): would the next Tab (`.top`) or Shift-Tab
    ///   (`.bottom`) from the focused control, outside the subtree, come into
    ///   it, or pass over it? Played over last frame's ring
    ///   (``lastFrameTabEdges(intoSubtreeAt:ownStopAt:)``), it lands on a
    ///   control in the subtree, passes over a focus section of it with
    ///   nothing to focus (a section's derived id names its path), or —
    ///   where the rows on screen have nothing to focus, and the ring nothing
    ///   of the subtree's — Tab lands on the scroll view's own stop, which
    ///   registers just after its content, or Shift-Tab leaves that stop for
    ///   a control outside. The stack then walks in from that edge and draws
    ///   the row it finds for the ring, and the key lands on it: no control
    ///   is given the focus on the way.
    /// - **After**: did the Tab just pressed come in from outside, or pass
    ///   over the subtree, by the same rules played over the move it made?
    ///   Only a Tab last frame's ring could not foresee needs it: one behind
    ///   another key in the same batch of input that moved the focus or
    ///   changed the rows. The stack then walks in from that edge, and once
    ///   the walk is done the focus is taken on to the row it finds
    ///   (``resolveEdgeArrival()``), unless it is in that row already, and the
    ///   frame walked again before it is written.
    ///
    /// Asked before, a stack with nothing to focus is walked whenever the focus
    /// stands beside it — on the scroll view, or on a search field above a
    /// list of ten thousand lines of text — so its answer is kept until its
    /// rows' data changes (`_VStackCore.edgeFocusStop`): all its rows are
    /// walked once a change of data, on the first frame the focus stands
    /// beside it.
    ///
    /// The scroll view's own stop is named by where it registers, `stopPath`:
    /// a drawing of the content made again later in the frame has no handle
    /// on its id. A section given its own name is not seen through.
    func tabEntryEdges(intoSubtreeAt path: String, ownStopAt stopPath: String) -> VerticalEdge.Set {
        guard let focused = currentFocusedID, !path.isEmpty else { return [] }
        let isInside = { (focusID: String) in Self.focusID(self.identityPath(of: focusID), addressesSubtreeAt: path) }
        var edges: VerticalEdge.Set = []
        if let edge = arrivalEdge(into: path, ownStopAt: stopPath, focused: focused, isInside: isInside) {
            edges.insert(VerticalEdge.Set(edge))
            noteArrival(into: path, by: edge)
        }
        return edges.union(lastFrameTabEdges(intoSubtreeAt: path, ownStopAt: stopPath))
    }

    /// The first question of ``tabEntryEdges(intoSubtreeAt:ownStopAt:)``
    /// alone, asked before the key: would the next Tab (`.top`) or Shift-Tab
    /// (`.bottom`) from the focused control, outside the subtree at `path`,
    /// come into it, played over last frame's ring? Also asked by a stack
    /// beside the focus in a pulled column (``ScrollContentWindow/focusBeyond``),
    /// which walks in from that edge only then: where the rows on screen have
    /// nothing to focus, the frame after a Tab that passed over it walks in
    /// instead (``noteArrival(into:by:)``).
    func lastFrameTabEdges(intoSubtreeAt path: String, ownStopAt stopPath: String? = nil) -> VerticalEdge.Set {
        guard let focused = currentFocusedID, !path.isEmpty else { return [] }
        let isInside = { (focusID: String) in Self.focusID(self.identityPath(of: focusID), addressesSubtreeAt: path) }
        guard !isInside(focused), let forward = lastFrameTabStep(.forward, from: focused),
            let backward = lastFrameTabStep(.backward, from: focused)
        else { return [] }
        let comesIn = { (step: (landing: Focusable?, passed: [FocusSection])) in
            step.landing.map { isInside($0.focusID) } == true
                || step.passed.contains { Self.focusID($0.id, addressesSubtreeAt: path) }
        }
        var edges: VerticalEdge.Set = []
        if comesIn(forward) { edges.insert(.top) }
        if comesIn(backward) { edges.insert(.bottom) }
        // A Tab that would pass over the content, its rows on screen with
        // nothing to focus, as the scroll view's own stop says: it registers
        // just after the content, so Tab onto it from a control outside, or
        // Shift-Tab off it to one, passes the place the content's rows would
        // be in the ring (owner, 2026-11-18: "(b)", walk before the key).
        // Content filing its rows in a focus section of its own is seen by
        // the section instead (`comesIn`).
        if let stopPath, !previousSections.contains(where: { Self.focusID($0.id, addressesSubtreeAt: path) }) {
            let isOwnStop = { (focusID: String) in self.renderedIdentity(ofFocusID: focusID)?.path == stopPath }
            if forward.landing.map({ isOwnStop($0.focusID) }) == true { edges.insert(.top) }
            if isOwnStop(focused), let landing = backward.landing, !isOwnStop(landing.focusID) {
                edges.insert(.bottom)
            }
        }
        return edges
    }

    /// The edges by which Tab (`.top`) and Shift-Tab (`.bottom`) from the
    /// focused control, inside the subtree at `path`, would leave it for the
    /// views after it (before it), played over last frame's ring: the edge
    /// each of those views is come into by. Asked by a pulled column of the
    /// child the focus lies in (`_VStackCore.entryChildren(_:frame:viewportHeight:context:)`),
    /// whose children past it walk in from that edge before the key, up to
    /// the first with something to focus: a lazy stack under a header's
    /// button, its rows on screen with nothing to focus, is passed over by a
    /// Tab from the button, and only a walk finds its first row that has.
    func lastFrameTabExits(fromSubtreeAt path: String) -> VerticalEdge.Set {
        guard let focused = currentFocusedID, !path.isEmpty else { return [] }
        let isInside = { (focusID: String) in Self.focusID(self.identityPath(of: focusID), addressesSubtreeAt: path) }
        guard isInside(focused) else { return [] }
        var edges: VerticalEdge.Set = []
        if let landing = lastFrameTabStep(.forward, from: focused)?.landing, !isInside(landing.focusID) {
            edges.insert(.top)
        }
        if let landing = lastFrameTabStep(.backward, from: focused)?.landing, !isInside(landing.focusID) {
            edges.insert(.bottom)
        }
        return edges
    }

    /// The Tab (`forward`) or Shift-Tab pressed just before this frame, and
    /// the control it left: what a pulled column asks to see whether it
    /// passed over the children beside that control
    /// (`_VStackCore.entryChildren(_:frame:viewportHeight:context:)`). `nil` in any other
    /// frame.
    var tabMoveIntoThisFrame: (forward: Bool, from: String)? {
        guard let move = tabEntry.move, move.generation &+ 1 == focusRenderGeneration else { return nil }
        return (move.forward, move.from)
    }

    /// Notes that the Tab pressed just before this frame came into the
    /// subtree at `path` by `edge`, or passed over it: the stacks in it walk in
    /// from that edge, and the end of the pass takes the focus on to the row
    /// they find (``resolveEdgeArrival()``). Kept across the drawings of one
    /// frame, so the rows noted by an earlier one stay.
    /// An arrival already noted for a subtree holding this one, by the same
    /// edge, is kept: a column outside drew first, and its rows count too.
    func noteArrival(into path: String, by edge: VerticalEdge) {
        if let arrival = tabEntry.arrival,
            arrival.content == path || (arrival.edge == edge && Self.focusID(path, addressesSubtreeAt: arrival.content))
        {
            return
        }
        tabEntry.arrival = (path, edge, [])
    }

    /// The edge the Tab pressed just before this frame came into the subtree
    /// at `path` by, from outside it, or passed over it by; `nil` for none.
    /// See ``tabEntryEdges(intoSubtreeAt:ownStopAt:)``.
    private func arrivalEdge(
        into path: String, ownStopAt stopPath: String, focused: String, isInside: (String) -> Bool
    ) -> VerticalEdge? {
        guard let move = tabEntry.move, move.generation &+ 1 == focusRenderGeneration, !isInside(move.from)
        else { return nil }
        let isOwnStop = { (focusID: String) in self.renderedIdentity(ofFocusID: focusID)?.path == stopPath }
        // Rows filed in focus sections of their own are not the stop's
        // neighbours: Tab onto the stop came from the control before it.
        let passesStop = !previousSections.contains { Self.focusID($0.id, addressesSubtreeAt: path) }
        if move.forward {
            return isInside(focused) || (passesStop && isOwnStop(focused)) ? .top : nil
        }
        return isInside(focused) || (passesStop && isOwnStop(move.from) && !isOwnStop(focused)) ? .bottom : nil
    }

    /// Notes the Tab or Shift-Tab about to move the focus, for the frame after
    /// it (``tabEntryEdges(intoSubtreeAt:ownStopAt:)``).
    func noteTabMove(forward: Bool) {
        tabEntry.move = currentFocusedID.map { (forward, $0, focusRenderGeneration) }
    }

    /// Notes that the stack at `stackPath` found `row`, its row nearest `edge`
    /// with something to focus: where a Tab coming into the content that
    /// holds it by that edge may go on to. Several stacks of a column can
    /// note one — two lazy stacks one above the other, the first with nothing
    /// to focus on screen (`_VStackCore.entryChildren(_:frame:viewportHeight:context:)`) —
    /// and the end of the pass
    /// takes the one first in the ring for the top edge, last for the bottom
    /// (``resolveEdgeArrival()``): the order they are drawn in need not be.
    func noteEdgeStop(_ edge: VerticalEdge, row: String, stackPath: String) {
        guard let arrival = tabEntry.arrival, arrival.edge == edge,
            Self.focusID(stackPath, addressesSubtreeAt: arrival.content), !arrival.rows.contains(row)
        else { return }
        tabEntry.arrival?.rows.append(row)
    }

    /// Whether a control in the subtree at `path` could take the focus in last
    /// frame's ring: where a Tab coming into a column of the scroll content
    /// stops before it reaches the children past it
    /// (`_VStackCore.entryChildren(_:frame:viewportHeight:context:)`).
    func heldFocusableLastFrame(inSubtreeAt path: String) -> Bool {
        previousSections.contains { section in
            section.focusables.contains {
                $0.canBeFocused && Self.focusID(identityPath(of: $0.focusID), addressesSubtreeAt: path)
            }
        }
    }

    /// Takes the focus on to the row a stack found for a Tab that came into
    /// its content (``tabEntryEdges(intoSubtreeAt:ownStopAt:)``): its first
    /// control for Tab, its last for Shift-Tab — of the rows found, the one
    /// first in the ring for Tab, last for Shift-Tab. Nothing moves when the
    /// focus is in that row already, or no stack found one.
    ///
    /// Asked once the frame's walk is done, before it is written
    /// (`FrameSettling`), which walks the frame again when this moves the
    /// focus, so no frame shows it where the key left it; and again at the
    /// end of the pass, for a driver that does not ask.
    ///
    /// - Returns: Whether the focus moved.
    @discardableResult
    func resolveEdgeArrival() -> Bool {
        guard let arrival = tabEntry.arrival else { return false }
        tabEntry.arrival = nil
        guard !arrival.rows.isEmpty, let focused = currentFocusedID else { return false }
        let row = { (focusID: String) in
            let path = self.identityPath(of: focusID)
            return arrival.rows.first { Self.focusID(path, addressesSubtreeAt: $0) }
        }
        let ring = sections.flatMap(\.focusables).filter(\.canBeFocused)
        let stops = ring.filter { row($0.focusID) != nil }
        guard let target = arrival.edge == .top ? stops.first : stops.last, let targetRow = row(target.focusID),
            !Self.focusID(identityPath(of: focused), addressesSubtreeAt: targetRow),
            isNearer(target.focusID, than: focused, in: ring)
        else { return false }
        // The walk that found the row drew it, and what it publishes: the
        // walk made again with the focus on it reads that, above the row.
        focusedValues.carryWalkForward()
        focus(id: target.focusID)
        return currentFocusedID == target.focusID
    }

    /// Whether the key that moved the focus to `focused` would have gone to
    /// `target` had the ring held it then: the key goes to the nearest stop in
    /// its direction from the control it left. A Shift-Tab from a footer's
    /// button that a column walked in by its child above (a custom `Layout`
    /// holding a `tail` button and a lazy stack, `PulledLayoutReachTests`)
    /// lands on `tail`, after the stack's last row, and stays there. True when
    /// the control the key left is not in the ring, as before this was asked.
    private func isNearer(_ target: String, than focused: String, in ring: [Focusable]) -> Bool {
        guard let move = tabEntry.move, let from = ring.firstIndex(where: { $0.focusID == move.from }),
            let to = ring.firstIndex(where: { $0.focusID == focused }),
            let candidate = ring.firstIndex(where: { $0.focusID == target })
        else { return true }
        let count = ring.count
        let distance = { (index: Int) in move.forward ? (index - from + count) % count : (from - index + count) % count }
        return distance(candidate) < distance(to)
    }

    /// The identity path the control `focusID` names last registered at, or
    /// the id itself where it has not registered: a default id embeds its
    /// path, an explicit `.focusID(_:)` does not (``renderedIdentity(ofFocusID:)``).
    func identityPath(of focusID: String) -> String {
        renderedIdentity(ofFocusID: focusID)?.path ?? focusID
    }

    /// Where Tab (`.forward`) or Shift-Tab (`.backward`) from `focused` would
    /// land by last frame's ring, and the sections it would pass over that
    /// hold nothing focusable — ``focusNext()`` and ``focusPrevious()``
    /// played over ``previousSections`` without moving anything. `nil` when
    /// `focused` is not in last frame's active section.
    private func lastFrameTabStep(
        _ direction: FocusDirection, from focused: String
    ) -> (landing: Focusable?, passed: [FocusSection])? {
        let root = activeSectionIdentifier.flatMap(lastFrameModalRoot(of:))
        let ring = root.map { root in previousSections.filter { lastFrameModalRoot(of: $0.id) == root } }
            ?? previousSections
        guard let activeIndex = ring.firstIndex(where: { $0.id == activeSectionIdentifier }) else { return nil }
        let members = ring[activeIndex].focusables
        guard let anchor = members.firstIndex(where: { $0.focusID == focused && $0.canBeFocused }) else { return nil }
        if let next = Self.nearestFocusable(in: members, from: anchor, direction, wrap: false) { return (next, []) }
        if ring.count > 1 {
            var passed: [FocusSection] = []
            var index = activeIndex
            for _ in 1..<ring.count {
                index = direction == .forward ? (index + 1) % ring.count : (index + ring.count - 1) % ring.count
                let available = ring[index].focusables.filter(\.canBeFocused)
                if let edge = direction == .forward ? available.first : available.last { return (edge, passed) }
                passed.append(ring[index])
            }
        }
        return (Self.nearestFocusable(in: members, from: anchor, direction, wrap: true), [])
    }

    /// The modal section `section` belonged to last frame, as
    /// ``presentationRoot(of:)`` answers for this one: asked mid-walk, this
    /// frame's modal marks are not all made yet.
    private func lastFrameModalRoot(of section: String) -> String? {
        var current = section
        var remaining = sectionPresenters.count + previousSectionPresenters.count + 1
        while remaining > 0 {
            if previousModalSectionIDs.contains(current) || modalSectionIDs.contains(current) { return current }
            guard let next = sectionPresenters[current] ?? previousSectionPresenters[current] else { return nil }
            current = next
            remaining -= 1
        }
        return nil
    }
}
