//  🖥️ TUI — A Terminal UI framework for Swift
//  ListBreathOutrunTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
import TUILists
@testable import TUIStyling
@testable import TUITestSupport

/// A focused list's cursor row breathes by handing the loop every frame of its breath
/// as runs, to replay between renders. A list drawn again before the breath next steps
/// — one with a live `TimelineView` in a row, drawn every tick — would never have one
/// replayed, so it builds only the frame on screen (`RedrawForecast`): the same lines,
/// and none of the sixteen frames it used to build beside them.
@MainActor
@Suite("A focused List drawn again before its breath steps builds only the frame on screen")
struct ListBreathOutrunTests {

    /// Renders `view` three times in one app, a sixtieth of a second apart — the
    /// first pass registers the focus stops, and the focus is then given to "rows"
    /// — and returns the last pass's buffer. Without `scheduling`, no animation
    /// scheduler is wired in, so nothing says when the list is drawn next.
    private func lastFrame(_ view: some View, scheduling: Bool = true) -> FrameBuffer {
        var tick = 0
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let scheduler = AnimationScheduler()
        func pass() -> FrameBuffer {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tuiContext)
            // A fresh tracker a pass, as the render loop installs one: what says that
            // something inside the list did what no memo can keep.
            environment.installVolatileReadTracker(VolatileReadTracker())
            if scheduling { environment.animationScheduler = scheduler }
            environment.frameNowNanos = Int64(tick) * 16_666_667
            let context = RenderContext(
                availableWidth: 40, availableHeight: 30, environment: environment, tuiContext: tuiContext)
            tuiContext.preferences.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            // Every row's timeline at a new entry, as on every tick of a live page.
            tuiContext.renderCache.frameDate = Date(timeIntervalSinceReferenceDate: 800_000_000 + Double(tick) / 60)
            tick += 1
            focusManager.beginRenderPass()
            scheduler.beginFrame()
            let buffer = renderToBuffer(view, context: context)
            tuiContext.renderCache.endVolatileReadTracking()
            scheduler.endFrame()
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
            return buffer
        }
        _ = pass()
        focusManager.focus(id: "rows")
        _ = pass()
        return pass()
    }

    /// A row with a live canvas in its own timeline, beside its title.
    private struct LiveRow: View {
        let index: Int

        var body: some View {
            HStack {
                TimelineView(.animation) { timeline in
                    let phase = Int(timeline.date.timeIntervalSinceReferenceDate * 60) % 8
                    Canvas { context, _ in
                        context.fill(Path(CGRect(x: phase, y: 0, width: 2, height: 1)), with: .color(.red))
                    }
                }
                .frame(width: 10, height: 2)
                Text(verbatim: "row \(index)")
            }
        }
    }

    private func list(live: Bool, spinning: Bool = false) -> some View {
        List(selection: .constant(Set([0]))) {
            ForEach(0..<4, id: \.self) { index in
                HStack {
                    if live { LiveRow(index: index) } else { Text(verbatim: "row \(index)") }
                    if spinning { Spinner(style: .dots) }
                }
            }
        }
        .focusID("rows")
    }

    /// The cursor row's breath: the list's runs, which its rows (a canvas and a title)
    /// leave none of their own among.
    private func breath(_ buffer: FrameBuffer) -> [AnimatedCellRun] {
        buffer.animatedCells.filter { $0.frames.count > 1 }
    }

    @Test("A list of live rows draws its cursor row's breath at the step on screen, and builds no other")
    func liveRowsBuildOneFrame() {
        let outrun = lastFrame(list(live: true))
        #expect(breath(outrun).isEmpty, "the breath was built for a list drawn again before it steps")

        // The same frame where nothing says when the list is drawn next: the breath
        // is built whole, and the frame on screen is the one the outrun list drew.
        let whole = lastFrame(list(live: true), scheduling: false)
        #expect(!breath(whole).isEmpty, "with no scheduler, the cursor row did not breathe")
        #expect(outrun.lines == whole.lines, "the frame on screen moved")
    }

    /// A row whose content animates leaves its runs under the breath, and the breath's
    /// run is what carries their line between renders; the wake the row asks for its
    /// spinner's next step must not stand in for it.
    @Test("A cursor row with a spinner among live rows still hands the loop its whole breath")
    func spinningRowBreathesAmongLiveRows() {
        let buffer = lastFrame(list(live: true, spinning: true))
        let spinnerTicks = AnimationClock.frameTicks(forSeconds: SpinnerStyle.dots.interval)
        let line = buffer.lines.firstIndex { $0.stripped.contains("row 0") }
        let onRow = buffer.animatedCells.filter { $0.offsetY == line && $0.isAnimating }
        #expect(
            onRow.contains { $0.frameTicks != spinnerTicks },
            "the cursor row left no breath under its spinner: \(onRow.map(\.frameTicks))")
    }

    @Test("A list at rest still hands the loop its cursor row's whole breath")
    func restingRowsBreathe() {
        let runs = breath(lastFrame(list(live: false)))
        #expect(!runs.isEmpty, "the cursor row of a resting list did not breathe")
        #expect(runs.allSatisfy { $0.frames.count > 2 }, "the breath had too few frames: \(runs.map(\.frames.count))")
    }

    /// The forecast counts only what this frame has declared: a lattice left from the
    /// frame before may belong to a view that is gone, and then its render never comes.
    @Test("Mid-frame, only the renders this frame has asked for count")
    func onlyThisFramesRequestsCount() {
        let scheduler = AnimationScheduler()
        scheduler.beginFrame()
        scheduler.request("left-over", AnimationRequest(frameTicks: 1))
        scheduler.endFrame()
        scheduler.beginFrame()
        #expect(scheduler.nextFiring(after: 0) != nil, "the loop still knows last frame's lattice")
        #expect(scheduler.nextFiringDeclaredThisFrame(after: 0) == nil, "a lattice not declared again counted")
        scheduler.requestWake("declared", at: 50_000_000)
        #expect(scheduler.nextFiringDeclaredThisFrame(after: 0) == 50_000_000)
        scheduler.request("left-over", AnimationRequest(frameTicks: 1))
        #expect(scheduler.nextFiringDeclaredThisFrame(after: 0) == AnimationClock.nanoseconds(atTick: 1))
        scheduler.endFrame()
    }
}
