//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationRetargetTests.swift
//
//  A change that arrives while an animation is running: SwiftUI's two ways to
//  take over (O3) — a merge that carries the motion on, and additive
//  animations that run side by side.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitView

@Suite("A change that interrupts an animation")
struct AnimationRetargetTests {

    private struct Owner {}

    private let key = AnimationStore.Key(identity: ViewIdentity(path: "Root"), owner: ObjectIdentifier(Owner.self))

    /// The frame timestamps, in nanoseconds.
    private let second: Int64 = 1_000_000_000

    /// A store holding `key` at 0, then animating it to `target` from time 0.
    private func store(animatingTo target: Double, by animation: Animation) -> AnimationStore {
        let store = AnimationStore()
        store.beginRenderPass()
        _ = store.value(for: key, target: 0.0, animation: nil, nowNanos: 0, isMeasuring: false)
        _ = store.value(for: key, target: target, animation: animation, nowNanos: 0, isMeasuring: false)
        return store
    }

    @Test("Interrupting a linear animation runs the two side by side: each covers its own part of the way")
    func additive() {
        let linear = Animation.linear(duration: 1)
        let store = store(animatingTo: 10, by: linear)
        // Half way, at 5, the target moves on to 20.
        let atRetarget = store.value(for: key, target: 20.0, animation: linear, nowNanos: second / 2, isMeasuring: false)
        #expect(atRetarget == 5, "no jump at the retarget")
        // At 1 s the first animation has covered its 10, the second half of its
        // own 10: 15. A restart from 5 at rest would show 12.5.
        let atOne = store.value(for: key, target: 20.0, animation: linear, nowNanos: second, isMeasuring: false)
        #expect(abs(atOne - 15) < 1e-9, "\(atOne)")
        let done = store.value(for: key, target: 20.0, animation: linear, nowNanos: 3 * second / 2, isMeasuring: false)
        #expect(done == 20)
        #expect(!store.isAnimating(at: key, nowNanos: 2 * second))
    }

    @Test("Interrupting a spring merges: the next spring sets off at the speed the value was moving")
    func springMerges() {
        let spring = Animation.spring(duration: 1)
        let interrupted = store(animatingTo: 10, by: spring)
        let at = second / 5
        let presented = interrupted.value(for: key, target: 10.0, animation: spring, nowNanos: at, isMeasuring: false)
        _ = interrupted.value(for: key, target: 20.0, animation: spring, nowNanos: at, isMeasuring: false)
        let frame = second / 60
        let moved = interrupted.value(for: key, target: 20.0, animation: spring, nowNanos: at + frame, isMeasuring: false)

        // The same retarget from rest: a value settled at `presented`.
        let rest = AnimationStore()
        rest.beginRenderPass()
        _ = rest.value(for: key, target: presented, animation: nil, nowNanos: at, isMeasuring: false)
        _ = rest.value(for: key, target: 20.0, animation: spring, nowNanos: at, isMeasuring: false)
        let fromRest = rest.value(for: key, target: 20.0, animation: spring, nowNanos: at + frame, isMeasuring: false)

        #expect(moved - presented > fromRest - presented, "it kept its momentum: \(moved) against \(fromRest)")
        // And it still arrives.
        #expect(abs(interrupted.value(for: key, target: 20.0, animation: spring, nowNanos: 10 * second, isMeasuring: false) - 20) < 1e-6)
    }

    @Test("The loop runs until every animation is done, an earlier one outlasting a later")
    func earlierOutlasts() {
        let slow = Animation.linear(duration: 2)
        let store = store(animatingTo: 10, by: slow)
        _ = store.value(for: key, target: 11.0, animation: .linear(duration: 0.1), nowNanos: second / 2, isMeasuring: false)
        // At 1 s the later animation has finished; the earlier one has not.
        #expect(store.hasLiveAnimations(at: second))
        #expect(store.isAnimating(at: key, nowNanos: second))
        let value = store.value(for: key, target: 11.0, animation: nil, nowNanos: second, isMeasuring: false)
        #expect(value < 11, "still on its way: \(value)")
        #expect(store.value(for: key, target: 11.0, animation: nil, nowNanos: 3 * second, isMeasuring: false) == 11)
        #expect(!store.hasLiveAnimations(at: 4 * second))
    }
}
