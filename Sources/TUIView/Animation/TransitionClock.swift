//  🖥️ TUI — A Terminal UI framework for Swift
//  TransitionClock.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// A transition's animation on the frame clock: what a view whose arrival a
/// removal interrupts, or whose removal a return interrupts, carries on with.
///
/// SwiftUI neither restarts nor freezes a transition a later change reverses.
/// The interrupted animation runs on to its end, and the new one takes each
/// value from wherever the old one has it at that moment to where the new
/// change sends it: `old(t)` interpolated towards the new end by the new
/// animation's fraction (measured, `Tools/SwiftUIProbes/Transitions/tr5.out`
/// T18 to T24). Inserted under a 2 s linear animation and removed under
/// another at 30%, a `.move(edge: .trailing)` went on towards its place,
/// slowing, turned at about 65% and left the way it came; removed and inserted
/// again at 30%, an `.opacity` went from 0.71 down to 0.59 and back up to 1.
package struct TransitionClock: Sendable, Equatable {
    /// The animation running.
    package let animation: Animation

    /// When it began.
    package let startNanos: Int64

    package init(animation: Animation, startNanos: Int64) {
        self.animation = animation
        self.startNanos = startNanos
    }

    /// How far it has run at `nowNanos`: `1` once it has finished, whatever
    /// its curve last said, as everywhere else an animation ends.
    package func fraction(at nowNanos: Int64) -> Double {
        let elapsed = Double(nowNanos - startNanos) / 1_000_000_000
        return animation.isFinished(at: elapsed) ? 1 : animation.fraction(at: elapsed)
    }
}
