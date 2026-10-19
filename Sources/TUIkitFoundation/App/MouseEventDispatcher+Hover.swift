//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MouseEventDispatcher+Hover.swift
//
//  The mouse dispatcher's hover state machine: the lanes the pointer is
//  resolved on, the transitions a move delivers, and the reconciliation of a
//  reshape under a resting pointer. Moved out of `MouseEventDispatcher.swift`,
//  which had reached its length limit; the state stays on the class, which an
//  extension cannot hold.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension MouseEventDispatcher {
    /// One lane of the hover state machine: the region the pointer was last
    /// resolved against, and the closure still owed its exit across a reshape.
    ///
    /// There are two lanes, ``hover`` and ``observedHover``, and they run the
    /// same transitions independently — see ``registerHoverObserver(in:_:)``.
    struct HoverSlot {
        /// The handler ID of the region the cursor was sitting on
        /// when the previous `.moved` event was processed, or `nil`
        /// if the cursor wasn't over any region this lane resolves. Used to
        /// synthesise `.entered` / `.exited` transitions when the
        /// cursor crosses region boundaries. Preserved across render passes,
        /// and an id is the control's own, so it still names the control the
        /// cursor was on however the tree around it has changed.
        var handlerID: HitTestRegion.HandlerID?

        /// The hovered REGION itself, kept beside the id: what the cursor rests
        /// on is a rectangle, and a control that MOVED under a still cursor has
        /// left it even though its id is unchanged. So "the same control" is
        /// asked of the region — its focusID when it has one, its rectangle
        /// otherwise. See ``reconcileHoverAfterReshape()``.
        var region: HitTestRegion?

        /// The hovered region's closure, retained across the handler-table
        /// rebuild: if the reshape puts a different region under the resting
        /// cursor, `.exited` must still reach the one that was left — by then
        /// its numeric id belongs to someone else, or to no one.
        var pendingExit: PendingHoverExit?
    }

    /// A control that was hovered and whose `.exited` still has to reach it.
    ///
    /// A named struct rather than the labelled tuple it used to be, and the
    /// reason is not taste: as a tuple inside an `Optional` it crashes
    /// `swift-frontend` on the Swift 6.5-dev snapshot of 2026-08-30 — an
    /// assertion in the `LoadableByAddress` SIL pass, on this property's
    /// setter, which stops the whole package compiling on that toolchain. A
    /// struct compiles. It reads no worse either way.
    ///
    /// `Tools/CompilerBugs/LoadableByAddressAssertion` is the bug in twelve
    /// lines, with the near-misses beside it — including this exact swap, which
    /// is the last row of its matrix.
    struct PendingHoverExit {
        let region: HitTestRegion
        let handler: (MouseEvent) -> Bool
    }

    /// Notes that the event funnel is dispatching an input — a key, a
    /// modifier key, or any report from the mouse — so the reshapes from
    /// here on are its effect, not the hover handlers' own: the controls
    /// reshapes took a lane off since the last input are forgotten
    /// (``leftByReshape``). The mouse's are noted by ``dispatch(_:)`` itself.
    package func noteInput() {
        leftByReshape.removeAll(keepingCapacity: true)
    }

    /// Lets go of the pointer: the terminal says it has left the window, as
    /// far as a terminal says so at all — the window has lost the focus (a
    /// focus-out report, mode 1004). Every lane is exited, as a move off the
    /// screen would exit it, the pointer rests nowhere known
    /// (``restingPosition``), and the help it was showing goes, held or not
    /// (`TooltipState.pointerLeft()`).
    ///
    /// A terminal reports no motion once the pointer is outside its window,
    /// and no mouse mode reports the pointer leaving it (`Terminal
    /// compatibility survey.md`, "Focus reporting"): a control stayed lit and
    /// a help stayed in the bar for as long as the pointer was away, and a
    /// reshape went on entering what it slid under the cell the pointer had
    /// left. A pointer that leaves without the focus going is still not
    /// heard. Nothing is entered again until the pointer next reports motion.
    ///
    /// - Returns: Whether anything was exited, or a help went: the frame that
    ///   draws it is owed.
    @discardableResult
    package func pointerLeft() -> Bool {
        let position = restingPosition ?? lastMotionPosition ?? (x: 0, y: 0)
        restingPosition = nil
        lastMotionPosition = nil
        leftByReshape.removeAll()
        var fired = exitLane(&hover, at: position)
        fired = exitLane(&observedHover, at: position) || fired
        if tooltipState?.pointerLeft() == true { fired = true }
        return fired
    }

    /// Exits `slot`'s hovered region, its handler told the pointer at
    /// `position` has left it, and leaves the lane on nothing.
    ///
    /// - Returns: Whether a handler was told.
    private func exitLane(_ slot: inout HoverSlot, at position: (x: Int, y: Int)) -> Bool {
        defer { slot = HoverSlot() }
        let target: PendingHoverExit? =
            slot.pendingExit
            ?? slot.handlerID.flatMap { id in
                slot.region.flatMap { region in handlers[id].map { PendingHoverExit(region: region, handler: $0) } }
            }
        guard let target else { return false }
        _ = target.handler(
            MouseEvent(
                button: .none, phase: .exited,
                x: position.x - target.region.localOriginX, y: position.y - target.region.localOriginY))
        return true
    }

    /// Re-resolves the hover after the tree reshapes under a resting cursor.
    ///
    /// A reshape can slide a different control under a cursor that has not
    /// moved, and the lane would go on believing it hovers what it hovered: the
    /// same-region branch of `dispatchMotion` synthesises nothing, so hover
    /// strands on the control the cursor left (its box stuck lit) and never
    /// lights the one that arrived. Ids being positional made that the COMMON
    /// case, since the newcomer usually inherited the old number outright; they
    /// are interned per control now, and the re-resolve below is still what
    /// answers a control moving. The id is remapped here by the
    /// region's own identity — focusID when it has one, rectangle otherwise —
    /// and when a genuinely different control (or none) sits under the
    /// cursor, `.exited` goes to the RETAINED closure of the one that was
    /// left and `.entered` to the newcomer. Each lane is re-resolved against
    /// its own region — see ``resolveHover(at:y:)``.
    ///
    /// Re-resolved where the pointer is known to rest (``restingPosition``),
    /// and only there does anything hear `.entered`. Where that is not known
    /// — motion went unreported since — the lanes are re-resolved against the
    /// last move, as they always were, for the exits they owe, and enter
    /// nothing: the pointer may be anywhere.
    func reconcileHoverAfterReshape() {
        guard let position = restingPosition ?? lastMotionPosition else {
            hover.pendingExit = nil
            observedHover.pendingExit = nil
            return
        }
        let entering = restingPosition != nil
        let resolved = resolveHover(at: position.x, y: position.y)
        hover = reconciled(hover, to: resolved.target, at: position, entering: entering)
        observedHover = reconciled(observedHover, to: resolved.observer, at: position, entering: entering)
    }

    /// One lane of ``reconcileHoverAfterReshape()``: `slot` re-resolved against
    /// `current`, the region its lane finds under the resting cursor now.
    ///
    /// A lane resting on nothing is re-resolved too: a control the reshape put
    /// under the cursor is entered, as a move onto it would enter it. Only a
    /// lane that hovered something used to be, so a view a reshape slid under
    /// a cursor resting on blank space heard nothing until the cursor next
    /// moved — its `.onHover` unlit, its help never starting its delay
    /// (decisions-HELP A-HELP-1, "Left open"). Only at a position known to
    /// be where the pointer rests (`entering`), and not while motion is not
    /// reported, when the control it enters would be left only by a move
    /// nobody hears: asked of ``frameFinalSupport``, the mode the terminal
    /// reports under since the last frame, not of ``activeSupport``, which
    /// the walk reset to the scene's base mid-frame — without motion unless
    /// the scene declares it, though an `.onHover` asks for it every frame.
    /// Entered once: the lane holds the control from then on,
    /// and the next reshape finds the same one. Never a control a reshape
    /// has taken a lane off since the last input (``leftByReshape``).
    ///
    /// A lane that hovered something enters the newcomer under the pointer
    /// only at a known position too (`entering`); it is exited as before,
    /// and what it left is remembered.
    private func reconciled(
        _ slot: HoverSlot, to current: HitTestRegion?, at position: (x: Int, y: Int), entering: Bool
    ) -> HoverSlot {
        guard slot.region != nil || slot.pendingExit != nil else {
            guard let current, entering, frameFinalSupport.motion, !leftByReshape.contains(current.handlerID)
            else { return slot }
            return entered(current, at: position)
        }
        let previous = slot.pendingExit?.region ?? slot.region
        if let current, isSameControl(previous, current) {
            return HoverSlot(handlerID: current.handlerID, region: current, pendingExit: nil)
        }
        if let pending = slot.pendingExit {
            let exit = MouseEvent(
                button: .none, phase: .exited,
                x: position.x - pending.region.localOriginX,
                y: position.y - pending.region.localOriginY)
            _ = pending.handler(exit)
        } else if let oldID = slot.handlerID, let oldHandler = handlers[oldID],
            let oldRegion = slot.region
        {
            // Regions replaced within one frame (no beginRenderPass between):
            // the old handler is still registered, and the trailing exit is
            // its due — this is the documented same-frame window.
            let exit = MouseEvent(
                button: .none, phase: .exited,
                x: position.x - oldRegion.localOriginX,
                y: position.y - oldRegion.localOriginY)
            _ = oldHandler(exit)
        }
        if let left = previous?.handlerID { leftByReshape.insert(left) }
        guard let current, entering, !leftByReshape.contains(current.handlerID) else { return HoverSlot() }
        return entered(current, at: position)
    }

    /// A lane on `region`, its handler told the resting cursor at `position`
    /// has entered it.
    private func entered(_ region: HitTestRegion, at position: (x: Int, y: Int)) -> HoverSlot {
        if let handler = handlers[region.handlerID] {
            let enter = MouseEvent(
                button: .none, phase: .entered,
                x: position.x - region.localOriginX,
                y: position.y - region.localOriginY)
            _ = handler(enter)
        }
        return HoverSlot(handlerID: region.handlerID, region: region, pendingExit: nil)
    }

    /// The closure a lane's hovered region still has in this frame's table,
    /// kept for the exit a reshape may owe it — `nil` when the lane hovers
    /// nothing the table still holds.
    func retainedExit(for slot: HoverSlot) -> PendingHoverExit? {
        guard let id = slot.handlerID, let handler = handlers[id], let region = slot.region
        else { return nil }
        return PendingHoverExit(region: region, handler: handler)
    }

    /// Whether two regions are the same CONTROL across a reshape: their
    /// focusIDs when both have one, their rectangles otherwise.
    private func isSameControl(_ a: HitTestRegion?, _ b: HitTestRegion) -> Bool {
        guard let a else { return false }
        if let fa = a.focusID, let fb = b.focusID { return fa == fb }
        return a.offsetX == b.offsetX && a.offsetY == b.offsetY
            && a.width == b.width && a.height == b.height
    }

    /// The two regions hover resolves against at a point, one per lane: the
    /// innermost region that is NOT a hover observer — the control the pointer
    /// is over — and the innermost observer IN FRONT of it.
    ///
    /// An observer behind that control is occluded and resolves to `nil`. That
    /// keeps the observer lane's answers exactly what they were when an observer
    /// was an ordinary region — it hears the pointer only where it was the
    /// innermost match — so a page's `.onHover` under a modal's consuming
    /// backdrop, or under an open menu, still hears nothing. The one thing that
    /// changes is that the control directly behind a stack of observers gets
    /// the hover it used to lose.
    private func resolveHover(at x: Int, y: Int) -> (target: HitTestRegion?, observer: HitTestRegion?) {
        let matching = matchingRegions(at: x, y: y)
        // The common frame has no observer, and is the old single lane.
        guard !hoverObserverIDs.isEmpty else { return (matching.first, nil) }
        var observer: HitTestRegion?
        for region in matching {
            guard hoverObserverIDs.contains(region.handlerID) else { return (region, observer) }
            if observer == nil { observer = region }
        }
        return (nil, observer)
    }

    /// Whether the hover observer registered this frame as `id` is one a
    /// pointer can reach: whether a pointer on some cell of its regions would
    /// be heard by it, rather than by nothing (no such region: the view is
    /// gone, or clipped away) or by something in front of it that takes the
    /// hover (a sheet's backdrop, an open menu, a hover observer inside it).
    ///
    /// For a tooltip held while the status bar's own rows moved the page
    /// under a resting pointer (`TooltipState.held`): the pointer is not on
    /// its view, so the hover machine reports nothing that happens to it.
    ///
    /// Every cell until one is heard, not the first alone: a view whose
    /// top-left cell something covered was taken for unreachable, and its
    /// help let go, though the pointer could rest on the rest of it
    /// (decisions-HELP A-HELP-1, "Left open"). Asked once a frame, and only
    /// while a help is held.
    package func reachesHoverObserver(_ id: HitTestRegion.HandlerID) -> Bool {
        for region in regions where region.handlerID == id {
            for y in region.offsetY..<(region.offsetY + region.height) {
                for x in region.offsetX..<(region.offsetX + region.width)
                where resolveHover(at: x, y: y).observer?.handlerID == id {
                    return true
                }
            }
        }
        return false
    }

    /// Processes a bare cursor-motion event by synthesising
    /// `.entered` / `.exited` transitions on the affected
    /// handlers — the hover state machine.
    ///
    /// Why route `.moved` separately:
    ///
    /// - There is no useful "the cursor moved here" semantic
    ///   that a single hit-test-based dispatch could deliver.
    ///   What views actually care about is "the cursor is now
    ///   over me" / "the cursor left me", and that requires
    ///   tracking which region the cursor was over previously.
    /// - Synthesising transitions in one place keeps the rest
    ///   of the dispatcher dumb. Modifiers like ``OnHover``
    ///   only have to react to the synthetic `.entered` /
    ///   `.exited` phases; they never deal with raw motion.
    ///
    /// Returns `true` iff at least one transition fired
    /// (either an `.entered` on a new region or an `.exited`
    /// on the previous one), so the AppRunner re-renders the
    /// view tree to reflect the new hover state. Pure motion
    /// inside the already-hovered region is offered to that
    /// handler as a localized `.moved`, and re-renders only if
    /// it says the move meant something — re-rendering for
    /// every cursor twitch would peg the run loop, and most
    /// handlers care only about entering and leaving.
    ///
    /// The machine runs on two lanes: the control under the pointer, and the
    /// hover observer in front of it (``registerHoverObserver(in:_:)``). Each lane
    /// transitions on its own, and the motion wants a render when either does.
    func dispatchMotion(_ event: MouseEvent) -> Bool {
        let resolved = resolveHover(at: event.x, y: event.y)
        // A report from the cell the pointer was already on moves nothing.
        let movedCell = lastMotionPosition.map { $0.x != event.x || $0.y != event.y } ?? true
        // Real motion supersedes any reshape bookkeeping: `advancing` hands
        // each lane back with its pending exit dropped.
        lastMotionPosition = (event.x, event.y)
        var fired = false
        hover = advancing(hover, to: resolved.target, by: event, fired: &fired)
        observedHover = advancing(observedHover, to: resolved.observer, by: event, fired: &fired)
        // After the lanes, whose `.entered` takes back a tooltip held through
        // the status bar's reflow when the move lands on its view again
        // (`TooltipState.held`); one the move left behind goes, and its
        // going is the frame this motion asks for.
        if movedCell, tooltipState?.notePointerMoved() == true { fired = true }
        return fired
    }

    /// One lane of ``dispatchMotion(_:)``: `slot` moved onto `current`, the
    /// region its lane resolves under the pointer, with the transitions that
    /// takes delivered on the way. Sets `fired` when the move wants a render.
    private func advancing(
        _ slot: HoverSlot, to current: HitTestRegion?, by event: MouseEvent, fired: inout Bool
    ) -> HoverSlot {
        let currentID = current?.handlerID
        let next = HoverSlot(handlerID: currentID, region: current, pendingExit: nil)

        // Still inside the same region: some controls are not one target but
        // many — a scrollbar's arrows and thumb share one region, and the cell
        // under the pointer is what lifts — so the move is offered to the
        // handler, which answers whether it changed anything.
        if currentID == slot.handlerID {
            if let currentID, let handler = handlers[currentID], let current {
                let moved = MouseEvent(
                    button: .none, phase: .moved,
                    x: event.x - current.localOriginX, y: event.y - current.localOriginY,
                    shift: event.shift, ctrl: event.ctrl, meta: event.meta
                )
                if handler(moved) { fired = true }
            }
            return next
        }

        // Fire .exited on the previously hovered handler if it
        // is still registered. (Between event and re-render,
        // the previous frame's handlers are still in `handlers`
        // — beginRenderPass for the next frame hasn't run yet.)
        // Coordinates are localised to the region, honouring the
        // dispatcher's contract for every phase — hover handlers
        // mostly ignore them, but DraggableModifier hit-tests the
        // transition point against its content's regions to route
        // hover through to interactive children.
        if let oldID = slot.handlerID, let oldHandler = handlers[oldID] {
            let offset = regionOffset(for: oldID) ?? (0, 0)
            let exit = MouseEvent(
                button: .none, phase: .exited,
                x: event.x - offset.x, y: event.y - offset.y,
                shift: event.shift, ctrl: event.ctrl, meta: event.meta
            )
            _ = oldHandler(exit)
            fired = true
        }

        if let newID = currentID, let newHandler = handlers[newID], let current {
            let enter = MouseEvent(
                button: .none, phase: .entered,
                x: event.x - current.localOriginX, y: event.y - current.localOriginY,
                shift: event.shift, ctrl: event.ctrl, meta: event.meta
            )
            _ = newHandler(enter)
            fired = true
        }
        return next
    }
}
