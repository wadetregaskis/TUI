//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollWindowHoldAppTests.swift
//
//  The top-row hold (`ScrollWindowHold`, `Documentation/Layout and
//  scrolling/Scroll anchoring.md` §5) in a running app: the run loop's own
//  frames — the measuring walk before each one included — a wheel scroll the
//  way a user makes one, and rows arriving above through an `@Observable`
//  model. `ScrollWindowHoldTests` drives each path directly; this is the
//  shape a "load earlier messages" button has in an app.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

@Observable
@MainActor
private final class Feed {
    var ids: [Int] = Array(100..<160)
}

private struct FeedApp: App {
    let feed: Feed?

    init() { feed = nil }

    init(_ feed: Feed) { self.feed = feed }

    var body: some Scene {
        WindowGroup {
            if let feed { FeedPage(feed: feed) }
        }
    }
}

private struct FeedPage: View {
    let feed: Feed

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(feed.ids, id: \.self) { Text(verbatim: "message \($0)") }
            }
        }
        // No bar: its thumb moves as the content grows, whatever the rows do.
        .scrollIndicators(.hidden)
        .frame(height: 8)
    }
}

@MainActor
@Suite("The top-row hold in a running app")
struct ScrollWindowHoldAppTests {

    @Test("Messages loaded above the ones a wheel scrolled to leave them where they are")
    func loadEarlierKeepsThePlace() {
        let feed = Feed()
        let app = TestApp(FeedApp(feed), width: 30, height: 10)
        var now: Int64 = 0
        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }
        func screen() -> [String] { app.screen.lines }
        frame()
        frame()
        for _ in 0..<5 {
            app.send(MouseEvent(button: .scrollDown, phase: .scrolled, x: 2, y: 3))
            frame()
        }
        let before = screen()
        #expect(
            !before.contains { $0.contains("message 100") } && before.contains { $0.contains("message 1") },
            "precondition: scrolled down from the first message \(before)")
        feed.ids.insert(contentsOf: 80..<100, at: 0)
        frame()
        #expect(screen() == before, "before: \(before)\nafter:  \(screen())")
    }
}
