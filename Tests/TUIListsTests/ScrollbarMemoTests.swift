//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollbarMemoTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUILists
@testable import TUITestSupport
@testable import TUIView

/// A palette edited in place: the id stays while a colour changes, as the
/// Example's Theme page does. `foregroundQuaternary` is the rung the bar's
/// track is drawn from.
private struct EditablePalette: Palette, Hashable {
    var id = "editable"
    var name = "Editable"
    var background: Color = .rgb(0, 0, 0)
    var foreground: Color = .rgb(200, 200, 200)
    var foregroundQuaternary: Color = .rgb(90, 90, 90)
    var accent: Color = .rgb(0, 200, 0)
    var success: Color = .rgb(0, 200, 0)
    var warning: Color = .rgb(200, 200, 0)
    var error: Color = .rgb(200, 0, 0)
    var info: Color = .rgb(0, 200, 200)
    var border: Color = .rgb(100, 100, 100)
}

/// A focused scroll view's bar pulses, and its animated runs were one
/// scrollbar render per pulse frame on every frame. The bar and its runs are
/// kept on the handler with the inputs they were drawn from, and drawn again
/// only when one of those moves.
@MainActor
@Suite("A scrollbar is drawn again only when its inputs move", .serialized)
struct ScrollbarMemoTests {

    @MainActor
    private struct Harness {
        let tui = TUIContext()
        let focusManager = FocusManager()

        /// Whether the content is wide as well as tall, and scrolls both ways.
        var twoAxis = false

        /// The clock the focus breath reads, or none: the step is then 0.
        var timer: CursorTimer?

        func frame(palette: any Palette = SystemPalette(.green)) -> FrameBuffer {
            let rows = VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<60, id: \.self) { index in
                    Text(twoAxis ? "row \(index) " + String(repeating: "=", count: 80) : "row \(index)")
                }
            }
            let view = ScrollView(twoAxis ? [.horizontal, .vertical] : .vertical) { rows }
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tui)
            environment.palette = palette
            if let timer { environment.cursorTimer = timer }
            // Beside the content: these frames compare the bar the first frame
            // draws, which the default (.overContent) draws only for the
            // pointer or the focus, and so not before the view takes the focus.
            environment.scrollIndicatorPlacement = .besideContent
            let context = RenderContext(
                availableWidth: 30, availableHeight: 8, environment: environment, tuiContext: tui)
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tui.renderCache.removeInactive()
            tui.stateStorage.endRenderPass()
            return buffer
        }

        var handler: ScrollViewHandler? {
            focusManager.activeSection?.focusables.compactMap { $0 as? ScrollViewHandler }.first
        }
    }

    @Test("Same inputs: the second frame's bar comes from the memo and matches the first")
    func memoAnswersUnchangedInputs() {
        let harness = Harness()
        let first = harness.frame()
        guard let handler = harness.handler else {
            Issue.record("no scroll handler registered")
            return
        }
        let hitsAfterFirst = handler.verticalScrollbarMemoHits
        let second = harness.frame()
        #expect(handler.verticalScrollbarMemoHits > hitsAfterFirst, "the memo answered: \(handler.verticalScrollbarMemoHits)")
        #expect(first.lines == second.lines)
    }

    @Test("A scrolled offset draws a new bar")
    func offsetInvalidates() {
        let harness = Harness()
        let first = harness.frame()
        guard let handler = harness.handler else {
            Issue.record("no scroll handler registered")
            return
        }
        _ = harness.frame()
        let hitsBefore = handler.verticalScrollbarMemoHits
        handler.scrollOffset = 20
        let scrolled = harness.frame()
        #expect(handler.verticalScrollbarMemoHits == hitsBefore, "moved inputs are not served: \(handler.verticalScrollbarMemoHits) vs \(hitsBefore)")
        #expect(first.lines.map(\.stripped) != scrolled.lines.map(\.stripped))
    }

    @Test("Same inputs: the second frame's HORIZONTAL bar comes from the memo and matches the first")
    func horizontalMemoAnswersUnchangedInputs() {
        var harness = Harness()
        harness.twoAxis = true
        let first = harness.frame()
        guard let handler = harness.handler else {
            Issue.record("no scroll handler registered")
            return
        }
        #expect(handler.horizontal.extent > 30, "precondition: the content scrolls sideways")
        let hitsAfterFirst = handler.horizontalScrollbarMemoHits
        let second = harness.frame()
        #expect(handler.horizontalScrollbarMemoHits > hitsAfterFirst, "the memo did not answer")
        #expect(first.lines == second.lines)
    }

    @Test("A sideways offset draws a new horizontal bar")
    func horizontalOffsetInvalidates() {
        var harness = Harness()
        harness.twoAxis = true
        let first = harness.frame()
        guard let handler = harness.handler else {
            Issue.record("no scroll handler registered")
            return
        }
        _ = harness.frame()
        let hitsBefore = handler.horizontalScrollbarMemoHits
        handler.horizontal.scrollOffset = 30
        let scrolled = harness.frame()
        #expect(handler.horizontalScrollbarMemoHits == hitsBefore, "moved inputs were served")
        #expect(first.lines.last?.stripped != scrolled.lines.last?.stripped, "the bar did not move")
    }

    @Test("A focused scroll view's two bars are served 200 ms on, each showing the frame its clock is on")
    func barsServedAcrossClockSteps() {
        // H-82's measurement, through the view rather than the memo function:
        // the key held the breath's raw clock step, so a focused scroll view
        // re-rendered more than 50 ms after its last render drew both bars
        // and their sixteen frames again (FREND-1). The first frame takes the
        // focus; the next two are 200 ms apart, four steps of the breath.
        let timer = CursorTimer(renderNotifier: AppState())
        var harness = Harness()
        harness.twoAxis = true
        harness.timer = timer
        withColorDepth(.truecolor) {
            timer.observe(nowNanos: 1_000_000_000)
            _ = harness.frame()
            let before = harness.frame()
            guard let handler = harness.handler else {
                Issue.record("no scroll handler registered")
                return
            }
            let hits = (handler.verticalScrollbarMemoHits, handler.horizontalScrollbarMemoHits)
            timer.observe(nowNanos: 1_200_000_000)
            let after = harness.frame()
            var fresh = Harness()
            fresh.twoAxis = true
            fresh.timer = timer
            _ = fresh.frame()
            let drawn = fresh.frame()
            #expect(before.lines != after.lines, "precondition: the breath moved in 200 ms")
            #expect(handler.verticalScrollbarMemoHits > hits.0, "the vertical bar was drawn again")
            #expect(handler.horizontalScrollbarMemoHits > hits.1, "the horizontal bar was drawn again")
            #expect(after.lines == drawn.lines, "the served bars are not the ones drawn afresh at that instant")
        }
    }

    @Test("A palette edited under the same id draws a new bar")
    func paletteEditedInPlaceInvalidates() {
        // The key held only the palette's id, so an edit that kept it served the
        // bar drawn before the edit. The oracle is a harness that has only ever
        // seen the edited palette, rendered the same number of frames, so focus
        // and the pulse are in the same state on both sides.
        var palette = EditablePalette()
        let harness = Harness()
        _ = harness.frame(palette: palette)
        _ = harness.frame(palette: palette)
        palette.foregroundQuaternary = .rgb(90, 0, 90)
        let edited = harness.frame(palette: palette)

        let oracle = Harness()
        _ = oracle.frame(palette: palette)
        _ = oracle.frame(palette: palette)
        let expected = oracle.frame(palette: palette)
        #expect(edited.lines == expected.lines, "the bar kept the colours from before the edit")
    }

    @Test("A view disabled under an unfocused bar draws it again, pinned, where there is no colour")
    func disabledInvalidates() {
        // Without colour a resting thumb is `▒` and a disabled view's `░`
        // (`ScrollbarColors.ThumbWithoutColor`), and nothing else in the key
        // moves when an unfocused view is disabled.
        var remembered: ScrollbarMemo<ClaimingColumn>?
        var hits = 0
        let thumbs = [true, false, false].map { enabled in
            withColorDepth(.noColor) { Self.thumb(enabled: enabled, remembered: &remembered, hits: &hits) }
        }
        #expect(thumbs == ["▒", "░", "░"])
        #expect(hits == 1, "the disabled bar was served the enabled one's, or never kept")
    }

    @Test("A focused bar's memo answers across its breath's clock steps, showing the frame each is on")
    func breathStepsAreServed() {
        // The key held the cycle's raw clock step, which moves every 50 ms
        // while the focus is held: a key typed in a focused editor more than
        // that after the last missed, and drew the bar and its sixteen frames
        // again (FREND-1). Two frames a tick apart, for 48 ticks: every step
        // of the breath three times.
        let timer = CursorTimer(renderNotifier: AppState())
        var remembered: ScrollbarMemo<ClaimingColumn>?
        var hits = 0
        var wrong: [Int] = []
        var shades: Set<[String]> = []
        for tick in 0..<48 {
            timer.creditWake(atNanos: 1_000_000_000 + UInt64(tick) * 16_666_667)
            let kept = Self.focusedBar(timer: timer, remembered: &remembered, hits: &hits)
            var none: ScrollbarMemo<ClaimingColumn>?
            var unused = 0
            let fresh = Self.focusedBar(timer: timer, remembered: &none, hits: &unused)
            if kept.bar.lines != fresh.bar.lines || kept.runs.map(\.frames) != fresh.runs.map(\.frames) {
                wrong.append(tick)
            }
            shades.insert(kept.bar.lines)
        }
        #expect(hits == 47, "the bar was drawn again \(48 - hits) times for inputs that never moved")
        #expect(wrong.isEmpty, "ticks whose kept bar is not the one drawn afresh: \(wrong)")
        #expect(shades.count > 1, "precondition: the breath shows more than one shade")
    }

    @Test("A still focus draws a new bar when the window stops appearing active")
    func stillFocusFollowsActivity() {
        // With the breath off the key held no cycle at all, so the held shade
        // of an inactive window and the bright one of an active window were
        // the same key (FREND-2).
        var remembered: ScrollbarMemo<ClaimingColumn>?
        var hits = 0
        let bars = [true, false, true].map { active in
            var context = makeRenderContext(width: 1, height: 8)
            context.environment.selectionIndicatorStyle = .none
            context.environment.appearsActive = active
            return withColorDepth(.truecolor) {
                ScrollbarMemo.vertical(
                    remembered: &remembered, hits: &hits, length: 8, extent: 32, viewport: 8, offset: 0,
                    arrows: .none, proportional: true, isFocused: true, hoveredCell: nil, flash: nil,
                    context: context
                ).bar.lines
            }
        }
        #expect(hits == 0, "a bar was served across a change of activity")
        #expect(bars[0] != bars[1] && bars[0] == bars[2], "the held and bright bars: \(bars)")
    }

    /// A focused bar eight cells tall over four times its height, drawn
    /// through `remembered` at `timer`'s instant.
    private static func focusedBar(
        timer: CursorTimer, remembered: inout ScrollbarMemo<ClaimingColumn>?, hits: inout Int
    ) -> ScrollbarMemo<ClaimingColumn> {
        var context = makeRenderContext(width: 1, height: 8)
        context.environment.cursorTimer = timer
        return withColorDepth(.truecolor) {
            ScrollbarMemo.vertical(
                remembered: &remembered, hits: &hits, length: 8, extent: 32, viewport: 8, offset: 0,
                arrows: .none, proportional: true, isFocused: true, hoveredCell: nil, flash: nil, context: context)
        }
    }

    /// The first cell of an unfocused bar four cells tall over twice its
    /// height, drawn through `remembered`, its view enabled or not.
    private static func thumb(
        enabled: Bool, remembered: inout ScrollbarMemo<ClaimingColumn>?, hits: inout Int
    ) -> String? {
        var context = makeRenderContext(width: 1, height: 4)
        context.environment.isEnabled = enabled
        return ScrollbarMemo.vertical(
            remembered: &remembered, hits: &hits, length: 4, extent: 8, viewport: 4, offset: 0,
            arrows: .none, proportional: true, isFocused: false, hoveredCell: nil, flash: nil,
            context: context
        ).bar.lines.first?.stripped
    }
}

/// A `List`'s bar is kept on its handler the same way: it never pulses, but every
/// cell of it is a full SGR spelling, drawn afresh each frame for inputs that had
/// not moved.
@MainActor
@Suite("A list's scrollbar is drawn again only when its inputs move", .serialized)
struct ListScrollbarMemoTests {

    @MainActor
    private struct Harness {
        let tui = TUIContext()
        let focusManager = FocusManager()

        func frame(palette: any Palette = SystemPalette(.green), depth: ColorDepth = .truecolor) -> FrameBuffer {
            let view = List(selection: .constant(Int?.none)) {
                ForEach(0..<60, id: \.self) { Text("row \($0)") }
            }
            .scrollIndicators(.visible)
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tui)
            environment.palette = palette
            // Beside the content: these frames compare the bar the first frame
            // draws, which the default (.overContent) draws only for the
            // pointer or the focus, and so not before the list takes the focus.
            environment.scrollIndicatorPlacement = .besideContent
            var context = RenderContext(
                availableWidth: 30, availableHeight: 8, environment: environment, tuiContext: tui)
            context.hasExplicitHeight = true
            return ColorDepth.withCurrent(depth) {
                tui.stateStorage.beginRenderPass()
                tui.renderCache.beginRenderPass()
                focusManager.beginRenderPass()
                let buffer = renderToBuffer(view, context: context)
                focusManager.endRenderPass()
                tui.renderCache.removeInactive()
                tui.stateStorage.endRenderPass()
                return buffer
            }
        }

        var handler: ItemListHandler<Int>? {
            focusManager.activeSection?.focusables.compactMap { $0 as? ItemListHandler<Int> }.first
        }
    }

    @Test("Same inputs: the second frame's bar comes from the memo and matches the first")
    func memoAnswersUnchangedInputs() throws {
        let harness = Harness()
        let first = harness.frame()
        let handler = try #require(harness.handler, "no list handler registered")
        #expect(handler.verticalScrollbarMemo != nil, "precondition: the list draws a bar")
        let hitsAfterFirst = handler.verticalScrollbarMemoHits
        let second = harness.frame()
        #expect(handler.verticalScrollbarMemoHits > hitsAfterFirst, "the memo answered: \(handler.verticalScrollbarMemoHits)")
        #expect(first.lines == second.lines)
    }

    @Test("A scrolled offset, a palette edited in place and another depth each draw a new bar")
    func movedInputsInvalidate() throws {
        var palette = EditablePalette()
        let harness = Harness()
        _ = harness.frame(palette: palette)
        let handler = try #require(harness.handler, "no list handler registered")

        // Each step moves one input; what it draws must be what a harness that
        // has only ever seen the new input draws, frame for frame.
        func expectFresh(_ drawn: FrameBuffer, _ what: String, depth: ColorDepth = .truecolor) {
            let oracle = Harness()
            _ = oracle.frame(palette: palette, depth: depth)
            oracle.handler?.scrollOffset = handler.scrollOffset
            let expected = oracle.frame(palette: palette, depth: depth)
            #expect(drawn.lines == expected.lines, "\(what) served the bar drawn before it")
        }

        handler.scrollOffset = 20
        let hitsBefore = handler.verticalScrollbarMemoHits
        expectFresh(harness.frame(palette: palette), "a scrolled offset")
        #expect(handler.verticalScrollbarMemoHits == hitsBefore, "moved inputs were served")

        palette.foregroundQuaternary = .rgb(90, 0, 90)
        expectFresh(harness.frame(palette: palette), "a palette edited in place")

        expectFresh(harness.frame(palette: palette, depth: .palette256), "another depth", depth: .palette256)
    }
}
