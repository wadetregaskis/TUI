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

    @Test("An interpolating spring does not merge: the two springs add, each covering its own part of the way")
    func interpolatingSpringAdds() {
        let spring = Animation.interpolatingSpring(duration: 1)
        let store = store(animatingTo: 10, by: spring)
        let at = second / 5
        _ = store.value(for: key, target: 20.0, animation: spring, nowNanos: at, isMeasuring: false)
        for nanos in [at + second / 10, second / 2, second] {
            let value = store.value(for: key, target: 20.0, animation: spring, nowNanos: nanos, isMeasuring: false)
            // The first spring's last 10 still to come, and the second's.
            let first = 10 * (1 - spring.fraction(at: Double(nanos) / 1e9))
            let later = 10 * (1 - spring.fraction(at: Double(nanos - at) / 1e9))
            #expect(abs(value - (20 - first - later)) < 1e-9, "\(value) at \(nanos)")
        }
    }

    @Test("An earlier animation that ends back where it started stops counting once it ends")
    func finishedEarlierStopsCounting() {
        // Out and back: it ends at its start, and SwiftUI snaps the value to
        // the target when it does (p11).
        let store = store(animatingTo: 10, by: Animation.linear(duration: 0.2).repeatCount(2, autoreverses: true))
        let later = Animation.linear(duration: 1)
        _ = store.value(for: key, target: 20.0, animation: later, nowNanos: second / 10, isMeasuring: false)
        // At 0.5 s the first is over; the second is 0.4 of the way from 10.
        let value = store.value(for: key, target: 20.0, animation: later, nowNanos: second / 2, isMeasuring: false)
        #expect(abs(value - 14) < 1e-9, "\(value)")
    }

    @Test("Retargeting again and again keeps only the earlier animations still running")
    func finishedEarlierIsDropped() {
        let quick = Animation.linear(duration: 0.1)
        let store = store(animatingTo: 1, by: quick)
        // A change every 1/20 s, each animation lasting two of them.
        for step in 1...200 {
            _ = store.value(
                for: key, target: Double(step + 1), animation: quick, nowNanos: Int64(step) * second / 20,
                isMeasuring: false)
        }
        #expect((store.earlierCount(at: key) ?? 0) <= 2, "\(store.earlierCount(at: key) ?? -1)")
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
