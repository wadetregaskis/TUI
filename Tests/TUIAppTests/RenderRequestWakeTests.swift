//  🖥️ TUI — A Terminal UI framework for Swift
//  RenderRequestWakeTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Synchronization
import Testing

@testable import TUIApp

/// The run loop's wake for render requests (`RenderRequestWake`): one a pass,
/// however many requests, and never none for a request the pass did not serve.
///
/// The deliveries are kept and run by the test, in the order they were posted,
/// as the main actor runs the `Task`s the loop posts: nothing waits on a clock.
@MainActor
@Suite("Render request wake")
struct RenderRequestWakeTests {
    /// The deliveries posted and not yet run, and the wakes delivered.
    final class Recorder: Sendable {
        let deliveries = Mutex<[@MainActor @Sendable () -> Void]>([])
        let wakes = Mutex(0)

        func makeWake() -> RenderRequestWake {
            RenderRequestWake(
                post: { [self] delivery in deliveries.withLock { $0.append(delivery) } },
                wake: { [self] in wakes.withLock { $0 += 1 } })
        }

        var posted: Int { deliveries.withLock { $0.count } }
        var woken: Int { wakes.withLock { $0 } }

        /// Runs what was posted, as the main actor would once the loop waits.
        @MainActor func runDeliveries() {
            let pending = deliveries.withLock { list in
                defer { list = [] }
                return list
            }
            for delivery in pending { delivery() }
        }
    }

    @Test("Two requests before a wake post one delivery, which wakes the loop once")
    func twoRequestsOneWake() {
        let recorder = Recorder()
        let wake = recorder.makeWake()
        // The timer's wake: a tick for each of the two clocks.
        wake.request()
        wake.request()
        #expect(recorder.posted == 1)
        recorder.runDeliveries()
        #expect(recorder.woken == 1)
    }

    @Test("A request the pass served before its delivery ran wakes nothing")
    func servedRequestWakesNothing() {
        let recorder = Recorder()
        let wake = recorder.makeWake()
        // A key's handler asks for a frame in the drain, and the fold reads it.
        wake.request()
        wake.served()
        recorder.runDeliveries()
        #expect(recorder.woken == 0)
    }

    @Test("A request made after the pass read still wakes the loop")
    func requestAfterServedWakes() {
        let recorder = Recorder()
        let wake = recorder.makeWake()
        wake.request()
        wake.served()
        // A body writes its state as the frame draws, after the fold.
        wake.request()
        #expect(recorder.posted == 2)
        recorder.runDeliveries()
        #expect(recorder.woken == 1)
        // And the next request posts afresh.
        wake.request()
        #expect(recorder.posted == 1)
        recorder.runDeliveries()
        #expect(recorder.woken == 2)
    }

    @Test("A request from another thread, after the pass read, wakes the loop")
    func requestOffMainAfterServedWakes() async {
        let recorder = Recorder()
        let wake = recorder.makeWake()
        wake.served()
        await Task.detached { wake.request() }.value
        recorder.runDeliveries()
        #expect(recorder.woken == 1)
    }
}
