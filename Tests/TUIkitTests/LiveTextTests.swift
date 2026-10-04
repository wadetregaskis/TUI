//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LiveTextTests.swift
//
//  A `Text` whose words are a function of the clock: read at the frame's own
//  date, one wake asked for at the next change and nothing in between, a
//  measure that says when its width lapses, and a plain `Text` untouched.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing
import TUIkitCore

@testable import TUIkit

/// Words that step every `step` seconds from `origin` — "tick 0", "tick 1", … —
/// and stop changing at `until`, when given.
private struct TickSource: LiveTextSource, Equatable {
    let origin: Date
    var step: Double = 1
    var until: Date?

    private func ticks(at date: Date) -> Int {
        let capped = until.map { min(date, $0) } ?? date
        return Int((capped.timeIntervalSince(origin) / step).rounded(.down))
    }

    func text(at date: Date, in environment: LiveTextEnvironment) -> String {
        "tick \(ticks(at: date))"
    }

    func nextChange(after date: Date, in environment: LiveTextEnvironment) -> Date? {
        let next = origin.addingTimeInterval(Double(ticks(at: date) + 1) * step)
        if let until, next > until { return nil }
        return next
    }
}

/// A row memoized by a title that never changes, around a live text: the shape
/// of a `ForEach` row over a "2 min ago".
private struct TitledLive: View, @preconcurrency Equatable {
    let title: String
    let source: TickSource

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title }

    var body: some View { Text(live: source) }
}

@MainActor
@Suite("Live Text")
struct LiveTextTests {
    private let second: Int64 = 1_000_000_000
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// A render context whose frame clock reads zero, so a declared wake's
    /// firing instant IS the delay that was asked for.
    private func harness(width: Int = 40) -> (TUIContext, RenderContext, AnimationScheduler) {
        let tui = TUIContext()
        let scheduler = AnimationScheduler()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = width
        environment.animationScheduler = scheduler
        environment.frameNowNanos = 0
        return (
            tui,
            RenderContext(
                availableWidth: width, availableHeight: 8, environment: environment, tuiContext: tui),
            scheduler
        )
    }

    /// One frame at `date`, fenced as the loop fences it.
    private func render(
        _ view: some View, at date: Date, tui: TUIContext, context: RenderContext,
        scheduler: AnimationScheduler
    ) -> FrameBuffer {
        tui.mouseEventDispatcher.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        tui.renderCache.frameDate = date
        context.environment.focusManager?.beginRenderPass()
        scheduler.beginFrame()
        let buffer = renderToBuffer(view, context: context)
        scheduler.endFrame()
        tui.stateStorage.endRenderPass()
        context.environment.focusManager?.endRenderPass()
        return buffer
    }

    // MARK: - What it draws

    @Test("A live text draws its words at the frame's date, not the clock's")
    func readsTheFrameDate() {
        let (tui, context, scheduler) = harness()
        let text = Text(live: TickSource(origin: base))
        let drawn = render(text, at: base.addingTimeInterval(42.5), tui: tui, context: context, scheduler: scheduler)
        #expect(drawn.lines.map(\.stripped) == ["tick 42"])
    }

    @Test("A live text alone draws exactly the bytes of a plain text with its words")
    func plainBytes() {
        let (tui, context, scheduler) = harness()
        let at = base.addingTimeInterval(7)
        for (live, plain) in [
            (Text(live: TickSource(origin: base)), Text(verbatim: "tick 7")),
            (Text(live: TickSource(origin: base)).bold().foregroundStyle(.red), Text(verbatim: "tick 7").bold().foregroundStyle(.red)),
        ] {
            let drawn = render(live, at: at, tui: tui, context: context, scheduler: scheduler)
            let expected = render(plain, at: at, tui: tui, context: context, scheduler: scheduler)
            #expect(drawn.lines == expected.lines)
            #expect(drawn.width == expected.width)
        }
    }

    @Test("A live run keeps its place and the styling around it in a concatenation")
    func concatenation() {
        let (tui, context, scheduler) = harness()
        let at = base.addingTimeInterval(3)
        let joined = Text("Ends ").bold() + Text(live: TickSource(origin: base)) + Text(verbatim: "!")
        let plain = Text("Ends ").bold() + Text(verbatim: "tick 3") + Text(verbatim: "!")
        let drawn = render(joined, at: at, tui: tui, context: context, scheduler: scheduler)
        #expect(drawn.lines.map(\.stripped) == ["Ends tick 3!"])
        #expect(drawn.lines == render(plain, at: at, tui: tui, context: context, scheduler: scheduler).lines)
    }

    @Test("What a live text holds as its string is its reading when it was built")
    func contentIsTheReadingWhenBuilt() {
        let text = Text(live: TickSource(origin: Date().addingTimeInterval(-5)))
        #expect(text.content == "tick 5" || text.content == "tick 6")
        #expect(text.isLive)
        #expect(!Text("plain").isLive)
    }

    @Test("Two live texts are equal when their sources are")
    func equality() {
        // Stopped at `base`, so both read the same however far apart they are built.
        let first = Text(live: TickSource(origin: base, step: 2, until: base))
        let second = Text(live: TickSource(origin: base, step: 2, until: base))
        #expect(first == second)
        // The same reading now, a different source: not equal.
        let bigStep = TickSource(origin: Date().addingTimeInterval(-0.5), step: 3_600)
        let otherStep = TickSource(origin: Date().addingTimeInterval(-0.5), step: 7_200)
        #expect(Text(live: bigStep) != Text(live: otherStep))
    }

    // MARK: - What it asks the run loop for

    @Test("A live text asks for one wake, just past its next change")
    func declaresTheNextChange() throws {
        let (tui, context, scheduler) = harness()
        _ = render(
            Text(live: TickSource(origin: base, step: 60)), at: base.addingTimeInterval(15),
            tui: tui, context: context, scheduler: scheduler)
        #expect(scheduler.liveWakeCount == 1)
        let firing = try #require(scheduler.nextFiring(after: 0))
        // 45 s to the next minute, and the millisecond of slack.
        #expect(firing == 45 * second + 1_000_000)
    }

    @Test("A live text that will not change again asks for nothing, and the screen goes idle")
    func finishedIsIdle() {
        let (tui, context, scheduler) = harness()
        let source = TickSource(origin: base, until: base.addingTimeInterval(10))
        _ = render(
            Text(live: source), at: base.addingTimeInterval(20), tui: tui, context: context,
            scheduler: scheduler)
        #expect(scheduler.isIdle)
    }

    @Test("A plain text and a plain concatenation ask for nothing")
    func plainTextsAreIdle() {
        let (tui, context, scheduler) = harness()
        _ = render(
            VStack { Text("a"); Text("b").bold() + Text("c") }, at: base, tui: tui, context: context,
            scheduler: scheduler)
        #expect(scheduler.isIdle)
    }

    @Test("A measure asks for no wake, even when it measures by rendering")
    func measureAsksForNoWake() {
        let (tui, context, scheduler) = harness()
        var measuring = context
        measuring.isMeasuring = true
        tui.renderCache.frameDate = base
        scheduler.beginFrame()
        _ = renderToBuffer(Text(live: TickSource(origin: base)), context: measuring)
        _ = measureChild(Text(live: TickSource(origin: base)), proposal: ProposedSize(width: 40, height: 8), context: context)
        scheduler.endFrame()
        #expect(scheduler.isIdle)
    }

    @Test("A measure records a read of the clock that moves at the next change, however it is measured")
    func measureDeclaresTheClock() {
        let (tui, context, _) = harness()
        tui.renderCache.frameDate = base.addingTimeInterval(15)
        for byRendering in [false, true] {
            var tracked = context
            let tracker = VolatileReadTracker()
            tracked.environment.volatileReadTracker = tracker
            let mark = tracker.beginScope()
            let text = Text(live: TickSource(origin: base, step: 60))
            if byRendering {
                tracked.isMeasuring = true
                _ = renderToBuffer(text, context: tracked)
            } else {
                _ = measureChild(text, proposal: ProposedSize(width: 40, height: 8), context: tracked)
            }
            #expect(tracker.sizeHold(since: mark) == .until(base.addingTimeInterval(60)))
            tracker.endScope(mark)
        }
    }

    @Test("A live text opts the subtree that draws it out of value memoization")
    func marksTheSubtreeVolatile() {
        let (tui, context, scheduler) = harness()
        var tracked = context
        let tracker = VolatileReadTracker()
        tracked.environment.volatileReadTracker = tracker
        _ = render(
            Text(live: TickSource(origin: base)), at: base, tui: tui, context: tracked, scheduler: scheduler)
        #expect(tracker.cacheUnsafeCount > 0)
    }

    // MARK: - Across frames

    @Test("A memoized row around a live text draws and lays out each frame's words")
    func memoizedRowFollowsTheClock() {
        let (tui, context, scheduler) = harness()
        let row = HStack(spacing: 0) {
            TitledLive(title: "t", source: TickSource(origin: base)).equatable()
            Text("|")
        }
        #expect(render(row, at: base.addingTimeInterval(9), tui: tui, context: context, scheduler: scheduler)
            .lines.map(\.stripped) == ["tick 9|"])
        _ = render(row, at: base.addingTimeInterval(9.5), tui: tui, context: context, scheduler: scheduler)
        let later = render(row, at: base.addingTimeInterval(100), tui: tui, context: context, scheduler: scheduler)
        #expect(later.lines.map(\.stripped) == ["tick 100|"], "the row kept the words, or the width, of the frame before")
    }
}
