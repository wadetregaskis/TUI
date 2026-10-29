//  🖥️ TUI — A Terminal UI framework for Swift
//  RunningAppClaimTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp

/// One app per process: the run loop claims the process as it starts and
/// gives it back as it ends. In child processes, since a claim is the
/// process's and a refused one stops it.
@Suite("One app per process")
struct RunningAppClaimTests {

    /// Two runs at once shared one terminal, one set of signal handlers and
    /// one signal debt, and the first teardown undid the other's raw mode.
    @Test("A second run while one is running stops at the precondition")
    func concurrentRunIsRefused() async {
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                RunningAppClaim.claim()
                RunningAppClaim.claim()
            }
        }
    }

    @Test("One run after another is fine")
    func sequentialRunsAreAllowed() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                RunningAppClaim.claim()
                RunningAppClaim.release()
                RunningAppClaim.claim()
                RunningAppClaim.release()
            }
        }
    }
}
