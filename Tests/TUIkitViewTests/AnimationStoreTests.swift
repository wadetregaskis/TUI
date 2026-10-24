//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationStoreTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitView

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

    @Test("An even-count autoreverse settles where it ended — no later snap to the target")
    func evenAutoreverseSettlesAtItsEnd() {
        let store = AnimationStore()
        let key = makeKey()
        store.beginRenderPass()

        // First sight does not animate.
        #expect(store.value(for: key, target: 0.0, animation: nil, nowNanos: 0, isMeasuring: false) == 0.0)

        // Out and back: 0 → 1 → 0 over 0.2 s.
        let animation = Animation.linear(duration: 0.1).repeatCount(2, autoreverses: true)
        _ = store.value(for: key, target: 1.0, animation: animation, nowNanos: 0, isMeasuring: false)

        // Mid-flight sanity: the first pass heads out.
        let mid = store.value(
            for: key, target: 1.0, animation: animation, nowNanos: second / 20, isMeasuring: false)
        #expect(mid > 0.0)

        // The finish frame: fraction 0, back at the start.
        let finished = store.value(
            for: key, target: 1.0, animation: animation, nowNanos: second / 2, isMeasuring: false)
        #expect(finished == 0.0)

        // An unrelated render much later must keep showing what the last
        // animated frame showed — the retirement used to store the TARGET,
        // snapping the picture from 0 to 1 here.
        let later = store.value(
            for: key, target: 1.0, animation: animation, nowNanos: 60 * second, isMeasuring: false)
        #expect(later == 0.0, "the settled picture snapped to the target")

        // And an unchanged re-declaration must NOT restart the animation.
        let evenLater = store.value(
            for: key, target: 1.0, animation: animation, nowNanos: 61 * second, isMeasuring: false)
        #expect(evenLater == 0.0)
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

    @Test("A new value after an even-autoreverse settle animates from the settled picture")
    func retargetAfterSettleStartsFromSettled() {
        let store = AnimationStore()
        let key = makeKey()
        store.beginRenderPass()

        #expect(store.value(for: key, target: 0.0, animation: nil, nowNanos: 0, isMeasuring: false) == 0.0)
        let bounce = Animation.linear(duration: 0.1).repeatCount(2, autoreverses: true)
        _ = store.value(for: key, target: 1.0, animation: bounce, nowNanos: 0, isMeasuring: false)
        _ = store.value(for: key, target: 1.0, animation: bounce, nowNanos: second / 2, isMeasuring: false)

        // Retarget to 2.0 with a fresh linear fade: the first frame presents
        // the settled 0.0 (retargeting starts from where the picture IS), and
        // the midpoint is 1.0 — from 0, not from the old target 1.
        let start = store.value(
            for: key, target: 2.0, animation: .linear(duration: 0.1),
            nowNanos: second, isMeasuring: false)
        #expect(start == 0.0)
        let mid = store.value(
            for: key, target: 2.0, animation: .linear(duration: 0.1),
            nowNanos: second + second / 20, isMeasuring: false)
        #expect(abs(mid - 1.0) < 0.0001)
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

    @Test("An even autoreverse settled away from its target keeps the store from presenting every target")
    func displacedSettleIsUnsettled() {
        let store = AnimationStore()
        let key = makeKey()
        store.beginRenderPass()
        _ = store.value(for: key, target: 0.0, animation: nil, nowNanos: 0, isMeasuring: false)
        let bounce = Animation.linear(duration: 0.1).repeatCount(2, autoreverses: true)
        _ = store.value(for: key, target: 1.0, animation: bounce, nowNanos: 0, isMeasuring: false)
        _ = store.value(for: key, target: 1.0, animation: bounce, nowNanos: second, isMeasuring: false)
        // Retired, presenting 0 where the tree says 1: a measure must still ask.
        #expect(!store.presentsEveryTarget)
        #expect(store.value(for: key, target: 1.0, animation: nil, nowNanos: 2 * second, isMeasuring: true) == 0.0)

        // Dropped when the tree stops asking: nothing is left to present otherwise.
        store.beginRenderPass()
        store.endRenderPass()
        #expect(!store.hasRecord(at: key))
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
}
