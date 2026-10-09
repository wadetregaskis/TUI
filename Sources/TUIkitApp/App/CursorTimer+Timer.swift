//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CursorTimer+Timer.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkitFoundation

// MARK: - Timer Control

extension CursorTimer {
    /// Starts the cursor animation timer.
    ///
    /// If the timer is already running, this is a no-op.
    func start() {
        guard task == nil else { return }

        task = Task { [weak self] in
            while !Task.isCancelled {
                // Read per iteration: `creditWake(atNanos:)` planned it at the previous
                // wake — or, for the first pass, a render set it through `advance(by:)`.
                let seconds = self?.sleepSeconds ?? Self.standardFrameSeconds
                do {
                    try await Task.sleep(nanoseconds: Self.sleepNanoseconds(seconds))
                } catch {
                    return  // cancelled
                }
                // The sleep returning is NOT proof the task still wants this
                // wake: `Task.sleep` throws only when the cancel beats the
                // wake, so one whose deadline passed while the main actor was
                // busy resumes normally even though `cancel()` has since been
                // called. Taking it then would fix the cursor clock's new zero
                // at this stale wake instead of the render the restart left it
                // to, and would carry on looping beside the task that render
                // starts — two timers, twice the wakes.
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.creditWake(atNanos: self.nowNanos())
            }
        }
    }

    /// `seconds` as the nanoseconds a sleep asks for: ROUNDED, through the conversion
    /// every step boundary uses.
    ///
    /// `UInt64(seconds * 1_000_000_000)` truncated, and a plan of `n` nanoseconds that
    /// has been through `Double(n) / 1e9` comes back one short on about 2% of plans. A
    /// real wake is milliseconds late and hides that. A clock that advances by exactly
    /// what was slept wakes 1 ns before the boundary, finds the change still 1 ns away,
    /// and wakes again for it: two wakes for one change. (Under the 10 ms floor this
    /// sleep once had, it was a frame 10 ms late.)
    static func sleepNanoseconds(_ seconds: Double) -> UInt64 {
        UInt64(clamping: AnimationClock.nanoseconds(seconds))
    }

    /// Takes a wake at `now`, plans the sleep that follows it, and posts the ticks — in
    /// that order, which is the point.
    ///
    /// The body of the timer's loop, separate so a test can step it on a clock of its
    /// own without racing a real `Task.sleep`.
    func creditWake(atNanos now: UInt64) {
        // What the clock READS, not what the sleep asked for. A wake is late by a few
        // milliseconds, and crediting only the planned sleep lost that at every wake —
        // every animation on a page ran slow by one shared factor, 1.48× on the
        // Spinners page.
        observe(nowNanos: now)
        // Planned BEFORE the ticks go out: see `planner` for what planning after them
        // did.
        if let planner {
            advance(by: planner(elapsed(for:)))
        }
        // Both clocks, because both advance on this one timer: they differ in where
        // their zero sits, not in when they tick.
        for clock in AnimationClock.allCases {
            renderNotifier?.setNeedsAnimationTick(clock)
        }
    }

    /// Stops the cursor animation timer.
    ///
    /// ``AnimationClock/content`` is not reset, and cannot be: it is the monotonic
    /// clock. A spinner that appears after a still stretch starts where the shared
    /// clock is, in phase with every other spinner of its style whose speed has not
    /// changed, rather than at its first frame. ``AnimationClock/cursor`` restarts at its bright end at the next
    /// ``observe(nowNanos:)``.
    func stop() {
        task?.cancel()
        task = nil
        focusEpochNanos = nil
        sleepSeconds = Self.standardFrameSeconds
    }

    /// Restarts ``AnimationClock/cursor`` at its bright end, leaving
    /// ``AnimationClock/content`` running.
    ///
    /// Call this when the focus moves, so whatever has just taken it is visible at
    /// once. The run loop also calls it when the process resumes from Ctrl-Z or an
    /// external SIGSTOP: the monotonic clock ran on while it was stopped, and a caret
    /// would otherwise come back mid-blink.
    ///
    /// **It reads no clock.** The new zero is taken at the next ``observe(nowNanos:)``
    /// — the render that always follows — floored to the step lattice, so that frame
    /// is step 0 by construction. Read here, the zero would be floored at INPUT time
    /// and the render would come later (up to a frame at the pacer's cap, on top of up
    /// to a step of floor), so the first frame could already be step 1 and miss the
    /// bright start this exists to give; and the read would move `.content` between
    /// two frames.
    func restartFocusPhase() {
        focusEpochNanos = nil
        sleepSeconds = Self.standardFrameSeconds
        // The in-flight sleep was sized for the OLD cadence, and its wake would set
        // the new zero at the wake rather than at the render that follows the focus
        // change. Cancelling usually ends the sleep with a CancellationError the loop
        // returns on; when the wake got there first the loop's own `Task.isCancelled`
        // check catches it instead. The render that always follows a focus change
        // starts the timer again.
        task?.cancel()
        task = nil
    }
}
