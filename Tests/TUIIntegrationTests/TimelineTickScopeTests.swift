//  🖥️ TUI — A Terminal UI framework for Swift
//  TimelineTickScopeTests.swift
//
//  A `TimelineView`'s entry re-evaluates the timeline's content, and nothing
//  else that has not changed: not the bodies above it, not a view its
//  `.background` or `.overlay` is drawn behind or over. And its content sees a
//  new date only at its own schedule's entries, however often something else draws. SwiftUI's rule,
//  which tuiarcade measured TUI breaking at sixty frames a second
//  (TUI-FEEDBACK.md, M2 items 1, 2 and 4).
//
//  Counted, not compared: a buffer served stale and one drawn again look the
//  same, so each test counts the bodies, renderers and changes it is about.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Observation
import Testing
import TUI
import TUITesting

/// What the views below count. Globals, not captures, so that no view holds
/// anything that would make it compare unequal.
@MainActor private var parentBodies = 0
@MainActor private var clockedInits = 0
@MainActor private var contentRuns = 0
@MainActor private var renderRuns = 0
@MainActor private var fastChanges = 0
@MainActor private var slowChanges = 0

/// Draws the first frames: the first, and those in which the walk learns
/// where the live timelines are.
@MainActor
private func warmUp(_ app: TestApp) {
    _ = app.screen
    app.advance(by: .milliseconds(100))
}

@MainActor
private func resetCounts() {
    parentBodies = 0
    clockedInits = 0
    contentRuns = 0
    renderRuns = 0
    fastChanges = 0
    slowChanges = 0
}

/// A 60 Hz timeline whose content reads its date, as a game loop's does.
private struct Loop: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            // swiftlint:disable:next redundant_discardable_let
            let _ = MainActor.assumeIsolated { contentRuns += 1 }
            Color.clear.onChange(of: timeline.date) { _, _ in }
        }
    }
}

/// The feedback's item 2: a timeline in the background of the parent's child.
private struct Clocked: View {
    init() {
        MainActor.assumeIsolated { clockedInits += 1 }
    }

    var body: some View {
        Text("still").background { Loop() }
    }
}

private struct Parent: View {
    var body: some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = MainActor.assumeIsolated { parentBodies += 1 }
        VStack {
            Text("title")
            Clocked()
        }
    }
}

@MainActor
@Observable
private final class Level {
    var number = 0
}

/// A parent above a running timeline whose body reads its own `@State` and a
/// model: a write to either runs it again, timeline or not.
private struct Counting: View {
    let level: Level
    @State private var taps = 0

    var body: some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = MainActor.assumeIsolated { parentBodies += 1 }
        VStack {
            Button("Tap") { taps += 1 }
            Text(verbatim: "taps \(taps) level \(level.number)")
            Clocked()
        }
    }
}

/// A canvas that reads nothing and never changes.
private struct Board: View, Equatable {
    var body: some View {
        Canvas { context, size in
            MainActor.assumeIsolated { renderRuns += 1 }
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.red))
        }
    }
}

/// The feedback's item 1: the timeline in the board's `.background`.
private struct BackgroundHost: View {
    var body: some View {
        Board().equatable().frame(width: 10, height: 3).background { Loop() }
    }
}

/// The same, the timeline in the board's `.overlay`.
private struct OverlayHost: View {
    var body: some View {
        Board().equatable().frame(width: 10, height: 3).overlay { Loop() }
    }
}

/// The feedback's item 4: a slow timeline beside a 60 Hz one.
private struct TwoTimelines<Slow: TimelineSchedule>: View {
    let slow: Slow

    var body: some View {
        VStack {
            TimelineView(.animation) { timeline in
                Color.clear.onChange(of: timeline.date) { _, _ in fastChanges += 1 }
            }
            .frame(width: 1, height: 1)
            TimelineView(slow) { timeline in
                Color.clear.onChange(of: timeline.date) { _, _ in slowChanges += 1 }
            }
            .frame(width: 1, height: 1)
        }
    }
}

@MainActor
@Suite("A timeline's entry re-evaluates only its own content", .serialized)
struct TimelineTickScopeTests {
    @Test("An entry runs no body above the timeline, and makes none of its ancestors' children again")
    func noAncestorBodies() {
        resetCounts()
        let app = TestApp(width: 20, height: 3) { Parent() }
        #expect(app.screen.contains("still"))
        warmUp(app)
        let (bodies, inits, runs) = (parentBodies, clockedInits, contentRuns)
        app.advance(by: .seconds(1))
        #expect(contentRuns - runs >= 55, "the timeline's content runs at each of its 60 entries")
        #expect(parentBodies == bodies, "the parent's body read nothing that moved")
        #expect(clockedInits == inits, "nor was the timeline's own view made again")
    }

    @Test("A body kept above a running timeline runs again for its own state and for what it read")
    func keptBodyStillInvalidates() throws {
        resetCounts()
        let level = Level()
        let app = TestApp(width: 30, height: 4) { Counting(level: level) }
        warmUp(app)
        let still = parentBodies
        app.advance(by: .milliseconds(200))
        #expect(parentBodies == still)
        try app.click("Tap")
        #expect(app.screen.contains("taps 1 level 0"))
        level.number = 3
        app.advance(by: .milliseconds(50))
        #expect(app.screen.contains("taps 1 level 3"))
        let settled = parentBodies
        app.advance(by: .milliseconds(200))
        #expect(parentBodies <= settled + 1, "kept again once a frame has shown the timeline still below")
    }

    @Test("A view the timeline is drawn behind is not drawn again at each entry")
    func backgroundContentServed() {
        resetCounts()
        let app = TestApp(width: 20, height: 3) { BackgroundHost() }
        warmUp(app)
        let first = renderRuns
        #expect(first >= 1)
        app.advance(by: .milliseconds(500))
        #expect(renderRuns == first, "30 entries of the timeline behind it; the canvas reads nothing that moved")
    }

    @Test("A view the timeline is drawn over is not drawn again at each entry")
    func overlaidContentServed() {
        resetCounts()
        let app = TestApp(width: 20, height: 3) { OverlayHost() }
        warmUp(app)
        let first = renderRuns
        #expect(first >= 1)
        app.advance(by: .milliseconds(500))
        #expect(renderRuns == first)
    }

    @Test("A timeline's content sees a new date only at its own entries, beside a 60 Hz timeline")
    func slowAnimationKeepsItsPace() {
        resetCounts()
        let app = TestApp(width: 4, height: 2) { TwoTimelines(slow: .animation(minimumInterval: 0.2)) }
        app.advance(by: .seconds(1))
        #expect(fastChanges >= 55)
        #expect((4...6).contains(slowChanges), "five entries a second: \(slowChanges)")
    }
}
