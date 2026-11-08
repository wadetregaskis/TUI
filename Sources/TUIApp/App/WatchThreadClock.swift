//  🖥️ TUI — A Terminal UI framework for Swift
//  WatchThreadClock.swift
//
//  The time the threads that watch a stalled main loop read, and their waits
//  on it: the machine's in an app, one a test steps in a test.
//
//  Created by Wade Tregaskis
//  License: MIT

// NSCondition and threads: the watchers it serves are POSIX-only.
#if !canImport(WASILibc)

import Foundation

/// What a thread watching the main loop (`StallWatchdog`, `UnreadQuitKeyWatch`)
/// reads the time from, and waits on its gate's condition by.
///
/// Not a `Clock`: those threads wait on an `NSCondition`, holding its lock, not
/// in a task, and they must — a watchdog for a stalled main loop cannot count
/// on the cooperative pool being free either. So the seam is the two things
/// those threads do with time: read it, and wait on their condition until a
/// deadline. The app's is ``SystemWatchThreadClock``, which is what they did
/// before there was a seam; a test's steps by hand, so "the grace passed, and
/// it popped nothing" is a step of the clock rather than a sleep.
///
/// Internal, and a generic parameter wherever it is used, so the app's path is
/// specialised on ``SystemWatchThreadClock`` and costs what `Date()` and
/// `NSCondition.wait(until:)` did.
protocol WatchThreadClock: Sendable {
    /// The time now.
    var now: Date { get }

    /// Waits on `condition`, whose lock the caller holds, until it is
    /// signalled, or, given a `deadline`, until the clock reads it.
    ///
    /// - Returns: `false` if the deadline came, as `NSCondition.wait(until:)`
    ///   says; otherwise `true`, which may also be a spurious wake, so the
    ///   caller looks again at what it waits for.
    func wait(on condition: NSCondition, until deadline: Date?) -> Bool
}

/// The machine's time, and `NSCondition`'s own waits.
struct SystemWatchThreadClock: WatchThreadClock {
    var now: Date { Date() }

    func wait(on condition: NSCondition, until deadline: Date?) -> Bool {
        guard let deadline else {
            condition.wait()
            return true
        }
        return condition.wait(until: deadline)
    }
}

#endif
