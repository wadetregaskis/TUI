//  🖥️ TUI — A Terminal UI framework for Swift
//  MouseEventDispatcher+Gestures.swift
//
//  Where the mouse dispatcher meets the gesture arena: attached gestures filed
//  for their regions, the left button routed through the arena, and the
//  gestures' clock.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

extension MouseEventDispatcher {
    /// Files an attached gesture for the region its modifier is about to
    /// emit, and returns that region's id.
    ///
    /// The region is a hover OBSERVER's: a gesture is not a control, and must
    /// not take the hover from the control it is attached to, nor answer for
    /// one behind it. Its handler declines everything — a gesture hears the
    /// pointer through the arena, never through ordinary dispatch. The filing
    /// also asks for the click and drag reporting the arena hears it through.
    ///
    /// One registration, not the four it was made of — the observer's handler,
    /// the role, and a request for each feature, each through its own entry
    /// point. Each of those declared its own replayable effect, read the
    /// channel token from the environment and, while a memo recorded, built
    /// and journaled a closure of its own; a served row replayed all four, each
    /// looking the dispatcher up again. The filing is one thing, recorded and
    /// replayed as one ``fileGesture(_:id:)``.
    @MainActor
    func registerGesture(in context: RenderContext, _ role: GestureRole) -> HitTestRegion.HandlerID {
        let id = handlerIDs.id(registeredIn: context)
        fileGesture(role, id: id)
        // As every registration: a measure pass makes nothing a frame can be
        // served from (`registerInterned`), though an attachment files nothing
        // while it measures anyway.
        guard !context.isMeasuring else { return id }
        context.environment.volatileReadTracker?.recordReplayableEffect()
        if let journal = context.recordingEffectJournal {
            journal.append(
                EffectJournal.Entry(
                    kind: Self.gestureRoleKind, channelToken: context.environment.keyChannelToken
                ) { replay in
                    replay.environment.mouseEventDispatcher?.fileGesture(role, id: id)
                })
        }
        return id
    }

    /// Files `role` under `id`: the region's handler on the observer lane, the
    /// role, and the reporting a gesture needs — what a render and a memo's
    /// replay of it both do.
    @MainActor
    private func fileGesture(_ role: GestureRole, id: HitTestRegion.HandlerID) {
        // Captures nothing, so a constant: no closure context is allocated.
        MouseHandlerRegistrar.register(id: id, handler: { _ in false }, lane: .hoverObserver, into: self)
        gestureRoles[id] = role
        requestFeature(.clicks)
        requestFeature(.drag)
    }

    /// The journal kind of an attached gesture's filing.
    static let gestureRoleKind = EffectJournal.Kind("gestureRole")

    /// Files the gesture a disabled view's attachment kept from an earlier
    /// frame, so an arena it is still in gives it up at the disable rather
    /// than at the next press (decisions B-F2-2). A disabled view takes no
    /// gesture, so it files no role and no region: only this.
    @MainActor
    func fileDisabledGesture(_ participant: GestureParticipant, in context: RenderContext) {
        disabledGestureParticipants.insert(ObjectIdentifier(participant))
        context.environment.volatileReadTracker?.recordReplayableEffect()
        if let journal = context.recordingEffectJournal {
            journal.append(
                EffectJournal.Entry(
                    kind: Self.disabledGestureKind, channelToken: context.environment.keyChannelToken
                ) { replay in
                    replay.environment.mouseEventDispatcher?.disabledGestureParticipants.insert(
                        ObjectIdentifier(participant))
                })
        }
    }

    /// The journal kind of a disabled gesture's filing.
    static let disabledGestureKind = EffectJournal.Kind("disabledGesture")

    /// Whether the last walk filed as disabled a gesture an arena has not yet
    /// given up for it: the run loop asks for one more frame, so it is given
    /// up — and what it held back runs — at the disable rather than at
    /// whatever frame comes next.
    @MainActor
    package var hasPendingGestureDisable: Bool {
        guard !disabledGestureParticipants.isEmpty else { return false }
        return gestureArenas.contains { $0.hasPendingDisable(disabledGestureParticipants) }
    }

    /// Runs the gestures' clocks to `now` — a long press's minimum duration, a
    /// tap's wait for its next click.
    ///
    /// Called at the start of every frame, before the tree renders, so what a
    /// timed end changes is drawn in that frame — and before the dispatcher's
    /// tables are cleared, so a control a gesture was holding back is given its
    /// press against the frame it was pressed on.
    ///
    /// A gesture whose view has gone hears no clock, and what it holds back
    /// stays held (``GestureArena/Contender/isDeparted``). Measured on macOS
    /// 15.8: a row with a double tap and a single tap, clicked, then removed
    /// by a button 0.1 s later, runs neither the single tap when the double
    /// tap's interval is out nor, inside a tap, that tap; the next press
    /// gives them up (``routeThroughGestures(_:matching:)``). Disabled
    /// instead, the row runs no single tap either, and the tap around it runs
    /// the row's click at the disable, which the first tick after the walk
    /// that disabled it is (decisions B-F2-2, ``markDepartedGestures()``).
    @MainActor
    package func advanceGestures(nowNanos now: Int64) {
        guard !gestureArenas.isEmpty else { return }
        markDepartedGestures()
        for arena in gestureArenas { arena.process(.tick(now), dispatcher: self) }
        settleGestureArenas()
    }

    /// Marks the arenas' gestures the frame on screen no longer files —
    /// their view left the tree, or was disabled — as departed, and the rest
    /// as not, once per walk: by the first arena input after it.
    ///
    /// A disabled view's are given up there and then, and what that lets go
    /// of runs before the input (``GestureArena/cancelDisabled(_:)``).
    ///
    /// Asked of the participant rather than of its region's id: an id is
    /// interned by its place among its identity's registrations, and one
    /// that moved would mark a gesture still on screen.
    @MainActor
    private func markDepartedGestures() {
        guard gestureFilingsUnread, !gestureArenas.isEmpty else { return }
        gestureFilingsUnread = false
        let filed = Set(gestureRoles.values.lazy.compactMap { $0.participant.map(ObjectIdentifier.init) })
        var released = false
        for arena in gestureArenas {
            arena.markDeparted(filed: filed)
            if !disabledGestureParticipants.isEmpty {
                released = arena.cancelDisabled(disabledGestureParticipants) || released
            }
        }
        guard released else { return }
        for arena in gestureArenas { arena.process(nil, dispatcher: self) }
        settleGestureArenas()
    }

    /// Gives up every gesture whose view has gone, and settles what that
    /// released, as a tick of the clock would.
    @MainActor
    private func giveUpDepartedGestures() {
        var gaveUp = false
        for arena in gestureArenas { gaveUp = arena.cancelDeparted() || gaveUp }
        guard gaveUp else { return }
        for arena in gestureArenas { arena.process(nil, dispatcher: self) }
        settleGestureArenas()
    }

    /// When the gestures next have to hear the clock, if any is waiting on it
    /// — what the run loop asks a wake for, so a long press ends on time with
    /// nothing else moving.
    @MainActor
    package var gestureDeadline: Int64? { gestureArenas.lazy.compactMap(\.deadline).min() }

    /// Routes a left-button event through the gesture arena, when one is
    /// involved.
    ///
    /// Once the event is decided, every gesture whose view has gone is given
    /// up, which releases what it held back — after, so the event is decided
    /// as if the gesture were still there. Measured on macOS 15.8, a
    /// sequence waiting for its second tap, beside a plain box inside a tap,
    /// then removed or disabled: the first click on the box runs nothing, as
    /// with the sequence there (the sequence had cancelled the tap around
    /// it), and the next runs that tap; a first click on a button or another
    /// view's tap runs it. A row removed while its double tap waits lets the
    /// tap around it run the row's click at the next press, wherever that
    /// lands: on a plain box beside the row, inside the tap, the press starts
    /// nothing of its own; on a button or another view's tap, outside it, it
    /// runs that at its release. A drag removed or disabled mid-drag reports
    /// nothing at its next move or its release. Given up at the next frame
    /// instead, such a gesture made what a click did depend on whether a
    /// frame came first.
    ///
    /// A disabled view's gestures are given up at the disable instead, as
    /// macOS 15.8 does — a `@GestureState` resets then, and the tap around a
    /// row disabled while its double tap waits runs the row's click then, the
    /// next click running as usual — save one that had won its press, such as
    /// a waiting sequence, which still holds the next click and runs nothing
    /// beside it, as a removed one does (all measured; decisions B-F2-2,
    /// ``GestureArena/cancelDisabled(_:)``).
    ///
    /// - Parameter matching: The regions under the event, innermost first;
    ///   asked for only for a press.
    /// - Returns: The dispatch result when gestures decided the event's fate,
    ///   and `nil` when it should go on through ordinary dispatch — a press
    ///   with no gesture under it (an arena still waiting goes on waiting),
    ///   and the drags and release of a press no arena took.
    @MainActor
    func routeThroughGestures(_ event: MouseEvent, matching: () -> [HitTestRegion]) -> Bool? {
        guard event.button == .left, !gestureRoles.isEmpty || !gestureArenas.isEmpty else { return nil }
        let time = Int64(bitPattern: nowNanos())
        let regions = event.phase == .pressed ? matching() : []
        markDepartedGestures()
        defer { giveUpDepartedGestures() }
        switch event.phase {
        case .pressed:
            return beginGestureArena(event, matching: regions, time: time)
        case .dragged, .released:
            guard let arena = gestureArenas.last, arena.isButtonDown else { return nil }
            var routed = arena.process(.pointer(event, timeNanos: time), dispatcher: self)
            if arena.controlTookPress, let settled = routeAgainstItsPress(event) {
                routed = routed || settled
            }
            settleGestureArenas()
            return routed
        default:
            return nil
        }
    }

    @MainActor
    private func beginGestureArena(_ event: MouseEvent, matching: [HitTestRegion], time: Int64) -> Bool? {
        let ranking = GestureArena.rank(matching, roles: gestureRoles)
        // An arena still waiting on a ranked gesture — a double tap waiting
        // for its next click — lives on through this press, as on macOS 15.8:
        // what this press shares with it carries on where it is, the rest
        // goes on hearing the clock. One whose ranked gestures have all
        // decided is done: what is not under this press, or carried on by an
        // arena that waits, is given up on, which may release what it held
        // back.
        // Sorted once, before any is given up on: giving one up may release
        // what another holds.
        var waiting: [GestureArena] = []
        var done: [GestureArena] = []
        for arena in gestureArenas {
            if arena.waitsOnRankedGesture { waiting.append(arena) } else { done.append(arena) }
        }
        if !done.isEmpty {
            var kept = waiting.reduce(into: Set<ObjectIdentifier>()) { $0.formUnion($1.participants) }
            if let ranking {
                for contender in ranking.ranked.compactMap(\.contender) + ranking.simultaneous {
                    kept.insert(ObjectIdentifier(contender.participant))
                }
            }
            for arena in done {
                arena.cancel(allBut: kept)
                arena.process(nil, dispatcher: self)
                arena.leave()
            }
            gestureArenas = waiting
            feedOrphanedGestures()
        }
        // No gesture under this press: it goes through ordinary dispatch.
        guard let (ranked, simultaneous) = ranking else { return nil }
        for contender in ranked.compactMap(\.contender) + simultaneous {
            contender.owner = owner(of: contender.region.handlerID)
        }
        let arena = GestureArena(ranked: ranked, simultaneous: simultaneous, press: event)
        arena.adopt(from: gestureArenas)
        gestureArenas.removeAll { previous in
            guard previous.isTakenOver(by: arena) else { return false }
            previous.leave()
            return true
        }
        gestureArenas.append(arena)
        let engaged = arena.process(.pointer(event, timeNanos: time), dispatcher: self)
        settleGestureArenas()
        return engaged
    }

    /// Lets what one arena decided reach the others, and drops the arenas
    /// with nothing left to decide.
    ///
    /// A gesture under two presses is in both their arenas, and may report
    /// only once neither holds it back; whichever releases it last reports
    /// its end, and a decision in one — a double tap that recognized ahead of
    /// a held single tap — cancels what comes after it in each. Every arena
    /// is settled again without new input once per arena, so a decision
    /// travels the whole chain. With one arena, the usual case, there is
    /// nothing to pass on.
    @MainActor
    private func settleGestureArenas() {
        if gestureArenas.count > 1 {
            for _ in 1..<gestureArenas.count {
                for arena in gestureArenas { arena.process(nil, dispatcher: self) }
            }
        }
        let before = gestureArenas.count
        gestureArenas.removeAll { arena in
            guard arena.isSettled else { return false }
            arena.leave()
            return true
        }
        if gestureArenas.count < before { feedOrphanedGestures() }
    }

    /// Hands each gesture a dropped arena fed to the newest arena left that
    /// holds it, so that it goes on hearing the clock.
    @MainActor
    private func feedOrphanedGestures() {
        for arena in gestureArenas.reversed() { arena.feedOrphans() }
    }
}
