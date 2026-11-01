//  🖥️ TUI — A Terminal UI framework for Swift
//  AnimationCompletionTracker.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// Which animations a change started, and when the completions registered with
/// it are due.
///
/// A completion is registered on a ``Transaction``; the transaction is stamped
/// on the state change made under it; the run loop renders that change in one
/// pass. "The animations created with this transaction" are therefore the ones
/// that pass starts, and only the stores know which those are — so while a
/// pass with completions to place is under way, the `AnimationStore` and the
/// `DepartureStore` report every animation they start to this, and at the end
/// of the pass the completions go into a batch with the deadlines those
/// animations set.
///
/// - **No animation started:** the batch fires at the end of the pass — the
///   change is on screen, and nothing about it is still moving.
/// - **`.logicallyComplete`:** when the latest logical completion of the
///   started animations has passed (``Animation/logicalCompletionDuration``).
///   An animation started by a later change does not move it.
/// - **`.removed`:** when the latest end has passed AND none of the values the
///   pass started is still animating — a later change that retargets one of
///   them makes this wait for the new animation too, as SwiftUI documents.
///
/// A value the tree stops asking about has been removed, so a batch whose
/// values have all gone fires whatever its deadlines say (a `repeatForever`
/// animation removed with its view is complete; one still on screen never is).
///
/// Not `Sendable`, like the stores it serves: the compiler keeps it on the
/// render path that holds it, which is on the main actor.
public final class AnimationCompletionTracker {
    private struct Batch {
        var completions: [AnimationCompletion]
        /// The values the pass started animating.
        var keys: [AnimationStore.Key] = []
        /// When the latest of them logically completes; `nil` while none has
        /// started, and `.max` once one never will.
        var logicalDeadline: Int64?
        /// When the latest of them ends, likewise.
        var endDeadline: Int64?

        var startedAny: Bool { endDeadline != nil }
    }

    /// The pass in progress, when it has completions to place.
    private var collecting: Batch?

    /// Batches waiting on their animations.
    private var waiting: [Batch] = []

    /// Creates a tracker with nothing to place.
    public init() {}

    /// Whether a pass is collecting the animations it starts — the one check
    /// a store makes before reporting, so a pass without completions pays a
    /// load and a branch per animation started, and none per value read.
    package var isCollecting: Bool { collecting != nil }

    /// Whether any completion is still waiting (tests, diagnostics).
    package var hasWaiting: Bool { !waiting.isEmpty }

    /// Starts a pass that must place `completions`. Nothing to place, nothing
    /// collected.
    ///
    /// Called again within a pass for each walk made again for what the
    /// effects wrote (`FrameSettling`), with the completions of the changes
    /// they made: those join the pass's batch, which still waits on what the
    /// walks before started, rather than replacing it.
    package func beginPass(placing completions: [AnimationCompletion]) {
        guard !completions.isEmpty else { return }
        guard var batch = collecting else {
            collecting = Batch(completions: completions)
            return
        }
        batch.completions.append(contentsOf: completions)
        collecting = batch
    }

    /// Reports an animation the pass started at `nowNanos`, on the value at
    /// `key` (`nil` for a departure, which is played rather than stored).
    package func noteStarted(_ animation: Animation, at nowNanos: Int64, key: AnimationStore.Key?) {
        guard var batch = collecting else { return }
        if let key { batch.keys.append(key) }
        batch.logicalDeadline = max(
            batch.logicalDeadline ?? .min, deadline(nowNanos, animation.logicalCompletionDuration))
        batch.endDeadline = max(batch.endDeadline ?? .min, deadline(nowNanos, animation.totalDuration))
        collecting = batch
    }

    /// Ends the pass: its completions fire now if it started nothing, and wait
    /// otherwise. Then fires whatever has come due. Called after the stores
    /// have pruned what the tree stopped asking about.
    @MainActor
    package func endPass(at nowNanos: Int64, animations: AnimationStore) {
        if let batch = collecting {
            collecting = nil
            if batch.startedAny {
                waiting.append(batch)
            } else {
                batch.completions.forEach { $0.fire() }
            }
        }
        fireDue(at: nowNanos, animations: animations)
    }

    /// Fires every waiting completion whose criteria are met at `nowNanos`.
    @MainActor
    private func fireDue(at nowNanos: Int64, animations: AnimationStore) {
        guard !waiting.isEmpty else { return }
        var stillWaiting: [Batch] = []
        for var batch in waiting {
            let removed =
                !batch.keys.isEmpty && batch.keys.allSatisfy { !animations.hasRecord(at: $0) }
            let logical = removed || nowNanos >= (batch.logicalDeadline ?? .max)
            let ended =
                removed
                || (nowNanos >= (batch.endDeadline ?? .max)
                    && !batch.keys.contains { animations.isAnimating(at: $0, nowNanos: nowNanos) })
            batch.completions.removeAll { completion in
                guard completion.criteria.waitsForRemoval ? ended : logical else { return false }
                completion.fire()
                return true
            }
            if !batch.completions.isEmpty { stillWaiting.append(batch) }
        }
        waiting = stillWaiting
    }

    /// `nowNanos` plus `seconds`, or `.max` for an animation that never gets
    /// there.
    private func deadline(_ nowNanos: Int64, _ seconds: Double?) -> Int64 {
        guard let seconds, seconds.isFinite else { return .max }
        return nowNanos &+ Int64((seconds * 1_000_000_000).rounded(.up))
    }
}
