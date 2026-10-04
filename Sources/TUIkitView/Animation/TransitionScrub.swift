//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TransitionScrub.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// A transition's body being drawn part-way between two of its phases.
///
/// A `Transition`'s body is a function of a DISCRETE phase — `.willAppear`,
/// `.identity`, `.didDisappear` — and what moves between two of them is every
/// animatable value the body produces, each interpolated from the value it had
/// at one phase to the value it has at the other. SwiftUI animates each of
/// those values in its render server. Here the frame is rebuilt from the tree,
/// so the body is drawn twice instead:
///
/// 1. **Recorded** at the end phase. Every value the animation store is asked
///    for is noted against its key, and handed back unchanged.
/// 2. **Drawn** at `.identity`. Every value the store is asked for is answered
///    `end.interpolated(towards: identity, amount: presence)` where a record
///    exists, and unchanged where none does.
///
/// That is the store's own arithmetic for an animating value —
/// `from.interpolated(towards: to, amount: curve(t))` — with `presence` already
/// being `curve(t)`, so the picture is the one per-value animation would draw.
///
/// While one is installed on the ``AnimationStore`` it answers EVERY lookup:
/// nothing a scrubbed body asks for is written to, or read from, the store's
/// records, so drawing a transition part-way can neither start an animation
/// nor disturb one. Whatever draws the transition's real content inside the
/// body removes it for the duration (`PlaceholderContentView`), so the
/// content's own animations go on as they would without the transition.
///
/// Main-actor by discipline, like the store it is installed on.
package final class TransitionScrub {
    /// Which of the two passes is being drawn.
    package enum Mode {
        /// Noting the end phase's values.
        case record
        /// Drawing at `.identity`, `presence` of the way from the end phase.
        /// Above 1 while a spring overshoots, which extrapolates.
        case draw(presence: Double)
    }

    /// The pass being drawn.
    package var mode: Mode

    /// The end phase's values, by the key the store would have filed them
    /// under. Type-erased for the reason the store's records are.
    private var ends: [AnimationStore.Key: Any] = [:]

    /// Creates a scrub, ready to record.
    package init() {
        mode = .record
    }

    /// How many values the record pass noted (tests, diagnostics).
    package var recordedCount: Int { ends.count }

    /// The value to draw for `key`, which the tree says is `target`.
    func value<D: VectorArithmetic>(for key: AnimationStore.Key, target: D) -> D {
        switch mode {
        case .record:
            ends[key] = target
            return target
        case .draw(let presence):
            // A value the end phase did not produce — a modifier present at
            // one phase only — is drawn as the `.identity` render has it.
            guard let end = ends[key] as? D else { return target }
            return end.interpolated(towards: target, amount: presence)
        }
    }
}
