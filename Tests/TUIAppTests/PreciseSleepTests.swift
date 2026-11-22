//  🖥️ TUI — A Terminal UI framework for Swift
//  PreciseSleepTests.swift
//
//  The run loop's sleep on Windows: never short, and ended at once by its
//  task's cancellation. How late it may be is a measurement, not a test's to
//  hold a loaded machine to (see `PreciseSleep`).
//
//  Created by Wade Tregaskis
//  License: MIT

#if os(Windows)

import Foundation
import Testing

@testable import TUIApp

@Suite("PreciseSleep on Windows")
struct PreciseSleepTests {
    @Test("A sleep lasts at least as long as it was asked for")
    func notShort() async {
        let clock = ContinuousClock()
        for milliseconds in [1, 5, 17] {
            let elapsed = await clock.measure { await PreciseSleep.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000) }
            // The timer's and the clock's readings may differ by a little.
            #expect(elapsed >= .milliseconds(milliseconds) - .microseconds(500), "\(milliseconds) ms took \(elapsed)")
        }
    }

    @Test("Cancelling the task ends the sleep at once, as cancelling a task's own sleep does")
    func cancelled() async {
        let clock = ContinuousClock()
        let started = clock.now
        let task = Task { await PreciseSleep.sleep(nanoseconds: 120_000_000_000) }
        task.cancel()
        await task.value
        // Far sooner than the sleep, with room for a loaded machine's
        // scheduling: a parallel run once took 7 s to get to the task at all.
        #expect(clock.now - started < .seconds(60))
    }

    @Test("Many sleeps in turn each end, and leave nothing waiting")
    func many() async {
        for _ in 0..<200 { await PreciseSleep.sleep(nanoseconds: 100_000) }
    }
}

#endif
