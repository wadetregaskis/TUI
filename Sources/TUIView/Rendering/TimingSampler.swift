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
    private var measuresToNextTiming = 0
    private var passesTimedWhole = 8

    /// Starts a pass.
    mutating func beginPass() {
        if passesTimedWhole > 0 { passesTimedWhole -= 1 }
    }

    /// The instant to time this measure from, if it is sampled.
    @inline(__always)
    mutating func startTiming() -> ContinuousClock.Instant? {
        if passesTimedWhole == 0 {
            measuresToNextTiming -= 1
            guard measuresToNextTiming < 0 else { return nil }
            measuresToNextTiming = 15
        }
        return ContinuousClock.now
    }
}
