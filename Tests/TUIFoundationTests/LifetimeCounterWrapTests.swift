//  🖥️ TUI — A Terminal UI framework for Swift
//  LifetimeCounterWrapTests.swift
//
//  The caches' lifetime statistics wrap at `Int.max` rather than trap (hunt
//  H-52, XPLAT-1). On wasm32 `Int` is 32 bits, and a screen walked every frame
//  reaches 2^31 lookups in days, or hours on a big page: a checked add there
//  ended the app. A counter set near the top through the test seam (`stats`'
//  internal setter) and stepped past it stands in for those days on every
//  platform.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

@MainActor
@Suite("Lifetime counters wrap")
struct LifetimeCounterWrapTests {

    @Test("A lookup past Int.max wraps the cache's hit and miss counts")
    func lookupsWrap() {
        let cache = RenderCache()
        let identity = ViewIdentity(path: "Root/View")
        cache.store(identity: identity, view: "A", buffer: FrameBuffer(text: "a"), contextWidth: 80, contextHeight: 24)
        cache.stats.hits = .max - 1
        cache.stats.misses = .max - 1
        cache.stats.stores = .max
        cache.rowWork.rendered = .max
        let before = cache.stats
        for _ in 0..<2 {
            _ = cache.lookup(identity: identity, view: "A", contextWidth: 80, contextHeight: 24)
            _ = cache.lookup(identity: identity, view: "B", contextWidth: 80, contextHeight: 24)
        }
        cache.store(identity: identity, view: "A", buffer: FrameBuffer(text: "a"), contextWidth: 80, contextHeight: 24)
        #expect(cache.stats.hits == .min)
        #expect(cache.stats.misses == .min)
        #expect(cache.stats.stores == .min)
        // A frame's reading is a difference of two totals: it stays right across the wrap.
        let delta = cache.stats.delta(since: before)
        #expect(delta.hits == 2)
        #expect(delta.misses == 2)
        #expect(delta.stores == 1)
        #expect(delta.lookups == 4)
    }

    @Test("A row-work reading across the wrap is the work done")
    func rowWorkDeltaWraps() {
        let earlier = RenderCache.RowWork(rendered: .max, served: .max - 2, bodies: .max)
        var later = earlier
        later.rendered &+= 3
        later.served &+= 3
        later.bodies &+= 1
        let delta = later.delta(since: earlier)
        #expect(delta.rendered == 3)
        #expect(delta.served == 3)
        #expect(delta.bodies == 1)
    }

    @Test("A wrapped total's lookups and hit rate do not trap")
    func lookupsOfAWrappedTotal() {
        let stats = RenderCache.Stats(hits: .max, misses: 1)
        #expect(stats.lookups == .min)
        #expect(stats.hitRate == 0)
    }

    @Test("A lazy stack's running pitch average keeps its value past any count")
    func measuredPitchHolds() {
        let state = StackWindowState()
        // Every row one line, measured all but twice as often as an Int counts.
        state.measuredPitchTotal = .max - 1
        state.measuredPitchCount = .max - 1
        state.recordMeasuredPitch(1)
        state.recordMeasuredPitch(1)
        #expect(state.measuredPitchCount > 0)
        #expect(state.estimatedPitch(spacing: 0) == 1)
    }
}
