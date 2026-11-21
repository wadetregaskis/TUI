//  🖥️ TUI — A Terminal UI framework for Swift
//  AnimationTriggerUnderMemoTests.swift
//
//  `.animation(_:value:)` remembers the value it watches through the frames a
//  memo serves its view on.
//
//  The modifier tells a change from a re-render by the value it saw last, which
//  the animation store keeps for as long as the modifier goes on asking. Under a
//  memo's hit nothing below is drawn, so nothing asked: the store forgot the
//  value at the end of the first served frame, the next change was a first
//  sight, which never animates, and the row jumped. Every `ForEach` row over
//  `Equatable` data is under such a memo.
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
@testable import TUIView

/// A bar whose length is its one continuous property, after a name to find its
/// line by.
private struct NamedBar: View, Animatable {
    let name: String
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    var body: some View {
        Text(name + String(repeating: "#", count: max(0, Int((fraction * 10).rounded()))))
    }
}

/// A to-do item: `Equatable`, so `ForEach` memoizes its row.
private struct Item: Identifiable, Equatable {
    let id: String
    var isDone = false
    var note = ""
}

@Observable
private final class Items {
    var all = [Item(id: "a"), Item(id: "b"), Item(id: "c")]
    /// Read by ``Clock`` alone.
    var ticks = 0
}

/// Rows that animate their own item's `isDone`, each under its row's memo.
private struct Rows: View {
    let items: Items

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items.all) { item in
                NamedBar(name: item.id + item.note, fraction: item.isDone ? 1 : 0)
                    .animation(.linear(duration: 1), value: item.isDone)
            }
        }
    }
}

/// A bar that animates the value it was made with: a view of an app's own,
/// which the plain memo keeps while that value stands.
private struct WatchedBar: View {
    let isDone: Bool

    var body: some View {
        NamedBar(name: "w", fraction: isDone ? 1 : 0).animation(.linear(duration: 1), value: isDone)
    }
}

/// Something else on the page that changes: what makes a frame in which the
/// bar beside it is served.
private struct Clock: View {
    let items: Items

    var body: some View { Text("t\(items.ticks)") }
}

/// The rows beside a clock. A write to an item drops every row (a row holding
/// the modifier is not `Equatable`, so it cannot be re-checked by its value),
/// so the frames that serve the rows are the clock's.
private struct Page: View {
    let items: Items

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rows(items: items)
            Clock(items: items)
        }
    }
}

@MainActor
@Suite("An animation's watched value outlives the frames a memo serves it on")
struct AnimationTriggerUnderMemoTests {
    private static let millisecond: Int64 = 1_000_000

    /// How long the bar named `name` is drawn.
    private func length(of name: String, in app: TestApp) -> Int? {
        app.screen.line(containing: name).map { line in line.count { $0 == "#" } }
    }

    /// The first two frames. The first teaches the cache that the page's
    /// bodies read an `@Observable`, which drops the whole cache once, as the
    /// second begins: from the third on, what is unchanged is served.
    private func start(_ app: TestApp) {
        app.frame(atNanos: 0)
        app.frame(atNanos: Self.millisecond / 2)
    }

    /// Draws a frame at `millis` for the clock's sake, and reports whether
    /// anything was served in it.
    private func tick(_ app: TestApp, _ items: Items, atMillis millis: Int64) -> Bool {
        let before = app.renderCache.rowWork.servedDrawing
        items.ticks += 1
        app.frame(atNanos: millis * Self.millisecond)
        return app.renderCache.rowWork.servedDrawing > before
    }

    @Test("A row a memo served, then changed, animates")
    func rowServedThenChangedAnimates() {
        let items = Items()
        let app = TestApp(width: 20, height: 5) { Page(items: items) }
        start(app)
        #expect(length(of: "b", in: app) == 0)
        #expect(tick(app, items, atMillis: 100), "nothing was served, so this proved nothing")

        // The change the modifier watches for.
        items.all[1].isDone = true
        app.frame(atNanos: 200 * Self.millisecond)
        #expect(length(of: "b", in: app) == 0, "the change jumped to its end")
        app.frame(atNanos: 700 * Self.millisecond)
        #expect(length(of: "b", in: app) == 5)
        app.frame(atNanos: 1200 * Self.millisecond)
        #expect(length(of: "b", in: app) == 10)
    }

    @Test("Served through many frames, a row still animates its next change")
    func rowServedThroughManyFramesAnimates() {
        let items = Items()
        let app = TestApp(width: 20, height: 5) { Page(items: items) }
        start(app)
        // More frames than a served record is kept for with nothing asking
        // (`AnimationStore.keepPasses`).
        var served = 0
        for frame in 1...150 where tick(app, items, atMillis: Int64(frame)) { served += 1 }
        #expect(served == 150, "the rows were not served every frame")
        items.all[1].isDone = true
        app.frame(atNanos: 200 * Self.millisecond)
        #expect(length(of: "b", in: app) == 0, "the change jumped to its end")
        app.frame(atNanos: 700 * Self.millisecond)
        #expect(length(of: "b", in: app) == 5)
    }

    @Test("A view the plain memo served, then changed, animates")
    func plainMemoServedThenChangedAnimates() {
        let items = Items()
        let app = TestApp(width: 20, height: 4) {
            VStack(alignment: .leading, spacing: 0) {
                WatchedBar(isDone: items.all[0].isDone)
                Clock(items: items)
            }
        }
        start(app)
        #expect(length(of: "w", in: app) == 0)
        #expect(tick(app, items, atMillis: 100), "nothing was served, so this proved nothing")

        items.all[0].isDone = true
        app.frame(atNanos: 200 * Self.millisecond)
        #expect(length(of: "w", in: app) == 0, "the change jumped to its end")
        app.frame(atNanos: 700 * Self.millisecond)
        #expect(length(of: "w", in: app) == 5)
    }

    @Test("A row that left and came back is a first sight, and does not animate")
    func rowThatLeftAndCameBackAppears() {
        let items = Items()
        let app = TestApp(width: 20, height: 5) { Page(items: items) }
        start(app)
        // Served once, so the memo is what keeps its watched value.
        #expect(tick(app, items, atMillis: 100))

        let gone = items.all.remove(at: 1)
        app.frame(atNanos: 200 * Self.millisecond)
        #expect(length(of: "b", in: app) == nil)

        var back = gone
        back.isDone = true
        items.all.insert(back, at: 1)
        app.frame(atNanos: 300 * Self.millisecond)
        #expect(length(of: "b", in: app) == 10, "an appearance is not a change")
    }
}
