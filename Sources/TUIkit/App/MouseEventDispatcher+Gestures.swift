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
    @MainActor
    func advanceGestures(nowNanos now: Int64) {
        guard let arena = gestureArena else { return }
        arena.process(.tick(now), dispatcher: self)
        if arena.isSettled { gestureArena = nil }
    }

    /// When the gestures next have to hear the clock, if any is waiting on it
    /// — what the run loop asks a wake for, so a long press ends on time with
    /// nothing else moving.
    @MainActor
    var gestureDeadline: Int64? { gestureArena?.deadline }

    /// Routes a left-button event through the gesture arena, when one is
    /// involved.
    ///
    /// - Parameter matching: The regions under the event, innermost first;
    ///   asked for only for a press.
    /// - Returns: The dispatch result when gestures decided the event's fate,
    ///   and `nil` when it should go on through ordinary dispatch — no gesture
    ///   under the press, and no arena under way.
    func routeThroughGestures(_ event: MouseEvent, matching: () -> [HitTestRegion]) -> Bool? {
        guard event.button == .left, !gestureRoles.isEmpty || gestureArena != nil else { return nil }
        let time = Int64(bitPattern: nowNanos())
        let regions = event.phase == .pressed ? matching() : []
        return MainActor.assumeIsolated {
            switch event.phase {
            case .pressed:
                return beginGestureArena(event, matching: regions, time: time)
            case .dragged, .released:
                guard let arena = gestureArena, arena.isButtonDown else { return nil }
                var routed = arena.process(.pointer(event, timeNanos: time), dispatcher: self)
                if arena.controlTookPress, let settled = routeAgainstItsPress(event) {
                    routed = routed || settled
                }
                if event.phase == .released, arena.isSettled { gestureArena = nil }
                return routed
            default:
                return nil
            }
        }
    }

    @MainActor
    private func beginGestureArena(_ event: MouseEvent, matching: [HitTestRegion], time: Int64) -> Bool? {
        let previous = gestureArena
        guard let (ranked, simultaneous) = GestureArena.rank(matching, roles: gestureRoles) else {
            // No gesture under this press: whatever was waiting is given up on,
            // and the press goes through ordinary dispatch.
            if let previous {
                previous.cancel(allBut: [])
                previous.process(nil, dispatcher: self)
            }
            gestureArena = nil
            return nil
        }
        let arena = GestureArena(ranked: ranked, simultaneous: simultaneous, press: event)
        if let previous { arena.inherit(from: previous, dispatcher: self) }
        gestureArena = arena
        let engaged = arena.process(.pointer(event, timeNanos: time), dispatcher: self)
        if arena.handedOff { gestureArena = nil }
        return engaged
    }
}
