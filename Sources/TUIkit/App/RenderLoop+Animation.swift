//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderLoop+Animation.swift
//
//  What a frame's animations are a function of — the clocks, the scheduler,
//  the frame's instant and the pending transaction — and the request that keeps
//  frames coming while anything still moves. Split from `RenderLoop.swift`,
//  which had reached the file-length limit, unchanged but for access: the two
//  functions and the token were private to that file.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension RenderLoop {
    /// Publishes everything this frame's animations are a function of: the two
    /// clocks, the scheduler they declare their rates to, this frame's `now`,
    /// and the transaction the pending change was made under — and tells the
    /// render cache where the clocks stand.
    ///
    /// `frameNowNanos` is the instant a wake declared this frame is measured from,
    /// and the one the loop asks for the next firing after, so the two agree
    /// exactly rather than by a clock read apart. `frameDate` is the wall clock
    /// read beside it, for the same reason: a timeline's wake is the distance
    /// from this date to its next entry, counted from `frameNowNanos`.
    func publishAnimationValues(
        into environment: inout EnvironmentValues,
        pulsePhase: Double,
        cursorTimer: CursorTimer?,
        animationScheduler: AnimationScheduler?,
        frameNowNanos: Int64,
        frameDate: Date
    ) {
        environment.pulsePhase = pulsePhase
        environment.cursorTimer = cursorTimer
        environment.animationScheduler = animationScheduler
        // One value, one dictionary entry: see `AnimationFrame`. The tick is
        // read WITHOUT marking the clock as consumed — a producer that lays its
        // cycle out against it is precisely one the loop can replay instead of
        // re-render, so reading it must not be what stops that. `canAnimate` is
        // false without a scheduler: a one-off render would show an animation's
        // first value and never advance past it.
        //
        // The CONTENT step, not the cursor one. Every `withAnimation` cycle
        // lays itself out against this, and a fade the app is running has
        // nothing to do with where the focus is — reading the focus-relative
        // step here restarted every such animation whenever the focus moved,
        // which is what made the Animation page's breathing label jump back to
        // full opacity on Tab.
        environment.animationFrame = AnimationFrame(
            nowNanos: frameNowNanos,
            step: cursorTimer?.steps(for: .content) ?? 0,
            canAnimate: animationScheduler != nil)
        // The same instant, for the render cache, read as the views read it: a
        // spinner or a bar indexes the frame's own timestamp, and a focus breath or
        // a caret the cursor timer's focus clock, 0 without a timer. The cache stamps
        // what it stores with it, and serves a stored buffer only while its animated
        // cells would show the same frames now — see `RenderCache.frameInstant`.
        tuiContext.renderCache.frameInstant = AnimationInstant(
            content: Double(frameNowNanos) / 1_000_000_000,
            cursor: cursorTimer?.elapsed(for: .cursor) ?? 0)
        // And the wall clock at that instant, the one date every walk of this
        // frame resolves a timeline's schedule against — see
        // `RenderCache.frameDate`.
        tuiContext.renderCache.frameDate = frameDate
        // Consumed, not merely read, so it applies to exactly one pass: the one
        // that first shows the change. A frame that renders for some other
        // reason must not restart animations that already began.
        environment.transaction = AppState.shared.consumePendingTransaction() ?? Transaction()
        // The completions waiting on the change go with it: this pass starts
        // its animations, and so decides when they fire.
        tuiContext.stateStorage.animationCompletions.beginPass(
            placing: AppState.shared.consumePendingCompletions())
    }

    /// Keeps the frames coming while anything is still moving.
    ///
    /// Asked once for the whole tree rather than declared per animating view: an
    /// interpolation's next frame is due at a *rate*, not at a phase, so one
    /// lattice serves every animation on screen (`AnimationRequest.viewAnimations`)
    /// — and it disappears the moment the last one arrives, which is what stops a
    /// settled screen rendering.
    ///
    /// Called AFTER the pass's prune, so an animation whose view has just left
    /// the tree does not hold the loop open for something nobody can see. A
    /// view that is *leaving* is the deliberate exception — it is exactly the
    /// thing nobody can see coming, and it needs frames until it has gone.
    func keepAnimating(scheduler: AnimationScheduler?, frameNowNanos: Int64) {
        let store = tuiContext.stateStorage
        guard store.animations.hasLiveAnimations(at: frameNowNanos)
            || store.departures.hasDepartures(at: frameNowNanos)
        else { return }
        scheduler?.request(Self.viewAnimationToken, .viewAnimations)
    }

    /// The scheduler token every in-flight interpolation shares.
    ///
    /// One token, not one per animation: they all want the same thing — another
    /// frame, soon — so they ride one lattice and one render serves them all.
    static var viewAnimationToken: String { "view-animations" }
}
