//  🖥️ TUI — A Terminal UI framework for Swift
//  ListWheelBetweenFramesTests.swift
//
//  A wheel over a List, between frames, can render rows the frame did not:
//  the bound of how far it may scroll is a walk up from the last row, and a
//  lazy row is rendered for its height, in the context the list captured when
//  it last rendered. When the frame since then kept the list (an unfocused one
//  inside a stored memo), that context names an earlier walk's volatile-read
//  tracker than the one the render cache mirrored for the measure memo, which
//  then stored what it measured against counters nothing was recording to.
//  Debug builds trapped on `memoizedMeasure`'s assertion; release builds kept
//  the size, whatever the row had read. Found in the Example's Lists page.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUILists
import TUITesting
@testable import TUITestSupport
@testable import TUIView

@Observable
@MainActor
private final class Ticker {
    var tick = 0
}

@MainActor
@Suite("A wheel between frames resolves a lazy List row")
struct ListWheelBetweenFramesTests {
    private struct Row: Identifiable {
        let id: Int
        var name: String { "file \(id)" }
    }

    /// Something else on the page to change, so a frame is drawn that keeps
    /// the list.
    private struct TickLabel: View {
        let ticker: Ticker
        var body: some View { Text(verbatim: "tick \(ticker.tick)") }
    }

    /// The list, stored by its memo while nothing it shows changes. Rows of two
    /// views, so a row's render measures them.
    private struct Files: View, Equatable {
        @State private var selection: Int?
        let rows = (0..<40).map(Row.init)

        nonisolated static func == (lhs: Self, rhs: Self) -> Bool { true }

        var body: some View {
            List("Files", selection: $selection) {
                ForEach(rows) { row in
                    HStack(spacing: 1) {
                        Text("•")
                        Text(row.name)
                    }
                }
            }
            .frame(height: 8)
        }
    }

    private struct Page: View {
        let ticker: Ticker

        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                // Takes the focus, so the list's registrations are replayable
                // and its memo is kept: a focused list is drawn every frame.
                Button("Focus") {}
                TickLabel(ticker: ticker)
                Files().equatable()
            }
        }
    }

    @Test("A wheel after a frame that kept the list measures its unbuilt rows with no stale tracker")
    func wheelAfterAKeptFrame() throws {
        let ticker = Ticker()
        let app = TestApp(width: 30, height: 16) { Page(ticker: ticker) }
        // Each round: a frame that keeps the list, then two ticks of the wheel
        // in one burst, as a terminal sends them. Somewhere past the list's
        // floor the second tick asks for the bound with the first tick's
        // offset, and the walk renders the last rows, which no frame drew.
        for _ in 0..<20 {
            ticker.tick += 1
            app.advance(by: .milliseconds(100))
            // Between frames no walk is running, so no tracker of one is
            // what the measure memo reads: what the wheel measures is kept
            // nowhere. (Debug builds also trap in `memoizedMeasure` if it is.)
            #expect(app.renderCache.volatileReadTracker == nil, "a walk's tracker outlived it")
            try app.scroll(.down, by: 2, over: "Files")
        }
        #expect(app.screen.contains("file 39"), "\(app.screen)")
    }
}
