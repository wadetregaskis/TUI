//  🖥️ TUI — A Terminal UI framework for Swift
//  CanvasBesideTimelineTests.swift
//
//  A `Canvas` beside a `TimelineView` is not drawn again on every entry of the
//  timeline: a game's board beside its 60 Hz loop. SwiftUI re-evaluates only the
//  timeline's content on a tick; TUI redrew the whole of the timeline's
//  ancestors, and the canvas, which had no memo of its own, ran its renderer at
//  every frame (tuiarcade's TUI-FEEDBACK.md, M1 item 1). And the canvas is still
//  drawn again when what its renderer reads changes.
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

/// How many times a renderer below ran. A global, not a capture, so the
/// renderer of `StillBoard` captures nothing, as the app's did.
@MainActor private var renderRuns = 0

/// What drives the frames: a `TimelineView` on the animation schedule whose
/// content reads its date, beside the board rather than around it.
private struct Ticker: View {
    var body: some View {
        Text("loop").background {
            TimelineView(.animation) { timeline in
                Color.clear.onChange(of: timeline.date) { _, _ in }
            }
        }
    }
}

/// A canvas that reads nothing, beside the ticker: the feedback's repro.
private struct StillBoard: View {
    var body: some View {
        HStack {
            Canvas { context, _ in
                MainActor.assumeIsolated { renderRuns += 1 }
                for column in 0..<4 {
                    context.fill(Path(CGRect(x: column * 2, y: 0, width: 2, height: 2)), with: .color(.blue))
                }
            }
            .frame(width: 8, height: 1)
            Ticker()
        }
    }
}

/// A canvas whose renderer captures the board's `@State`, beside the ticker.
private struct LevelBoard: View {
    @State private var level = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Up") { level += 1 }
            HStack {
                Canvas { context, _ in
                    MainActor.assumeIsolated { renderRuns += 1 }
                    context.draw(Text(verbatim: "L\(level)"), in: CGRect(x: 0, y: 0, width: 4, height: 2))
                }
                .frame(width: 4, height: 1)
                Ticker()
            }
        }
    }
}

@MainActor
@Observable
private final class Score {
    var points = 0
}

/// A canvas whose renderer reads an `@Observable` model, beside the ticker.
private struct ScoreBoard: View {
    let score: Score

    var body: some View {
        HStack {
            Canvas { context, _ in
                let points = MainActor.assumeIsolated {
                    renderRuns += 1
                    return score.points
                }
                context.draw(Text(verbatim: "P\(points)"), in: CGRect(x: 0, y: 0, width: 4, height: 2))
            }
            .frame(width: 4, height: 1)
            Ticker()
        }
    }
}

@MainActor
@Suite("A Canvas beside a TimelineView", .serialized)
struct CanvasBesideTimelineTests {
    @Test("A canvas that reads nothing is drawn once, not on every frame of the timeline beside it")
    func stillCanvasIsServed() {
        renderRuns = 0
        let app = TestApp(width: 20, height: 2) { StillBoard() }
        #expect(app.screen.contains("loop"))
        let first = renderRuns
        #expect(first >= 1)
        app.advance(by: .milliseconds(500))
        #expect(app.elapsed == .milliseconds(500))
        #expect(renderRuns == first, "the timeline drew about 30 frames; the canvas reads nothing that moved")
    }

    @Test("A canvas whose renderer captured state is drawn again when that state is written")
    func capturedStateRedraws() throws {
        renderRuns = 0
        let app = TestApp(width: 20, height: 3) { LevelBoard() }
        #expect(app.screen.contains("L0"))
        app.advance(by: .milliseconds(250))
        let still = renderRuns
        try app.click("Up")
        #expect(app.screen.contains("L1"))
        #expect(renderRuns > still)
        let afterWrite = renderRuns
        app.advance(by: .milliseconds(250))
        #expect(renderRuns == afterWrite)
        #expect(app.screen.contains("L1"))
    }

    @Test("A canvas whose renderer read a model is drawn again when the model changes")
    func observedModelRedraws() {
        renderRuns = 0
        let score = Score()
        let app = TestApp(width: 20, height: 2) { ScoreBoard(score: score) }
        #expect(app.screen.contains("P0"))
        app.advance(by: .milliseconds(250))
        let still = renderRuns
        score.points = 7
        app.advance(by: .milliseconds(20))
        #expect(app.screen.contains("P7"))
        #expect(renderRuns > still)
    }
}
