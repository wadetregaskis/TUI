//  🖥️ TUI — A Terminal UI framework for Swift
//  TimingSampler.swift
//
//  Which measures a learner times: the plain-body memo's (`PlainMemo`) and the
//  body keep's (`BodyKeep`), each with its own count.
//
//  Created by Wade Tregaskis
//  License: MIT

/// Which measures to time: every one through the first passes, while a page's
/// bodies are all being seen, and every 16th after. Two reads of a clock on
/// every measure were 9% of `fanout`'s frame; a sample finds a body that stays
/// slow within a few frames.
///
/// A learner owns its own: the plain memo once asked the body keep's, and with
/// `TUI_KEEP_BODIES=0` learned nothing (f36de2138).
struct TimingSampler {
    /// Whether anything is timed: off, nothing is, so nothing is learned from the
    /// clock. See ``RenderCache/learnsFromTiming``.
    var isOn = true
    private var measuresToNextTiming = 0
    private var passesTimedWhole = 8

    /// Starts a pass.
    mutating func beginPass() {
        if passesTimedWhole > 0 { passesTimedWhole -= 1 }
    }

    /// The instant to time this measure from, if it is sampled.
    @inline(__always)
    mutating func startTiming() -> ContinuousClock.Instant? {
        guard isOn else { return nil }
        if passesTimedWhole == 0 {
            measuresToNextTiming -= 1
            guard measuresToNextTiming < 0 else { return nil }
            measuresToNextTiming = 15
        }
        return ContinuousClock.now
    }
}

extension RenderCache {
    /// Whether the cache's learners read the clock: the body keep, which keeps
    /// the bodies seen to be slow (``BodyKeep``), and the plain memo, which asks
    /// for the composites seen to be heavy (``PlainMemo``). On in an app, where
    /// what is slow on this machine is the point.
    ///
    /// Off, nothing is timed and so nothing is learned: no body is slow and no
    /// composite heavy, on any machine. `HeadlessApp`, and so `TestApp`, turns it
    /// off, since what a test counts must not depend on how fast or loaded its
    /// machine is. CI run 99 (2026-11-09) failed a kept-render count on macOS 27
    /// alone: a type there crossed the plain memo's line mid-test, and a kept
    /// sibling missed once while it moved. A test of the learning itself turns
    /// it back on, and sets the line it means to be over.
    package var learnsFromTiming: Bool {
        get { bodyKeep.learnsFromTiming }
        set {
            bodyKeep.learnsFromTiming = newValue
            plainMemo.learnsFromTiming = newValue
        }
    }
}
