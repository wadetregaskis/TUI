//  🖥️ TUI — A Terminal UI framework for Swift
//  AutoRepeatTimerTests.swift
//
//  The auto-repeat timer decides whether a press was a tap or a hold, and the
//  only evidence it has is that no release has been read yet. That evidence is
//  worthless while the main actor is busy, because the run loop reads stdin
//  between frames and a busy main actor is a loop that is not reading: a frame
//  slower than the initial delay turned one click on a Slider / Stepper arrow
//  into two steps.
//
//  On a clock the test steps (`TestClock`), so nothing here waits on the wall:
//  a busy main actor is, to the timer, a sleep that came back late, and a step
//  of the clock past the delay and its tolerance is exactly that. They used to
//  wait by the wall, at shrunk cadences, and block the main actor by spinning;
//  every such wait was a race some loaded runner lost.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUITesting

@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("AutoRepeatTimer tap versus hold")
struct AutoRepeatTimerTests {
    /// The shipping cadence: on a stepped clock it costs no time.
    private static let delay = Duration.milliseconds(AutoRepeatTimer.defaultInitialDelayMs)
    private static let interval = Duration.milliseconds(AutoRepeatTimer().repeatIntervalMs)

    /// Waits until the timer's task is asleep on `clock`: an edge it crosses,
    /// counted, where a step of the clock would otherwise land before the wait
    /// it is meant to end.
    private static func asleep(on clock: TestClock) async {
        await settle(until: { clock.sleepers == 1 })
    }

    /// A scrollbar arrow and a slider arrow are the same gesture, and the two
    /// auto-repeats are separate implementations — the scrollbar's is driven
    /// from the render pass, this one from a task. They must still agree about
    /// where a click ends, or the same press means different things one control
    /// apart.
    @Test("The two auto-repeats agree on how long a click may be")
    func initialDelayMatchesTheScrollbar() {
        #expect(
            AutoRepeatTimer().initialDelayMs * 1_000_000
                == Int(ScrollbarRenderer.autoRepeatInitialDelayNanos))
    }

    @Test("A tap fires exactly once")
    func tapFiresOnce() async {
        var fires = 0
        let clock = TestClock()
        let timer = AutoRepeatTimer(clock: clock)
        timer.start { fires += 1 }
        await Self.asleep(on: clock)
        #expect(fires == 1, "the press acted")
        timer.stop()
        #expect(clock.sleepers == 0, "the release ended the wait: nothing is left to fire")
        clock.advance(by: Self.delay * 3)
        await yieldToSpawnedWork()
        #expect(fires == 1, "the press acted, the release ended it before any repeat")
    }

    @Test("A hold still repeats")
    func holdRepeats() async {
        var fires = 0
        let clock = TestClock()
        let timer = AutoRepeatTimer(clock: clock)
        timer.start { fires += 1 }
        await Self.asleep(on: clock)
        clock.advance(by: Self.delay)
        await settle(until: { fires == 2 })
        await Self.asleep(on: clock)
        clock.advance(by: Self.interval)
        await settle(until: { fires == 3 })
        timer.stop()
        #expect(fires == 3, "past the initial delay the repeat loop runs, one fire an interval")
    }

    @Test("A hold's repeats are continuous changes; the press that began it is not")
    func repeatsAreContinuous() async {
        var continuous: [Bool] = []
        let clock = TestClock()
        let timer = AutoRepeatTimer(clock: clock)
        timer.start { continuous.append(Transaction.ambient?.isContinuous ?? false) }
        await Self.asleep(on: clock)
        clock.advance(by: Self.delay)
        await settle(until: { continuous.count == 2 })
        await Self.asleep(on: clock)
        clock.advance(by: Self.interval)
        await settle(until: { continuous.count == 3 })
        timer.stop()
        #expect(continuous.first == false, "the press itself is a single action")
        #expect(continuous.count == 3 && continuous.dropFirst().allSatisfy { $0 }, "\(continuous)")
    }

    /// The regression. The main actor is blocked right through the initial
    /// delay — the app rendering a frame that outlasts it — and only then does
    /// the loop get to read the release. Without the awake-time gate the timer
    /// wakes first and fires a repeat that the user never asked for.
    @Test("A frame longer than the initial delay does not turn a tap into two")
    func slowFrameDoesNotDoubleATap() async {
        var fires = 0
        let clock = TestClock()
        let timer = AutoRepeatTimer(clock: clock)
        timer.start { fires += 1 }
        await Self.asleep(on: clock)
        #expect(fires == 1, "the press acted")

        // The frame: the timer's sleep comes back three delays after it began,
        // as one does from behind a main actor that was busy all that while.
        clock.advance(by: Self.delay * 3)
        // It woke late and went back to sleep, rather than firing. Without the
        // gate it fires and then sleeps the interval, so this wait ends either
        // way, and the count below tells the two apart.
        await Self.asleep(on: clock)
        #expect(fires == 1, "the timer woke late and waited again, rather than firing (\(fires) fires)")

        // Only NOW does the loop reach the release that has been sitting in the
        // input buffer since the click.
        timer.stop()
        #expect(clock.sleepers == 0, "the release ended the wait")
        #expect(fires == 1, "still one step, not two (\(fires) fires)")
    }
}
