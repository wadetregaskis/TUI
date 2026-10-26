//  🖥️ TUI — A Terminal UI framework for Swift
//  FramePacerTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIFoundation
@testable import TUITestSupport

@Suite("FramePacer")
struct FramePacerTests {
    /// 60 FPS, the default, so the numbers below read in whole frames.
    private let interval: UInt64 = 1_000_000_000 / 60

    /// A pacer whose first frame has already rendered at `t0`, which is the state
    /// the run loop is in for every iteration after the first.
    private func rendered(
        at t0: UInt64, deadline: UInt64? = nil, maxFrameRate: Int = 60
    ) -> FramePacer {
        var pacer = FramePacer(maxFrameRate: maxFrameRate, startedAtNanos: 0)
        pacer.render { FramePacer.Frame(renderedAtNanos: t0, animationDeadlineNanos: deadline) }
        return pacer
    }

    /// Renders whatever the clock says, and counts.
    private func frame(at time: UInt64, deadline: UInt64? = nil) -> FramePacer.Frame {
        FramePacer.Frame(renderedAtNanos: time, animationDeadlineNanos: deadline)
    }

    // MARK: - The cap

    @Test("A burst of requests inside one interval renders exactly one frame")
    func burstCoalesces() {
        var pacer = rendered(at: 1_000)
        var renders = 0
        for step in stride(from: UInt64(0), to: interval, by: UInt64.Stride(interval / 8)) {
            pacer.requestRender()
            pacer.renderIfDue(now: 1_000 + step) {
                renders += 1
                return frame(at: 1_000 + step)
            }
        }
        #expect(renders == 0)
        // The instant the cap clears, the coalesced burst renders — once.
        pacer.renderIfDue(now: 1_000 + interval) {
            renders += 1
            return frame(at: 1_000 + interval)
        }
        #expect(renders == 1)
        #expect(!pacer.isRenderPending)
    }

    @Test("A request that arrives with the cap already clear renders immediately")
    func requestAfterCapRendersNow() {
        var pacer = rendered(at: 1_000)
        var renders = 0
        pacer.requestRender()
        pacer.renderIfDue(now: 1_000 + interval) {
            renders += 1
            return frame(at: 1_000 + interval)
        }
        #expect(renders == 1)
    }

    @Test("With nothing requested, the cap clearing renders nothing")
    func capClearingIsNotItselfAReason() {
        var pacer = rendered(at: 1_000)
        var renders = 0
        pacer.renderIfDue(now: 1_000 + 10 * interval) {
            renders += 1
            return frame(at: 0)
        }
        #expect(renders == 0)
    }

    @Test("The cap runs from when the render finished, not from when it was asked for")
    func capMeasuresFromFrameCompletion() {
        var pacer = rendered(at: 1_000)
        pacer.requestRender()
        // The frame is due at 1_000 + interval but takes half an interval to
        // produce, so the next one may not render until 1.5 intervals in.
        pacer.renderIfDue(now: 1_000 + interval) {
            frame(at: 1_000 + interval + interval / 2)
        }
        pacer.requestRender()
        var renders = 0
        pacer.renderIfDue(now: 1_000 + 2 * interval) {
            renders += 1
            return frame(at: 0)
        }
        #expect(renders == 0)
        pacer.renderIfDue(now: 1_000 + interval + interval / 2 + interval) {
            renders += 1
            return frame(at: 0)
        }
        #expect(renders == 1)
    }

    @Test("A nonsense frame rate is clamped to 1 FPS rather than dividing by zero")
    func rateIsClamped() {
        #expect(FramePacer(maxFrameRate: 0, startedAtNanos: 0).frameIntervalNanos == 1_000_000_000)
        #expect(FramePacer(maxFrameRate: -5, startedAtNanos: 0).frameIntervalNanos == 1_000_000_000)
    }

    // MARK: - Animation deadlines

    @Test("A deadline the clock has reached is itself a reason to render")
    func deadlineIsAReason() {
        var pacer = rendered(at: 1_000, deadline: 1_000 + 3 * interval)
        var renders = 0
        // Cap long clear, deadline not yet reached: nothing is owed.
        pacer.renderIfDue(now: 1_000 + 2 * interval) {
            renders += 1
            return frame(at: 0)
        }
        #expect(renders == 0)
        pacer.renderIfDue(now: 1_000 + 3 * interval) {
            renders += 1
            return frame(at: 1_000 + 3 * interval)
        }
        #expect(renders == 1)
    }

    @Test("A deadline that passes while the cap is closed still renders once it clears")
    func deadlineDebtSurvivesTheCap() {
        // The grid fires a third of the way into the frame interval — faster than
        // the cap allows. The frame it owes must not be dropped for having been
        // due at an instant that has now gone by.
        var pacer = rendered(at: 1_000, deadline: 1_000 + interval / 3)
        var renders = 0
        pacer.renderIfDue(now: 1_000 + interval / 3) {
            renders += 1
            return frame(at: 0)
        }
        #expect(renders == 0)
        #expect(pacer.isRenderPending)
        pacer.renderIfDue(now: 1_000 + interval) {
            renders += 1
            return frame(at: 1_000 + interval, deadline: 1_000 + interval + interval / 3)
        }
        #expect(renders == 1)
    }

    @Test("A frame that declares no animation leaves nothing to wake for")
    func deadlineIsDroppedWhenNothingAnimates() {
        var pacer = rendered(at: 1_000, deadline: 1_000 + interval)
        #expect(pacer.waitNanos(now: 1_000) != nil)
        pacer.requestRender()
        pacer.renderIfDue(now: 1_000 + interval) {
            frame(at: 1_000 + interval, deadline: nil)
        }
        #expect(pacer.waitNanos(now: 1_000 + interval) == nil)
        var renders = 0
        pacer.renderIfDue(now: 1_000 + 10 * interval) {
            renders += 1
            return frame(at: 0)
        }
        #expect(renders == 0)
    }

    // MARK: - The wait

    @Test("Idle and unanimated, the loop blocks until woken")
    func idleBlocks() {
        let pacer = rendered(at: 1_000)
        #expect(pacer.waitNanos(now: 1_000) == nil)
        #expect(pacer.waitNanos(now: 1_000 + 99 * interval) == nil)
    }

    @Test("A pending render waits exactly until the cap clears")
    func pendingWaitsForTheCap() {
        var pacer = rendered(at: 1_000)
        pacer.requestRender()
        #expect(pacer.waitNanos(now: 1_000) == interval)
        #expect(pacer.waitNanos(now: 1_000 + interval / 4) == interval - interval / 4)
    }

    @Test("A deadline sooner than the cap waits for the cap, not the deadline")
    func deadlineNeverBeatsTheCap() {
        let pacer = rendered(at: 1_000, deadline: 1_000 + interval / 3)
        #expect(pacer.waitNanos(now: 1_000) == interval)
    }

    @Test("A deadline later than the cap is the target, and a pending render is not")
    func laterDeadlineIsTheTarget() {
        var pacer = rendered(at: 1_000, deadline: 1_000 + 4 * interval)
        // Nothing pending: the only reason to wake is the deadline.
        #expect(pacer.waitNanos(now: 1_000) == 4 * interval)
        // Pending as well: the sooner of the two, which is the cap.
        pacer.requestRender()
        #expect(pacer.waitNanos(now: 1_000) == interval)
    }

    @Test("A target already in the past waits zero rather than underflowing")
    func pastTargetWaitsZero() {
        var pacer = rendered(at: 1_000, deadline: 1_000 + interval)
        pacer.requestRender()
        // Both the cap and the deadline are behind `now`. The loop wants a
        // zero-length wait — one more iteration — not a 584-year one.
        #expect(pacer.waitNanos(now: 1_000 + 5 * interval) == 0)
    }

    // MARK: - The partial-input poll

    @Test("The poll gives an otherwise unbounded wait a deadline")
    func pollBoundsAnIdleWait() {
        let pacer = rendered(at: 1_000)
        #expect(pacer.waitNanos(now: 1_000) == nil)
        #expect(
            pacer.waitNanos(now: 1_000, pollingPendingInput: true)
                == FramePacer.pendingInputPollNanos)
    }

    @Test("The poll only ever shortens a wait")
    func pollOnlyShortens() {
        // A 60 FPS interval (~16.7 ms) is shorter than the ~25 ms poll: the frame
        // must not be delayed to meet it.
        var fast = rendered(at: 1_000)
        fast.requestRender()
        #expect(fast.waitNanos(now: 1_000, pollingPendingInput: true) == interval)
        // A 1 FPS interval is far longer: the poll wins.
        var slow = rendered(at: 1_000, maxFrameRate: 1)
        slow.requestRender()
        #expect(
            slow.waitNanos(now: 1_000, pollingPendingInput: true)
                == FramePacer.pendingInputPollNanos)
    }

    // MARK: - A wake between frames

    @Test("A wake between frames bounds an idle wait and owes no frame when it comes")
    func wakeBoundsAnIdleWaitWithoutAFrame() {
        var pacer = rendered(at: 1_000)
        let wake: UInt64 = 1_000 + 5_000_000_000
        #expect(pacer.waitNanos(now: 1_000, until: wake) == 5_000_000_000)
        // Reached, it is the loop's to serve: nothing renders for it.
        var renders = 0
        #expect(!pacer.renderIfDue(now: wake) { renders += 1; return frame(at: wake) })
        #expect(renders == 0)
        #expect(pacer.waitNanos(now: wake, until: wake) == 0)
    }

    @Test("A wake between frames only shortens a wait, and ignores the cap")
    func wakeOnlyShortens() {
        var pending = rendered(at: 1_000)
        pending.requestRender()
        #expect(pending.waitNanos(now: 1_000, until: 1_000 + 10 * interval) == interval)
        // Sooner than the cap: what it does draws nothing, so the cap does not hold it.
        #expect(pending.waitNanos(now: 1_000, until: 1_000 + interval / 2) == interval / 2)
        let animating = rendered(at: 1_000, deadline: 1_000 + 3 * interval)
        #expect(animating.waitNanos(now: 1_000, until: 1_000 + 9 * interval) == 3 * interval)
    }
}
