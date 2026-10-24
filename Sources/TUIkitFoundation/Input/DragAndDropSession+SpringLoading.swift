//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DragAndDropSession+SpringLoading.swift
//
//  Spring loading: a drag held still over a spring-loaded control activates
//  it, and carries on. Resolved the way drop targeting is — against the
//  controls on screen now, registered per frame — and timed the way the edge
//  auto-scroll is, by the run loop at the top of a frame.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension DragAndDropSession {
    /// One frame's registration of a control a paused drag activates.
    ///
    /// The sibling of ``DragAndDropSession/Target``: a rectangle the session
    /// finds by its handler id at the pointer, and what to do there.
    package struct SpringLoadTarget {
        /// The mouse-region id whose on-screen rectangle the pause is over.
        package let handlerID: HitTestRegion.HandlerID

        /// The control's identity, so the view the drag is carrying is never
        /// activated by a pause over its own (blank) place.
        package let identity: ViewIdentity

        /// What a pause does: what a click on the control would do.
        package let activate: () -> Void

        /// The control's pictures, dropped when the pause starts drawing it as
        /// waiting or firing and when it stops (``springLoadPhase(of:)``).
        /// Stamped by ``registerSpringLoadTarget(_:in:)``, which knows the
        /// context; `nil` for a bare registration.
        var drawing: HandlerDrawing?

        /// The memberwise initializer, spelled out because the synthesized one
        /// is internal and TUIkitTabs makes these, for a tab bar's tabs and a
        /// sidebar's tab rows, and TUIkitPickers, for a segmented picker's
        /// segments.
        package init(handlerID: HitTestRegion.HandlerID, identity: ViewIdentity, activate: @escaping () -> Void) {
            self.handlerID = handlerID
            self.identity = identity
            self.activate = activate
        }
    }

    /// The spring-loaded control the drag is over, and how long it has rested
    /// there.
    struct SpringLoadHover {
        /// The control's region id.
        let handlerID: HitTestRegion.HandlerID

        /// The control, and its pictures — what ``springLoadPhase(of:)`` is
        /// asked by, and what a change of phase redraws.
        let identity: ViewIdentity
        let drawing: HandlerDrawing?

        /// The cell the pointer rests on, absolute. A move to another cell is
        /// not a pause, and starts the clock again.
        var cellX: Int
        var cellY: Int

        /// When the pause began, on the frame clock — `nil` until the first
        /// frame that sees it, so the pause is timed on the clock its deadline
        /// is checked against (as ``LongPressGestureModifier``'s press is).
        var sinceNanos: UInt64?

        /// Whether the pause has activated the control. Once per arrival: a
        /// disclosure group opened by a pause must not shut on the next one,
        /// so the control is spent until the pointer leaves it.
        var fired = false

        /// Until when, on the frame clock, the control is drawn as pressed,
        /// having just fired — `nil` once that has passed, or before it fires.
        var firingUntilNanos: UInt64?

        /// How the control is drawn now.
        var phase: SpringLoadPhase? {
            if firingUntilNanos != nil { return .firing }
            return fired ? nil : .pending
        }
    }

    /// How a spring-loaded control a paused drag rests on is drawn (owner
    /// ruling B82), as macOS draws it: highlighted while it waits, emphasised
    /// as it fires.
    package enum SpringLoadPhase: Sendable {
        /// The pause is running: the control draws as hovered.
        case pending
        /// The pause has just activated it: the control draws as pressed,
        /// from that frame for ``SpringLoading/firingNanos``.
        case firing
    }

    /// How the control at `identity` is drawn for the paused drag resting on
    /// it, or `nil` for none: each spring-loading control ORs it into its
    /// hovered and pressed looks (owner ruling B82).
    package func springLoadPhase(of identity: ViewIdentity) -> SpringLoadPhase? {
        guard let hover = springLoadHover, hover.identity == identity else { return nil }
        return hover.phase
    }

    /// Drops the pictures of the controls whose spring-loading look the last
    /// change to ``springLoadHover`` changed: the one it named, and the one it
    /// names now.
    func redrawSpringLoadPhases(from old: SpringLoadHover?) {
        let new = springLoadHover
        guard old?.identity != new?.identity || old?.phase != new?.phase else { return }
        old?.drawing?.changed()
        if old?.identity != new?.identity { new?.drawing?.changed() }
    }

    /// The spring-loading delay.
    enum SpringLoading {
        /// How long the pointer must rest on a control: half a second, 30
        /// ticks of the frame clock — macOS's default, the
        /// `com.apple.springing.delay` that System Settings' spring-loading
        /// speed slider writes (read as 0.5 on the measuring machine).
        static let delayNanos = UInt64(AnimationClock.nanoseconds(atTick: 30))

        /// How long a control is drawn as pressed once a pause has activated
        /// it: six ticks of the frame clock, a tenth of a second — long enough
        /// to be seen, where one frame is gone before it is.
        static let firingNanos = UInt64(AnimationClock.nanoseconds(atTick: 6))
    }

    /// Registers a spring-load target for this frame — the bare form, for the
    /// session's own machinery and the tests that drive it directly.
    func registerSpringLoadTarget(_ target: SpringLoadTarget) {
        springLoadTargets.append(target)
    }

    /// Registers a spring-load target for the view `context` is rendering, and
    /// records the registration for the value memo that may serve the subtree,
    /// as a drop target's is: a served button that no longer registered would
    /// sit under a paused drag and do nothing.
    @MainActor
    package func registerSpringLoadTarget(_ target: SpringLoadTarget, in context: RenderContext) {
        var target = target
        target.drawing = HandlerDrawing(context)
        registerSpringLoadTarget(target)
        guard let journal = DragAndDropRegistrar.declareReplayable(in: context) else { return }
        journal.append(
            EffectJournal.Entry(
                kind: DragAndDropRegistrar.springLoadKind,
                channelToken: context.environment.keyChannelToken
            ) { replay in
                replay.environment.dragAndDropSession?.registerSpringLoadTarget(target)
            })
    }

    /// Notes where the drag is, against the spring-load targets on screen: a
    /// new control starts a pause, a move to another cell restarts it, and
    /// leaving every control ends it.
    ///
    /// Called on every drag event and again by ``driveSpringLoading(nowNanos:)``
    /// — the second because a frame can move a control out from under a pointer
    /// that has not moved (a list auto-scrolling, a page the last pause opened).
    func trackSpringLoading() {
        guard springLoadingApplies, let event = lastAbsoluteEvent,
            let target = springLoadTarget(atX: event.x, y: event.y)
        else {
            springLoadHover = nil
            return
        }
        guard var hover = springLoadHover, hover.handlerID == target.handlerID else {
            springLoadHover = SpringLoadHover(
                handlerID: target.handlerID, identity: target.identity, drawing: target.drawing,
                cellX: event.x, cellY: event.y)
            return
        }
        if hover.cellX != event.x || hover.cellY != event.y {
            hover.cellX = event.x
            hover.cellY = event.y
            if !hover.fired { hover.sinceNanos = nil }
        }
        springLoadHover = hover
    }

    /// Advances the pause, activating the control under it once it has lasted
    /// the delay, and returns the instant the run loop should next render at
    /// for it — `nil` when nothing is pending.
    ///
    /// Run at the top of a frame, before the pass clears the last frame's
    /// regions and registrations, as ``driveAutoScroll(nowNanos:)`` is: those
    /// are what is on screen, and so what the pointer is resting on. A
    /// control's activation then shows in the frame about to be drawn.
    package func driveSpringLoading(nowNanos: UInt64) -> UInt64? {
        trackSpringLoading()
        // A control that has just fired draws as pressed until its flash is
        // over, and asks for the frame that ends it.
        if var hover = springLoadHover, let until = hover.firingUntilNanos {
            guard nowNanos >= until else { return until }
            hover.firingUntilNanos = nil
            springLoadHover = hover
            return nil
        }
        guard var hover = springLoadHover, !hover.fired,
            let target = springLoadTargets.last(where: { $0.handlerID == hover.handlerID })
        else { return nil }
        let since = hover.sinceNanos ?? nowNanos
        hover.sinceNanos = since
        let deadline = since &+ SpringLoading.delayNanos
        guard nowNanos >= deadline else {
            springLoadHover = hover
            return deadline
        }
        hover.fired = true
        hover.firingUntilNanos = nowNanos &+ SpringLoading.firingNanos
        springLoadHover = hover
        target.activate()
        return hover.firingUntilNanos
    }

    /// Whether a drag in flight can spring-load anything: one carrying a
    /// payload. A row reorder cannot — its rows land only in the list they
    /// came from, so revealing somewhere else is no use to it.
    private var springLoadingApplies: Bool {
        active != nil && reorderFocusID == nil
    }

    /// The innermost spring-load target at the given position, from this
    /// frame's registrations — never the view being carried or a control inside
    /// it (`Button { … }.draggable(item)`), whose place is blank while it is in
    /// the hand. A control that merely CONTAINS the carried view still counts:
    /// a tab view's chips are registered at the tab view, and a drag out of one
    /// tab's content onto another tab's chip is the case spring loading is for.
    private func springLoadTarget(atX x: Int, y: Int) -> SpringLoadTarget? {
        let hitIDs = dispatcher?.handlerIDs(at: x, y: y) ?? []
        for id in hitIDs {
            guard let target = springLoadTargets.last(where: { $0.handlerID == id }) else { continue }
            if let source, target.identity == source || source.isAncestor(of: target.identity) {
                return nil
            }
            return target
        }
        return nil
    }
}
