//  🖥️ TUI — A Terminal UI framework for Swift
//  AnimationEnvironment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// The three facts about the frame being rendered that every animation is a
/// function of.
///
/// One value rather than three environment entries, and the reason is measured.
/// ``EnvironmentValues`` is a dictionary that is copied on every environment
/// modification — which is to say constantly, all the way down every tree — so
/// each entry added to it is paid for by every app on every frame whether or
/// not it animates anything. Three of them cost about 1% of a frame on `table`
/// and `deep`; folded into one they cost a third of that, and the grouping is
/// honest anyway: these are one thing, published once, read together.
public struct AnimationFrame: Sendable, Equatable {
    /// The frame's monotonic-clock timestamp, in nanoseconds.
    ///
    /// The *frame's*, not a live reading: one pass may walk the tree more than
    /// once (the app header's height-discovery re-render), and two walks of one
    /// frame must agree on where every animation has got to. It is also the
    /// anchor an animation grid registers against, so the loop's next-firing
    /// query and the grids agree exactly rather than by a clock read apart.
    public var nowNanos: Int64 = 0

    /// How many whole standard animation frames of the replay clock have passed
    /// at this frame: ``AnimationClock/standardFrameTicks`` ticks of 1/60 s, 50 ms,
    /// each.
    ///
    /// What an ``AnimatedCellRun``'s frames are indexed by, so a producer that
    /// pre-renders a cycle can lay its frames out to match what the run loop
    /// will replay. See ``AnimationCycle``.
    ///
    /// A step, not a tick: a tick is 1/60 s, and one step is three of them.
    public var step: Int = 0

    /// Whether this render can be followed by more of them on a timer.
    ///
    /// False outside the run loop — a one-off snapshot (`ViewRenderer`, a frame
    /// dump) renders once and is done. An animation started there would present
    /// its *old* value and never advance, which is strictly worse than not
    /// animating: the picture would be wrong and stay wrong. So changes snap
    /// when this is false.
    public var canAnimate: Bool = false

    /// Creates a frame description. The defaults describe a one-off render at
    /// the start of time, which is what a headless render is.
    public init(nowNanos: Int64 = 0, step: Int = 0, canAnimate: Bool = false) {
        self.nowNanos = nowNanos
        self.step = step
        self.canAnimate = canAnimate
    }
}

private struct AnimationFrameKey: EnvironmentKey, _RenderProjectingEnvironmentKey {
    static var defaultValue: AnimationFrame { AnimationFrame() }

    /// Compared by whether changes may animate, not by the frame's instant
    /// and step, which move every frame: a view that draws from those reads
    /// the frame clock, which records a volatile read, so nothing it drew is
    /// ever stored to be compared (Option C, v4 §4.7). Compared as it stands,
    /// no environment matched a stored one, and no row was ever re-checked
    /// (`Stress --census`: every unequal environment on log, inbox, chat and
    /// residual was this key).
    static func renderProjection(of value: Any) -> (any Equatable)? {
        (value as? AnimationFrame)?.canAnimate
    }
}

extension EnvironmentValues {
    /// What this frame's animations are a function of. See ``AnimationFrame``.
    public var animationFrame: AnimationFrame {
        get { self[AnimationFrameKey.self] }
        set { self[AnimationFrameKey.self] = newValue }
    }

    /// The current frame's monotonic-clock timestamp (ns).
    /// See ``AnimationFrame/nowNanos``.
    public var frameNowNanos: Int64 {
        get { animationFrame.nowNanos }
        set { animationFrame.nowNanos = newValue }
    }

    /// The replay clock's step count for this frame. See ``AnimationFrame/step``.
    public var animationStep: Int {
        get { animationFrame.step }
        set { animationFrame.step = newValue }
    }

    /// Whether a change may animate at all. See ``AnimationFrame/canAnimate``.
    public var canAnimate: Bool {
        get { animationFrame.canAnimate }
        set { animationFrame.canAnimate = newValue }
    }
}
