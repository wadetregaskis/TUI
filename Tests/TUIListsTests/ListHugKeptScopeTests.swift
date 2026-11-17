//  🖥️ TUI — A Terminal UI framework for Swift
//  ListHugKeptScopeTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
import TUIFoundation
import TUILists
import TUITesting
@testable import TUIView

/// A clock a leaf reads, as `Stress`'s `StressClock` is.
@Observable
private final class Clock {
    var tick = 0
}

/// How many times a row closure ran: the rows a walk read, and the rows a frame
/// drew. In the environment, as the clock is, so that the page holds only
/// values the plain memo can compare, as an app's page does.
@Observable
private final class Calls {
    @ObservationIgnored var count = 0
}

/// A hugging `List`'s widest-row width outlives a change it never read.
///
/// A plain composite of the app's is memoized (`PlainMemo`), and its kept
/// result is observed by a scope that collects every read made beneath it — a
/// clock a sibling leaf reads, say. When the clock moved, that scope reported
/// at the composite softly, and a soft report drops everything below it that
/// recorded nothing to be re-checked by: the list's width among them, though
/// the list read nothing and its width has a scope of its own. So
/// `app-shapes/sidebar-filtered`, whose detail pane shows a ticking stamp,
/// walked its 1,950 rows twice running each time the memo tried its page
/// again, every 64 frames: 40% of its time. A kept scope's change now drops
/// the result it kept and what holds that, and leaves what is below to the
/// scopes there.
@MainActor
@Suite("A hugging List's width outlives a kept scope's change")
struct ListHugKeptScopeTests {
    private struct Row: Identifiable, Sendable, Equatable {
        let id: Int
        var name: String { id == 3 ? "Wolfgang" : "ab" }
    }

    /// A leaf that reads the clock, as `Stress`'s `TickStamp` does.
    private struct Stamp: View {
        @Environment(Clock.self) private var clock
        var body: some View { Text(verbatim: "\(clock.tick)") }
    }

    /// The app's own composite, so the plain memo keeps what it draws: a list
    /// hugging its widest row, beside a stamp.
    private struct Page: View {
        let rows: [Row]
        @Environment(Calls.self) private var calls

        var body: some View {
            HStack(spacing: 1) {
                List(rows) { (row: Row) -> Text in
                    calls.count += 1
                    return Text(verbatim: row.name)
                }
                .fixedSize(horizontal: true)
                Stamp()
            }
        }
    }

    private static let frame: Int64 = 16_666_667

    /// The clock moves every frame, as `Stress`'s does, so neither the stamp's
    /// memo nor the page's can be served: each fails twice and rests, for 4, 8,
    /// 16, 32 and then 64 passes, and is tried again. Each try of the page's
    /// stores it with the stamp drawn inside it, so its scope reads the clock,
    /// and the next tick reported there.
    @Test("A clock read beside the list, ticking every frame, never walks its rows again")
    func tickBesideTheListKeepsItsWidth() {
        let rows = (0..<300).map(Row.init)
        let clock = Clock()
        let calls = Calls()
        let app = TestApp(width: 60, height: 12) { Page(rows: rows).environment(clock).environment(calls) }
        #expect(app.renderCache.plainMemo.isOn, "the memo whose scope this is about")
        // The opening frames: the list's own state, the stamp's type learned to
        // read (a clear of everything), and the first walk.
        for frame in 0..<4 {
            if frame > 0 { clock.tick += 1 }
            app.frame(atNanos: Int64(frame) * Self.frame)
        }

        // Through the page's tries at 7, 16, 33 and 66 passes, give or take
        // the pass its memo stores in.
        calls.count = 0
        for frame in 4..<72 {
            clock.tick += 1
            app.frame(atNanos: Int64(frame) * Self.frame)
        }
        #expect(app.screen.contains("\(clock.tick)"), "the tick is drawn")
        // The drawn rows are served from their own memos, so a frame that does
        // not walk calls the closure for few rows, if any; a walk calls it for
        // every one of them.
        #expect(calls.count < rows.count, "68 frames read \(calls.count) rows of \(rows.count)")
    }
}
