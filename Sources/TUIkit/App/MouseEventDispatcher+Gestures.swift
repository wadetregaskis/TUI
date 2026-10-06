//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MouseEventDispatcher+Gestures.swift
//
//  Where the mouse dispatcher meets the gesture arena: attached gestures filed
//  for their regions, the left button routed through the arena, and the
//  gestures' clock.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

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
        MouseHandlerRegistrar.register(id: id, handler: { _ in false }, isHoverObserver: true, into: self)
        gestureRoles[id] = role
        requestFeature(.clicks)
        requestFeature(.drag)
    }

    /// The journal kind of an attached gesture's filing.
    static let gestureRoleKind = EffectJournal.Kind("gestureRole")

    /// Runs the gestures' clocks to `now` — a long press's minimum duration, a
    /// tap's wait for its next click.
    ///
    /// Called at the start of every frame, before the tree renders, so what a
    /// timed end changes is drawn in that frame — and before the dispatcher's
    /// tables are cleared, so a control a gesture was holding back is given its
    /// press against the frame it was pressed on.
    ///
    /// First, every gesture the last frame did not file is given up: its
    /// view left the tree, or was disabled. Measured on macOS 15.8: a row
    /// clicked, then removed by a button 0.1 s later, runs no single tap
    /// behind its double tap; with the row kept, it runs when the double tap
    /// gives up. Nothing else reaches a gesture once its view has gone, so it
    /// waited out its interval and ran the single tap for a row no longer on
    /// screen. Asked of the participant rather than of its region's id: an
    /// id is interned by its place among its identity's registrations, and
    /// one that moved would give up a gesture still on screen.
    @MainActor
    func advanceGestures(nowNanos now: Int64) {
        guard !gestureArenas.isEmpty else { return }
        let filed = Set(gestureRoles.values.lazy.compactMap { $0.participant.map(ObjectIdentifier.init) })
        for arena in gestureArenas { arena.cancel(allBut: filed) }
        for arena in gestureArenas { arena.process(.tick(now), dispatcher: self) }
        settleGestureArenas()
    }

    /// When the gestures next have to hear the clock, if any is waiting on it
    /// — what the run loop asks a wake for, so a long press ends on time with
    /// nothing else moving.
    @MainActor
    var gestureDeadline: Int64? { gestureArenas.lazy.compactMap(\.deadline).min() }

    /// Routes a left-button event through the gesture arena, when one is
    /// involved.
    ///
    /// - Parameter matching: The regions under the event, innermost first;
    ///   asked for only for a press.
    /// - Returns: The dispatch result when gestures decided the event's fate,
    ///   and `nil` when it should go on through ordinary dispatch — a press
    ///   with no gesture under it (an arena still waiting goes on waiting),
    ///   and the drags and release of a press no arena took.
    func routeThroughGestures(_ event: MouseEvent, matching: () -> [HitTestRegion]) -> Bool? {
        guard event.button == .left, !gestureRoles.isEmpty || !gestureArenas.isEmpty else { return nil }
        let time = Int64(bitPattern: nowNanos())
        let regions = event.phase == .pressed ? matching() : []
        return MainActor.assumeIsolated {
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
