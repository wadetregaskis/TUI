//  🖥️ TUI — A Terminal UI framework for Swift
//  SteppedWatchClock.swift
//
//  A `WatchThreadClock` a test steps, for the threads that watch a stalled
//  main loop: "the grace passed, and it did nothing" as a step of the clock,
//  not a sleep.
//
//  Created by Wade Tregaskis
//  License: MIT

#if !canImport(WASILibc)

import Foundation
import Synchronization
import Testing

@testable import TUIApp

/// A ``WatchThreadClock`` whose time passes only when a test says.
///
/// A thread waiting on it waits on its condition with no deadline of the
/// machine's; ``advance(by:)`` moves the time and wakes every thread waiting,
/// then returns only once each has done what it does on waking — looked, and
/// either waited again or let its lock go — so what the test asserts next is
/// what the thread made of the new time. ``awaitWaiter(timed:)`` waits for the
/// thread to be waiting at all, which a step must not run ahead of: a step
/// before the thread has begun its wait moves a clock it has not read yet.
///
/// The machine's time comes in only as a hang-breaker, ten seconds by
/// default, on a condition, never a sleep.
final class SteppedWatchClock: WatchThreadClock {
    /// A thread in ``wait(on:until:)``.
    private struct Waiter {
        let id: Int
        let condition: NSCondition
        let deadline: Date?
        /// How many steps the clock had taken when the wait began.
        let step: Int
    }

    private struct State {
        var now = Date(timeIntervalSinceReferenceDate: 0)
        var waiters: [Waiter] = []
        var nextID = 0
        var steps = 0
    }

    private let state = Mutex(State())

    /// What a test waits on for the threads' progress. Every change to
    /// ``state`` is made holding it, so no broadcast is lost.
    private let progress = NSCondition()

    var now: Date { state.withLock { $0.now } }

    func wait(on condition: NSCondition, until deadline: Date?) -> Bool {
        progress.lock()
        let id: Int? = state.withLock { state in
            if let deadline, state.now >= deadline { return nil }
            state.nextID += 1
            state.waiters.append(
                Waiter(id: state.nextID, condition: condition, deadline: deadline, step: state.steps))
            return state.nextID
        }
        progress.broadcast()
        progress.unlock()
        guard let id else { return false }
        // The caller holds the condition's lock from before the registration to
        // here, so a step's broadcast, which takes that lock, cannot fall
        // between the two and be lost.
        condition.wait()
        progress.lock()
        let timedOut = state.withLock { state in
            state.waiters.removeAll { $0.id == id }
            return deadline.map { state.now >= $0 } ?? false
        }
        progress.broadcast()
        progress.unlock()
        return !timedOut
    }

    /// Waits until a thread is waiting on the clock, a wait begun since the
    /// last step: `timed`, one with a deadline (watching input), or else one
    /// without (waiting to be armed).
    ///
    /// - Returns: Whether one came within `timeout` seconds.
    func awaitWaiter(timed: Bool = true, timeout: TimeInterval = 10) -> Bool {
        let giveUp = Date(timeIntervalSinceNow: timeout)
        progress.lock()
        defer { progress.unlock() }
        while !state.withLock({ state in
            state.waiters.contains { ($0.deadline != nil) == timed && $0.step == state.steps }
        }) {
            guard progress.wait(until: giveUp) else { return false }
        }
        return true
    }

    /// Moves the time on by `seconds`, wakes every thread waiting on the clock,
    /// and returns once each has acted on it.
    func advance(by seconds: TimeInterval, timeout: TimeInterval = 10) {
        progress.lock()
        let woken = state.withLock { state in
            state.now = state.now.addingTimeInterval(seconds)
            state.steps += 1
            return state.waiters
        }
        progress.unlock()
        for waiter in woken {
            waiter.condition.lock()
            waiter.condition.broadcast()
            waiter.condition.unlock()
        }
        // Each wakes, and leaves its wait holding its condition's lock…
        let giveUp = Date(timeIntervalSinceNow: timeout)
        let ids = Set(woken.map(\.id))
        progress.lock()
        while state.withLock({ $0.waiters.contains { ids.contains($0.id) } }) {
            guard progress.wait(until: giveUp) else {
                Issue.record("a thread woken by the step did not wake within \(timeout) s")
                break
            }
        }
        progress.unlock()
        // …which it lets go only once it has done with what it woke to: waiting
        // again, or letting go to sleep elsewhere, or ending.
        for waiter in woken {
            waiter.condition.lock()
            waiter.condition.unlock()
        }
    }
}

#endif
