//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollGlide.swift
//
//  A programmatic scroll made inside an animation, on its way: the distance
//  it has still to travel, stepped a whole line at a time along the
//  animation's curve, once a frame (decisions B27-ANIMATING; the design is
//  `Documentation/SwiftUI parity/Decisions/Scrolling/Animated scrolling, a
//  design (B27).md`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - The glide

/// A programmatic scroll that is gliding to its target rather than jumping
/// there: a `scrollTo` or a ``ScrollPosition`` write made inside
/// `withAnimation`.
///
/// **A distance, not a destination.** The drawn offset stays the scrollable's
/// own `scrollOffset`, which keys, the wheel and every render go on reading as
/// they always have; this is how far that offset still has to travel. Each
/// frame moves it by what the curve has added since the last one, so whatever
/// else moves the offset meanwhile — rows arriving above the top row, which the
/// top-row hold follows — moves the destination with it. The landing then
/// applies the request once more, without animation, which corrects whatever a
/// distance could not know of (``Landing``).
///
/// It is not an `AnimationStore` value. That store's values move with no
/// thought for the event-time code that moves a scroll offset too, a new
/// target with no animation in force jumps there, and its live values hold the
/// 30 Hz lattice open, where a glide wants a frame only on the 1/60 s ticks at
/// which its line changes (the design note, §1).
///
/// Opaque outside the framework: the requirement it fills on
/// ``ScrollableOffsetState`` is public because the protocol is.
public struct ScrollGlide: Sendable {
    /// What a glide applies once more when it lands, without animation: the
    /// request it was started by.
    package enum Landing: Sendable, Hashable {
        /// A `scrollTo` or a ``ScrollPosition`` row request, sought again: rows
        /// that arrived between the viewport and the row while the glide ran,
        /// or estimated heights the frames in between were drawn at, leave the
        /// distance short or long by however far that moved the row.
        case seek(ScrollToRequest)
        /// A `List`'s or a `Table`'s row request, sought again from the row it
        /// was found at: that row is looked at first, and the rows searched
        /// for the key only when it no longer holds it. A list finds a key by
        /// asking its rows in order, so a second search would cost the request
        /// over again.
        case listSeek(ScrollToRequest, row: Int)
        /// A ``ScrollPosition`` offset along the glide's axis, clamped again.
        case offset(Int)
        /// The start of the glide's axis: the top, or the leading edge.
        case top
        /// The end of the glide's axis: the bottom, through the End key's tail
        /// seek, so rows that arrived during the glide are followed from the
        /// landing on; or the trailing edge.
        case bottom
        /// Nothing: a page key's glide lands where its distance takes it, as
        /// the key would have put the view (`scrollKeyboardAnimation(_:)`).
        case distance
        /// A list's place, put back exactly: its top row, and the lines of it
        /// scrolled off the top. A list glides a row at a time; this is the
        /// line within a tall row a key or a request left it on.
        case rowPosition(row: Int, subRowLines: Int)
    }

    /// How far the glide travels, in the scrollable's offset unit: lines, for
    /// a `ScrollView`, columns for its horizontal axis, and rows for a `List`
    /// or a `Table`.
    package let distance: Int

    /// How much of ``distance`` the frames so far have stepped the offset by.
    /// Less than the curve says where an edge stopped a step: a spring's
    /// overshoot is clamped at the ends of the content, and what it would have
    /// gone past by is never stepped back.
    package var covered = 0

    /// The animation the glide moves with: its first pass only
    /// (``Animation/firstPass``).
    package let animation: Animation

    /// When the glide started, on the frame clock.
    package private(set) var startNanos: Int64

    /// What the landing applies.
    package let landing: Landing

    /// The viewport the glide started in. A resize lands it at once, before
    /// anything that settles a resize — a scroll target behaviour putting the
    /// view back on a page — sees the offset.
    package private(set) var viewport: CellSize

    /// Whether a key started it, under `scrollKeyboardAnimation(_:)`, rather
    /// than a request made inside `withAnimation`. A key's glide is the user's
    /// scroll: the view is ``ScrollPhase/interacting`` through it, a scroll
    /// key pressed during it counts from its target, and its quiet is counted
    /// from its landing.
    package let isKeyboard: Bool

    /// Whether it waits for its first frame to start: a key's, made at event
    /// time, has no frame clock to start on and no viewport to start in, and
    /// takes both from the frame that draws its start.
    package private(set) var awaitsFirstFrame: Bool

    package init(distance: Int, animation: Animation, startNanos: Int64, landing: Landing, viewport: CellSize) {
        self.distance = distance
        self.animation = animation.firstPass
        self.startNanos = startNanos
        self.landing = landing
        self.viewport = viewport
        isKeyboard = false
        awaitsFirstFrame = false
    }

    /// A key's glide of `distance`, made at event time: it starts on the next
    /// frame (``awaitsFirstFrame``).
    package init(keyDistance distance: Int, animation: Animation, landing: Landing) {
        self.distance = distance
        self.animation = animation.firstPass
        startNanos = 0
        self.landing = landing
        viewport = CellSize(width: 0, height: 0)
        isKeyboard = true
        awaitsFirstFrame = true
    }

    /// Starts a glide that waited for its first frame (``awaitsFirstFrame``)
    /// at `nanos`, in `viewport`.
    mutating func start(atNanos nanos: Int64, in viewport: CellSize) {
        startNanos = nanos
        self.viewport = viewport
        awaitsFirstFrame = false
    }

    /// Seconds since the glide started, at `nanos` on the frame clock.
    private func elapsed(atNanos nanos: Int64) -> Double {
        Double(nanos &- startNanos) / 1_000_000_000
    }

    /// Whether the animation has finished by `nanos`.
    ///
    /// In whole nanoseconds, rounded up, where the animation knows its length:
    /// the deadline the completion tracker gives a `withAnimation` completion
    /// is that instant (`AnimationCompletionTracker`), and a landing a
    /// nanosecond before it is the glide's last frame, after which nothing
    /// would draw the frame that fires it.
    package func isFinished(atNanos nanos: Int64) -> Bool {
        guard let total = animation.totalDuration else { return animation.isFinished(at: elapsed(atNanos: nanos)) }
        return nanos &- startNanos >= Int64((total * 1_000_000_000).rounded(.up))
    }

    /// How much of the distance the curve has travelled by `nanos`, in whole
    /// lines: the line the glide is drawn on.
    package func place(atNanos nanos: Int64) -> Int {
        Int((Double(distance) * animation.fraction(at: elapsed(atNanos: nanos))).rounded())
    }

    /// The first 1/60 s tick after `nanos` at which the glide is drawn on
    /// another line, or at which it finishes and lands: the only ticks it
    /// needs a frame on. A five-line glide asks for five frames and its
    /// landing, not for every tick the animation lasts.
    ///
    /// Found by sampling the curve forward a tick at a time — a few
    /// evaluations on most frames; up to the end of the animation on the frame
    /// of its last visible change, which for the default spring is a few dozen.
    /// Never more than ``searchTicks`` on one frame: an animation that finishes
    /// further off than that, or never (a custom one), is asked again from the
    /// tick that ends the search.
    package func nextFrameNanos(after nanos: Int64) -> Int64 {
        let current = place(atNanos: nanos)
        var tick = AnimationClock.tick(atNanoseconds: nanos) &+ 1
        for _ in 0..<Self.searchTicks {
            let instant = AnimationClock.nanoseconds(atTick: tick)
            if isFinished(atNanos: instant) || place(atNanos: instant) != current { return instant }
            tick &+= 1
        }
        return AnimationClock.nanoseconds(atTick: tick)
    }

    /// The longest a glide looks ahead on one frame for its next one: a
    /// second.
    static var searchTicks: Int { AnimationClock.ticksPerSecond }
}

// MARK: - The animation in force

extension RenderContext {
    /// The animation a programmatic scroll on this frame glides with, or
    /// `nil` when it jumps.
    ///
    /// The frame's transaction's animation, as for every other change: it is
    /// the transaction the request was made under, which the run loop
    /// publishes for exactly the frame that consumes it. `nil` without a
    /// scheduler — a one-off render would draw the start and never advance —
    /// and under reduce motion, which holds still what moves in X and Y, a
    /// scroll offset among it (decisions A-D3M-1). `ChildGlide`'s rule.
    /// Asked on the frames that carry a request only.
    @MainActor
    package var scrollGlideAnimation: Animation? {
        scrollGlideAnimation(environment.transaction.effectiveAnimation)
    }

    /// `animation`, or `nil` where a scroll may not glide: without a scheduler
    /// or under reduce motion (``scrollGlideAnimation``). The keys' animation
    /// (`scrollKeyboardAnimation(_:)`) is held to the same rule.
    @MainActor
    package func scrollGlideAnimation(_ animation: Animation?) -> Animation? {
        environment.scrollGlideAnimation(animation)
    }
}

extension EnvironmentValues {
    /// `animation`, or `nil` where a scroll may not glide: without a scheduler
    /// or under reduce motion — `RenderContext.scrollGlideAnimation(_:)`'s rule,
    /// for a view that captures it from the environment alone (a list's frame
    /// inputs).
    package func scrollGlideAnimation(_ animation: Animation?) -> Animation? {
        guard let animation, animationFrame.canAnimate, !accessibilityReduceMotion else { return nil }
        return animation
    }
}

// MARK: - Stepping a glide

extension ScrollableOffsetState {
    /// Starts gliding from the offset as it stands to `target`, with
    /// `animation`, landing as `landing` says — or does nothing, and answers
    /// `false`, when the offset is already there. The offset is not moved:
    /// the frame that starts a glide draws its start.
    ///
    /// Replaces any glide in flight, so a second request glides from where
    /// the first had got to, from rest. Drops any overscroll excursion, as a
    /// jump does: a request aims at an exact line. Tells the pass's completion
    /// tracker, so `withAnimation(_:_:completion:)` fires when the animation
    /// ends, as for any other animation the change started.
    @MainActor
    package func beginGlide(
        to target: Int, animation: Animation, landing: ScrollGlide.Landing, viewport: CellSize,
        context: RenderContext
    ) -> Bool {
        let distance = target - scrollOffset
        guard distance != 0 else { return false }
        let now = context.environment.frameNowNanos
        glide = ScrollGlide(
            distance: distance, animation: animation, startNanos: now, landing: landing, viewport: viewport)
        clearOverscroll()
        context.stateStorage?.animationCompletions.noteStarted(animation.firstPass, at: now, key: nil)
        return true
    }

    /// Moves a glide in flight to this frame's line, before the content is
    /// drawn, and answers what to apply when it has landed: once its animation
    /// has finished, or at once when the viewport is no longer the one it
    /// started in. Landing steps the rest of the distance first, so the
    /// landing's re-application starts from the target.
    ///
    /// Render passes only. The caller tests for a glide first, so a
    /// scrollable at rest pays that one test.
    ///
    /// The steps go through ``scrollFine(by:)``, clamped at the content's
    /// ends, and are counted in the offset they moved: the unit a `ScrollView`
    /// steps in. A scrollable whose glide moves in another unit than its fine
    /// step — a list, whose glide steps whole rows where its fine step is a
    /// line — passes `step`, which moves the view by a number of its units
    /// and answers how far it went.
    ///
    /// A key's glide starts here, on the frame after the key: this frame
    /// draws its start, and its clock and viewport are this frame's.
    @MainActor
    package func advanceGlide(
        viewport: CellSize, context: RenderContext, step: ((Int) -> Int)? = nil
    ) -> ScrollGlide.Landing? {
        guard var current = glide, !context.isMeasuring else { return nil }
        let now = context.environment.frameNowNanos
        if current.awaitsFirstFrame {
            current.start(atNanos: now, in: viewport)
            glide = current
            return nil
        }
        let lands = current.viewport != viewport || current.isFinished(atNanos: now)
        let delta = (lands ? current.distance : current.place(atNanos: now)) - current.covered
        if delta != 0 {
            if let step {
                current.covered += step(delta)
            } else {
                let before = scrollOffset
                scrollFine(by: delta)
                current.covered += scrollOffset - before
            }
        }
        glide = lands ? nil : current
        return lands ? current.landing : nil
    }

    /// Asks for the frame a glide in flight next needs — the tick its line
    /// next changes on, or the one it lands on — and so declares this frame's
    /// drawing time-varying, which keeps any memo above from serving a frame
    /// of it after the glide has moved on. Render passes only, and the caller
    /// tests for a glide first.
    ///
    /// `axis` tells apart the wakes of two glides one view runs at once, its
    /// rows' and its columns': each asks for its own frames.
    @MainActor
    package func requestGlideFrame(context: RenderContext, axis: String = "") {
        guard let glide, !context.isMeasuring else { return }
        context.requestWake(
            token: "scroll-glide\(axis)-\(context.identity.path)",
            atNanos: glide.nextFrameNanos(after: context.environment.frameNowNanos))
    }
}

// MARK: - Keys that glide

extension ScrollableOffsetState {
    /// Runs the scroll key `move` — Page Up/Down, Home, End — as a glide with
    /// `animation`, landing as `landing` says, or as the jump it is when
    /// `animation` is `nil` (`scrollKeyboardAnimation(_:)`, unset or under
    /// reduce motion). Event time.
    ///
    /// The key moves the view as it always has — the scroll target behaviour,
    /// the edge anchors and the tail seek all applied — and the offset is then
    /// put back where the view is drawn and the distance kept, for the next
    /// frame to start gliding (``ScrollGlide/awaitsFirstFrame``). A key's glide
    /// in flight lands first, so the key counts from its target and N presses
    /// move exactly N pages. A key that moved nothing, or pushed into an
    /// overscroll allowance — a line or two, shown at once — does not glide.
    ///
    /// The key is the user's scroll (it stops a programmatic glide where it
    /// stands, as any does), so the view stays ``ScrollPhase/interacting``.
    package func glideKey(with animation: Animation?, landing: ScrollGlide.Landing, _ move: () -> Void) {
        let drawn = scrollOffset
        landKeyboardGlide()
        let excursion = overscrollState.excursion
        move()
        guard let animation, scrollOffset != drawn, overscrollState.excursion == excursion else { return }
        let distance = scrollOffset - drawn
        scrollOffset = drawn
        glide = ScrollGlide(keyDistance: distance, animation: animation, landing: landing)
    }

    /// Lands a key's glide in flight at its target at once — a scroll key
    /// pressed during it counts from where it is going, not from where it is
    /// drawn — and leaves a programmatic one, which the key's own user scroll
    /// stops where it stands. Event time.
    package func landKeyboardGlide() {
        guard let current = glide, current.isKeyboard else { return }
        glide = nil
        let rest = current.distance - current.covered
        if rest != 0 { scrollFine(by: rest) }
    }
}
