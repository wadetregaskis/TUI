//  🖥️ TUI — A Terminal UI framework for Swift
//  RedrawForecast.swift
//
//  Whether a cycle a view is about to pre-render would ever be replayed.
//
//  A view that animates without being re-rendered draws its whole cycle once and
//  hands the run loop the frames as ``AnimatedCellRun``s: a focused list's cursor
//  row breathes that way, sixteen frames of its lines for one render. That is the
//  cheap route only while nothing else renders the page: the next render replaces
//  the runs with its own, and a run the loop never replayed was built for nothing.
//  A list of live previews, each a `TimelineView` drawn every tick, rebuilt its
//  cursor row sixteen times a frame to show one of them, a tenth of the frame.
//
//  So the view asks first. It is drawn again before the cycle next steps when two
//  things hold, and then only the frame on screen is worth building:
//
//  * a render is due by then, which this frame has already asked for — a lattice
//    or a wake declared so far, never one left from the frame before that has not
//    been declared again and may not be (``AnimationScheduler/nextFiringDeclaredThisFrame(after:)``);
//  * that render reaches the view: something drawn inside it since it began did
//    what a kept buffer cannot do again — the very wake, often — so every memo
//    around it declines to keep this frame's buffer (``VolatileReadTracker/sideEffects``),
//    and the next walk draws it afresh.
//
//  Neither holds by accident in the other direction, so the forecast errs one
//  way only: a view it cannot vouch for builds its runs as before.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// What a view knows, part-way through drawing itself, of whether it is drawn again
/// before a cycle it would pre-render next steps — taken as it begins
/// (``init(_:)``), and asked once it knows the cycle
/// (``outruns(nextStepOf:in:)``).
package struct RedrawForecast {
    /// The pass's tracker as the view began, and the side effects it had counted:
    /// `nil` without a tracker, where nothing says what a memo will keep.
    private let start: (tracker: VolatileReadTracker, sideEffects: Int)?

    /// The forecast for a view drawing in `context`, taken before it draws anything
    /// of its content.
    @MainActor
    package init(_ context: RenderContext) {
        start = context.environment.volatileReadTracker.map { ($0, $0.sideEffects) }
    }

    /// No forecast: every cycle is built whole. For a caller drawing lines it keeps
    /// no runs of anyway.
    package static var none: Self { Self() }

    private init() { start = nil }

    /// Whether the view is drawn again at or before the soonest next step of `runs`,
    /// so the runs built for them now would never be replayed: the render due by then
    /// draws whatever step the cycle has reached.
    ///
    /// - Parameters:
    ///   - runs: The rate and clock of each run the view would build.
    ///   - context: The view's context, in which the frame's requests so far are read.
    @MainActor
    package func outruns(
        nextStepOf runs: [(clock: AnimationClock, frameTicks: Int)], in context: RenderContext
    ) -> Bool {
        guard let start, !runs.isEmpty, !context.isMeasuring,
            let tracker = context.environment.volatileReadTracker, tracker === start.tracker,
            tracker.sideEffects != start.sideEffects,
            let scheduler = context.environment.animationScheduler,
            let next = scheduler.nextFiringDeclaredThisFrame(after: context.environment.frameNowNanos)
        else { return false }
        return next <= context.nextStepNanos(of: runs)
    }
}
