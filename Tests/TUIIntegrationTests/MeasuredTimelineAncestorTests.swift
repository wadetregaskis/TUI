//  🖥️ TUI — A Terminal UI framework for Swift
//  MeasuredTimelineAncestorTests.swift
//
//  A composite above a live `TimelineView` that a stack measures before it
//  draws, whose body the measure keeps for the draw (`BodyKeep`): its body is
//  kept across frames too (`FrameBodyKeep`), so an entry of the timeline runs
//  the timeline's content and not that body. The draw took the measure's body
//  and never reached the keep across frames, so the body ran at every entry,
//  sixty times a second (VIEWR-3). And what a kept body is kept for must still
//  run: a changed input runs the body again, and its `onChange` and `task(id:)`
//  see the new value.
//
//  Counted, not compared: a buffer served stale and one drawn again look the
//  same, and the render-memo verifier compares buffers, so it is blind to a
//  side effect that did not run.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport
@testable import TUIView

/// What the views below count. Globals, not captures, so that no view holds
/// anything that would make it compare unequal.
@MainActor private var aboveBodies = 0
@MainActor private var loopRuns = 0
@MainActor private var changesSeen: [Int] = []
@MainActor private var tasksSeen: [Int] = []

@MainActor
private func resetCounts() {
    aboveBodies = 0
    loopRuns = 0
    changesSeen = []
    tasksSeen = []
}

/// A 60 Hz timeline whose content reads its date, as a game loop's does.
private struct Loop: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            // swiftlint:disable:next redundant_discardable_let
            let _ = MainActor.assumeIsolated { loopRuns += 1 }
            Color.clear.onChange(of: timeline.date) { _, _ in }
        }
    }
}

/// The composite the keep is for: above the timeline, and inside a stack, so
/// it is measured before it is drawn.
private struct Above: View {
    let number: Int

    var body: some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = MainActor.assumeIsolated { aboveBodies += 1 }
        Text(verbatim: "number \(number)")
            .background { Loop() }
            .onChange(of: number) { _, new in changesSeen.append(new) }
            .task(id: number) { tasksSeen.append(number) }
    }
}

private struct Host: View {
    @State private var number = 0

    var body: some View {
        VStack {
            Button("Bump") { number += 1 }
            Above(number: number)
        }
    }
}

@MainActor
@Suite("A body measured before it is drawn above a live timeline is kept across frames", .serialized)
struct MeasuredTimelineAncestorTests {
    /// How the measure comes to keep the body for the draw: every body kept
    /// (`keepsEveryBody`), or the type learned slow, as an app learns it.
    enum Keeping: CaseIterable, Sendable {
        case everyBody
        case learnedSlow
    }

    private func app(_ keeping: Keeping) -> TestApp {
        resetCounts()
        let app = TestApp(width: 30, height: 3) { Host() }
        let bodyKeep = app.renderCache.bodyKeep
        switch keeping {
        case .everyBody:
            bodyKeep.keepsEveryBody = true
        case .learnedSlow:
            // Every body timed is over a line of zero: a body learned slow on
            // the first frame, whatever the machine's load.
            bodyKeep.keepsEveryBody = false
            app.renderCache.learnsFromTiming = true
            bodyKeep.slowBody = .zero
        }
        return app
    }

    /// Draws the first frames: the first, and those in which the walk learns
    /// where the live timelines are.
    private func warmUp(_ app: TestApp) {
        #expect(app.screen.contains("number 0"))
        app.advance(by: .milliseconds(100))
    }

    @Test("An entry of the timeline runs no body above it", arguments: Keeping.allCases)
    func unchangedFramesRunNoBody(_ keeping: Keeping) {
        let app = app(keeping)
        warmUp(app)
        let (bodies, runs) = (aboveBodies, loopRuns)
        app.advance(by: .seconds(1))
        #expect(loopRuns - runs >= 55, "the timeline's content runs at each of its 60 entries")
        #expect(aboveBodies == bodies, "the body read nothing that moved: \(aboveBodies - bodies) ran")
        #expect(app.renderCache.plainMemo.frameBodies.counts.taken > 0)
    }

    @Test("A changed input runs the kept body once, and its onChange and task see it", arguments: Keeping.allCases)
    func changedInputRunsTheBody(_ keeping: Keeping) async throws {
        let app = app(keeping)
        warmUp(app)
        try await app.wait(until: { tasksSeen == [0] })
        let still = aboveBodies
        app.advance(by: .milliseconds(200))
        #expect(aboveBodies == still)
        try app.click("Bump")
        #expect(app.screen.contains("number 1"))
        try await app.wait(until: { tasksSeen == [0, 1] })
        #expect(changesSeen == [1], "onChange saw the new value once")
        let changed = aboveBodies
        #expect(changed > still, "the body ran for its new input")
        app.advance(by: .milliseconds(500))
        #expect(aboveBodies <= changed + 1, "kept again within a frame of the change: \(aboveBodies - changed) ran")
        #expect(app.screen.contains("number 1"))
        #expect(changesSeen == [1])
        #expect(tasksSeen == [0, 1])
    }
}
