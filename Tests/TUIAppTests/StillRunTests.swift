//  🖥️ TUI — A Terminal UI framework for Swift
//  StillRunTests.swift
//
//  `TUI_STILL`: what a still run's frames show and what they ask for, driven through
//  `RenderLoop` with the timer and scheduler the run loop passes it. The other half,
//  that the run loop doesn't start the timer for the runs such a frame leaves, is one
//  line in `AppRunner.renderFrame`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// A page of what moves by itself: a spinner and a timeline.
private struct EverythingThatMovesApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            VStack {
                Spinner(style: .dots)
                TimelineView(.periodic(from: Date(timeIntervalSince1970: 0), by: 1)) { timeline in
                    Text("\(Int(timeline.date.timeIntervalSince1970))")
                }
            }
        }
    }
}

@MainActor
@Suite("A still run")
struct StillRunTests {
    /// Renders the page at one instant, returning the bytes it wrote.
    private func frame(
        _ loop: RenderLoop<EverythingThatMovesApp>, harness: RenderLoopHarness,
        scheduler: AnimationScheduler, timer: CursorTimer, atSeconds seconds: Int64
    ) -> String {
        harness.terminal.reset()
        scheduler.beginFrame()
        loop.render(
            pulsePhase: timer.breathPhase, cursorTimer: timer, animationScheduler: scheduler,
            frameNowNanos: seconds * 1_000_000_000,
            frameDate: Date(timeIntervalSince1970: TimeInterval(seconds)))
        scheduler.endFrame()
        return harness.terminal.allOutput
    }

    @Test("Draws the same picture whenever a frame comes, and asks for no other")
    func nothingMovesAndNothingIsAsked() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(EverythingThatMovesApp())
        loop.stillDate = Date(timeIntervalSince1970: 500)
        let scheduler = AnimationScheduler()
        let timer = CursorTimer(renderNotifier: harness.appState)

        let first = frame(loop, harness: harness, scheduler: scheduler, timer: timer, atSeconds: 1000)
        #expect(first.contains("500"), "the timeline stays at the launch date: \(first.debugDescription)")
        #expect(scheduler.nextFiring(after: 1000 * 1_000_000_000) == nil)

        let second = frame(loop, harness: harness, scheduler: scheduler, timer: timer, atSeconds: 1007)
        #expect(second.isEmpty, "seven seconds on, nothing changed: \(second.debugDescription)")
        #expect(scheduler.nextFiring(after: 1007 * 1_000_000_000) == nil)
    }

    @Test("Differs from a run that moves, which is what the test above is worth")
    func aRunThatMovesAsksAndChanges() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(EverythingThatMovesApp())
        let scheduler = AnimationScheduler()
        let timer = CursorTimer(renderNotifier: harness.appState)

        _ = frame(loop, harness: harness, scheduler: scheduler, timer: timer, atSeconds: 1000)
        #expect(scheduler.nextFiring(after: 1000 * 1_000_000_000) != nil)
        let second = frame(loop, harness: harness, scheduler: scheduler, timer: timer, atSeconds: 1007)
        #expect(!second.isEmpty)
    }
}
