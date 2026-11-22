//  🖥️ TUI — A Terminal UI framework for Swift
//  Terminal+PollPace.swift
//
//  A clock for the tests that drive the input parser a `readEvent()` at a
//  time, each standing for a pass of the run loop.
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUITestSupport in Package.swift).
#if TUI_TEST_SUPPORT && canImport(Testing)

@testable import TUIApp

extension Terminal {
    /// Times this terminal's parser as the run loop paces it while the parser
    /// holds something and nothing else wakes the loop: each `readEvent()` a
    /// poll (`FramePacer.pendingInputPollNanos`, 25 ms) after the one before.
    ///
    /// The parser's waits are on the clock (``nowNanos``), and it reads the
    /// clock once a call, so a test that reads N times has waited N polls:
    /// what the waits were counted in until 2026-11-22, when a pass was any
    /// wake of the loop rather than a poll. A test about the clock itself sets
    /// ``nowNanos`` instead (`ParserWaitClockTests`).
    func readsAtThePollsPace() {
        var now: UInt64 = 0
        nowNanos = {
            now &+= FramePacer.pendingInputPollNanos
            return now
        }
    }
}

#endif
