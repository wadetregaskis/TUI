//  🖥️ TUI — A Terminal UI framework for Swift
//  AnimationStoreTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIView

/// The store's settling behaviour: what a finished animation leaves on screen
/// must be what every later frame keeps showing.
@Suite("AnimationStore settling")
struct AnimationStoreTests {

    private struct Owner {}

    private func makeKey() -> AnimationStore.Key {
        AnimationStore.Key(
            identity: ViewIdentity(path: "Root"), owner: ObjectIdentifier(Owner.self))
    }

    /// The frame timestamps, in nanoseconds.
    private let second: Int64 = 1_000_000_000

    @Test("An even-count autoreverse plays out and back, then shows its target, as SwiftUI's does (p11)")
    func evenAutoreverseEndsAtItsTarget() {
        let store = AnimationStore()
        let key = makeKey()
        store.beginRenderPass()

        // First sight does not animate.
        #expect(store.value(for: key, target: 0.0, animation: nil, nowNanos: 0, isMeasuring: false) == 0.0)

        // Out and back: 0 → 1 → 0 over 0.2 s.
        let animation = Animation.linear(duration: 0.1).repeatCount(2, autoreverses: true)
        _ = store.value(for: key, target: 1.0, animation: animation, nowNanos: 0, isMeasuring: false)

        // Mid-flight sanity: the first pass heads out, the second comes back.
        let out = store.value(
            for: key, target: 1.0, animation: animation, nowNanos: second / 20, isMeasuring: false)
        #expect(out > 0.0)
        let back = store.value(
            for: key, target: 1.0, animation: animation, nowNanos: second * 3 / 20, isMeasuring: false)
        #expect(back > 0.0 && back < 1.0)

        // Over: the target, where SwiftUI's snaps once the passes have played
        // (`Tools/SwiftUIProbes/Animation curves, springs and keyframes/p11.out`).
        let finished = store.value(
            for: key, target: 1.0, animation: animation, nowNanos: second / 2, isMeasuring: false)
        #expect(finished == 1.0)
        #expect(store.presentsEveryTarget, "retired at its target")

        // And it stays there, an unchanged re-declaration restarting nothing.
        let later = store.value(
            for: key, target: 1.0, animation: animation, nowNanos: 60 * second, isMeasuring: false)
        #expect(later == 1.0)
    }

    @Test("A plain animation settles at its target")
    func plainAnimationSettlesAtTarget() {
        let store = AnimationStore()
        let key = makeKey()
        store.beginRenderPass()

        #expect(store.value(for: key, target: 0.0, animation: nil, nowNanos: 0, isMeasuring: false) == 0.0)
        let animation = Animation.linear(duration: 0.1)
        _ = store.value(for: key, target: 1.0, animation: animation, nowNanos: 0, isMeasuring: false)

        let finished = store.value(
            for: key, target: 1.0, animation: animation, nowNanos: second, isMeasuring: false)
        #expect(finished == 1.0)
        let later = store.value(
            for: key, target: 1.0, animation: animation, nowNanos: 60 * second, isMeasuring: false)
        #expect(later == 1.0)
    }

    @Test("A new value after an even-autoreverse settle animates from its target")
    func retargetAfterSettleStartsFromTarget() {
        let store = AnimationStore()
        let key = makeKey()
        store.beginRenderPass()

        #expect(store.value(for: key, target: 0.0, animation: nil, nowNanos: 0, isMeasuring: false) == 0.0)
        let bounce = Animation.linear(duration: 0.1).repeatCount(2, autoreverses: true)
        _ = store.value(for: key, target: 1.0, animation: bounce, nowNanos: 0, isMeasuring: false)
        _ = store.value(for: key, target: 1.0, animation: bounce, nowNanos: second / 2, isMeasuring: false)

        // Retarget to 2.0 with a fresh linear fade: it starts from the 1.0 the
        // settled picture shows, and the midpoint is 1.5.
        let start = store.value(
            for: key, target: 2.0, animation: .linear(duration: 0.1),
            nowNanos: second, isMeasuring: false)
        #expect(start == 1.0)
        let mid = store.value(
            for: key, target: 2.0, animation: .linear(duration: 0.1),
            nowNanos: second + second / 20, isMeasuring: false)
        #expect(abs(mid - 1.5) < 0.0001)
    }

    @Test("The store presents every target until something runs, and again once it settles at its target")
    func presentsEveryTargetFollowsWhatRuns() {
        let store = AnimationStore()
        let key = makeKey()
        store.beginRenderPass()
        #expect(store.presentsEveryTarget, "an empty store")

        _ = store.value(for: key, target: 0.0, animation: nil, nowNanos: 0, isMeasuring: false)
        #expect(store.presentsEveryTarget, "a first sight settles at its target")

        // A measure starts nothing, so it unsettles nothing.
        let animation = Animation.linear(duration: 0.1)
        _ = store.value(for: key, target: 1.0, animation: animation, nowNanos: 0, isMeasuring: true)
        #expect(store.presentsEveryTarget)

        _ = store.value(for: key, target: 1.0, animation: animation, nowNanos: 0, isMeasuring: false)
        #expect(!store.presentsEveryTarget, "running")
        _ = store.value(for: key, target: 1.0, animation: animation, nowNanos: second, isMeasuring: false)
        #expect(store.presentsEveryTarget, "retired at its target")

        // An unanimated change jumps, and stays settled.
        _ = store.value(for: key, target: 3.0, animation: nil, nowNanos: 2 * second, isMeasuring: false)
        #expect(store.presentsEveryTarget)
    }

    @Test("A scrub answers every lookup, so the store does not present every target while one draws")
    func scrubIsNotSettled() {
        let store = AnimationStore()
        store.scrub = TransitionScrub()
        #expect(!store.presentsEveryTarget)
        store.scrub = nil
        #expect(store.presentsEveryTarget)
    }

    @Test("An arrival retires once its animation is over, at what it presented")
    func arrivalRetires() {
        let store = AnimationStore()
        let key = makeKey()
        store.beginRenderPass()
        let animation = Animation.linear(duration: 0.1)
        #expect(store.arrivalPhase(for: key, animation: animation, nowNanos: 0, isMeasuring: false) == 0)
        #expect(!store.presentsEveryTarget)
        #expect(store.arrivalPhase(for: key, animation: animation, nowNanos: second / 20, isMeasuring: false) == 0.5)
        #expect(store.arrivalPhase(for: key, animation: animation, nowNanos: second, isMeasuring: false) == 1)
        #expect(store.presentsEveryTarget)
        #expect(store.arrivalPhase(for: key, animation: animation, nowNanos: 2 * second, isMeasuring: false) == 1)
    }

    /// What a memo keeps for good, the keys it declared, holds them and not the
    /// capacity the log had grown to for a whole page that was logged before it.
    @Test("A memo's declared records don't keep the log's capacity")
    func declaredRecordsAreExact() throws {
        let store = AnimationStore()
        let page = store.beginLogging()
        let keys = Array(repeating: makeKey(), count: 300)
        store.declareAgain(AnimationStore.DeclaredRecords(keys))
        #expect(store.endLogging(from: page)?.keys.count == 300)

        let row = store.beginLogging()
        store.declareAgain(AnimationStore.DeclaredRecords([makeKey()]))
        let declared = try #require(store.endLogging(from: row))
        #expect(declared.keys.count == 1)
        #expect(declared.keys.capacity < 8, "\(declared.keys.capacity)")
    }
}
