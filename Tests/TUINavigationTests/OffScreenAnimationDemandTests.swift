//  🖥️ TUI — A Terminal UI framework for Swift
//  OffScreenAnimationDemandTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUINavigation
@testable import TUITestSupport
@testable import TUIView

/// A view that builds its appearance from the pulse phase WHILE rendering, so
/// nothing can replay it and it must ask for a render every tick.
///
/// The shape a multi-row `Button`'s caps already take (`ButtonStyle.swift`,
/// `recordVolatileRead`), reduced to the one line that matters.
private struct TickHungryProbe: View, Renderable {
    var body: Never { fatalError("TickHungryProbe renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        context.environment.volatileReadTracker?.recordVolatileRead()
        return FrameBuffer(text: "tick")
    }
}

/// A view whose animation is driven by the scheduler alone — no volatile read,
/// no ``AnimatedCellRun``. The `Spinner` fallback's shape, and the one the
/// indeterminate bar takes when its colours are translucent.
private struct SchedulerDrivenProbe: View, Renderable {
    var body: Never { fatalError("SchedulerDrivenProbe renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        context.requestAnimation(token: "probe", frameTicks: 3)
        return FrameBuffer(text: "spin")
    }
}

private struct VisibleProbeApp: App {
    init() {}
    var body: some Scene { WindowGroup { TickHungryProbe() } }
}

private struct HiddenProbeApp: App {
    init() {}
    var body: some Scene { WindowGroup { TickHungryProbe().hidden() } }
}

/// The scheduler half of ``HiddenProbeApp``.
private struct HiddenSchedulerApp: App {
    init() {}
    var body: some Scene { WindowGroup { SchedulerDrivenProbe().hidden() } }
}

/// A probe on screen beside one hidden twice over: the inner discard must not
/// be taken again by the outer one, or the probe on screen loses its frames.
private struct VisibleBesideNestedHiddenApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            VStack {
                TickHungryProbe().hidden().hidden()
                TickHungryProbe()
            }
        }
    }
}

/// A view that presents a screen-level layer — a sheet's shape — and reads the
/// pulse, as a sheet's content can.
private struct PresentingProbe: View, Renderable {
    var body: Never { fatalError("PresentingProbe renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        context.environment.volatileReadTracker?.recordVolatileRead()
        context.requestAnimation(token: "presented", frameTicks: 3)
        var buffer = FrameBuffer(text: "page")
        buffer.overlays.append(
            OverlayLayer(offsetX: 0, offsetY: 0, content: FrameBuffer(text: "sheet"), level: .modal, centered: true))
        return buffer
    }
}

/// A hidden view that presents a sheet: the sheet stays on screen, so the
/// demand made in the same render is kept with it.
private struct HiddenPresentingApp: App {
    init() {}
    var body: some Scene { WindowGroup { PresentingProbe().hidden() } }
}

/// The probe is the stack's ROOT, and a screen is pushed over it. The root
/// still renders — that is how its `@State` survives being covered — and its
/// buffer is thrown away.
private struct CoveredRootApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: .constant([1])) {
                TickHungryProbe()
                    .navigationDestination(for: Int.self) { _ in Text("detail") }
            }
        }
    }
}

/// A covered root that MEASURES its content — any scroll view does — which
/// the throwaway tracker has to be installed for, mirror and all.
private struct CoveredScrollingRootApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: .constant([1])) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<50, id: \.self) { index in Text("row \(index)") }
                    }
                }
                .navigationDestination(for: Int.self) { _ in Text("detail") }
            }
        }
    }
}

/// The control for the one above: the same stack, with a root that wants
/// nothing. Without it, `usesPulse` being set would not be evidence about the
/// ROOT — a navigation bar or a focused control on the pushed screen would do
/// just as well.
private struct CoveredPlainRootApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: .constant([1])) {
                Text("root")
                    .navigationDestination(for: Int.self) { _ in Text("detail") }
            }
        }
    }
}

private struct SchedulerDrivenApp: App {
    init() {}
    var body: some Scene { WindowGroup { SchedulerDrivenProbe() } }
}

/// The scheduler half of ``CoveredRootApp``: a covered root whose animation is
/// a lattice rather than a volatile read.
private struct CoveredSchedulerRootApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: .constant([1])) {
                SchedulerDrivenProbe()
                    .navigationDestination(for: Int.self) { _ in Text("detail") }
            }
        }
    }
}

/// A DIMMED probe — isolated by the very same helper the covered root uses,
/// and then drawn. The guard on the fix's blast radius.
private struct DimmedProbeApp: App {
    init() {}
    var body: some Scene { WindowGroup { TickHungryProbe().dimmed() } }
}

/// Two of the three ways a view has of saying "render me again" are PASS-wide,
/// and a pass does not know which of its renders reached the screen. An
/// animation that is hidden or covered therefore went on costing a full render
/// twenty times a second while showing nobody anything.
///
/// A render whose buffer is discarded WHOLE can say so: the covered
/// `NavigationStack` root does (`withThrowawayFrameDemand`), and `.hidden()`
/// does whenever its content presents no sheet (§92.2 of `Opacity as
/// composition.md`). `ScrollView`'s window keeps the rows inside the viewport
/// from the same render as the rows outside it, so it cannot; what reads the
/// pulse there is a focused control's, which the window scrolls to.
///
/// The last test is the standing condition rather than a defect, and is here
/// because it is the same fact seen from the other side.
@MainActor
@Suite("An animation nobody can see still asks for frames", .serialized)
struct OffScreenAnimationDemandTests {

    /// The control, and the reason the two below are about visibility rather
    /// than about the probe: on screen it asks for every tick, which is right.
    @Test("A visible tick-hungry view keeps the clock live")
    func visibleKeepsTheClockLive() {
        let harness = RenderLoopHarness()
        let activity = harness.loop(VisibleProbeApp()).render()

        #expect(harness.terminal.allOutput.contains("tick"))
        #expect(activity.usesPulse)
    }

    /// `.hidden()` renders its content and returns an empty buffer, and the
    /// read was counted against a frame that shows none of it. It is now
    /// counted as discarded (`VolatileReadTracker.discardReads(_:)`), since
    /// nothing of the content survives.
    @Test("A hidden one draws nothing and asks for no frames")
    func hiddenMakesNoDemand() {
        let harness = RenderLoopHarness()
        let activity = harness.loop(HiddenProbeApp()).render()

        #expect(!harness.terminal.allOutput.contains("tick"), "nothing is on screen")
        #expect(!activity.usesPulse)
    }

    /// The scheduler channel at the same site: the content's lattices go to a
    /// scheduler of the hidden view's own, which nothing hands on.
    @Test("A hidden one leaves no lattice on the scheduler")
    func hiddenLeavesNoLattice() {
        let harness = RenderLoopHarness()
        let scheduler = AnimationScheduler()
        _ = harness.loop(HiddenSchedulerApp()).render(animationScheduler: scheduler)

        #expect(!harness.terminal.allOutput.contains("spin"))
        #expect(scheduler.isIdle)
    }

    /// The discard is taken net of the discards inside it. Taken from the raw
    /// count, the outer `.hidden()` took the inner one's read a second time,
    /// and the probe on screen lost its frames: a frozen animation, the one
    /// failure this must never have.
    @Test("A hidden view inside a hidden view takes its reads once")
    func nestedHiddenTakesOnce() {
        let harness = RenderLoopHarness()
        let activity = harness.loop(VisibleBesideNestedHiddenApp()).render()

        #expect(harness.terminal.allOutput.contains("tick"), "one probe is on screen")
        #expect(activity.usesPulse)
    }

    /// `.hidden()` keeps screen-level layers, so a `.sheet` presented from
    /// inside a hidden subtree still presents, as SwiftUI's does (measured: a
    /// real, visible sheet window in every arrangement, both modifier orders).
    /// The sheet renders in the same pass as the hidden page, and nothing
    /// tells their demand apart, so all of it is kept: a frame too many rather
    /// than a sheet that stops animating.
    @Test("A hidden view presenting a sheet keeps the demand made with it")
    func hiddenPresentingKeepsDemand() {
        let harness = RenderLoopHarness()
        let scheduler = AnimationScheduler()
        let activity = harness.loop(HiddenPresentingApp()).render(animationScheduler: scheduler)

        #expect(harness.terminal.allOutput.contains("sheet"), "the sheet is on screen")
        #expect(!harness.terminal.allOutput.contains("page"), "the page is hidden")
        #expect(activity.usesPulse)
        #expect(!scheduler.isIdle)
    }

    /// `NavigationStack` renders a covered root to keep its `@State` alive and
    /// drops the buffer (`NavigationStack.swift`, `isolatedForBackground`).
    /// That isolation covers the focus ring, the key channels and the status
    /// bar — every channel by which the invisible root could reach the user —
    /// and left the volatile-read tracker, the channel by which it reached the
    /// CLOCK. It now gets a throwaway for that too.
    @Test("A covered NavigationStack root asks for no frames")
    func coveredRootMakesNoDemand() {
        let harness = RenderLoopHarness()
        let activity = harness.loop(CoveredRootApp()).render()

        #expect(harness.terminal.allOutput.contains("detail"), "the pushed screen is showing")
        #expect(!harness.terminal.allOutput.contains("tick"), "and the root is not")
        #expect(!activity.usesPulse)
    }

    /// The other channel, at the same site: a lattice re-declared from behind a
    /// covering screen kept the scheduler awake, because the scheduler drops
    /// only the tokens that STOP re-declaring and an invisible view re-declares
    /// exactly as a visible one does.
    @Test("A covered root leaves no lattice on the scheduler")
    func coveredSchedulerRootLeavesNoLattice() {
        let harness = RenderLoopHarness()
        let scheduler = AnimationScheduler()
        _ = harness.loop(CoveredSchedulerRootApp()).render(animationScheduler: scheduler)

        #expect(harness.terminal.allOutput.contains("detail"), "the pushed screen is showing")
        #expect(!harness.terminal.allOutput.contains("spin"), "and the root is not")
        #expect(scheduler.isIdle, "nothing invisible is holding the loop awake")
    }

    /// The guard on the blast radius. `.dimmed()` isolates its content with the
    /// SAME helper the covered root uses — and then draws it. So does the page
    /// under a modal or an alert, and a context menu's backdrop. Denying the
    /// demand inside `isolatedForBackground()` would have frozen every one of
    /// them: a dimmed page is inert, not invisible.
    @Test("A dimmed — but drawn — subtree keeps its clock")
    func dimmedButDrawnKeepsTheClockLive() {
        let harness = RenderLoopHarness()
        let activity = harness.loop(DimmedProbeApp()).render()

        #expect(harness.terminal.allOutput.contains("tick"), "it is on screen, dimmed")
        #expect(activity.usesPulse)
    }

    /// The control: the same stack with an ordinary root reads no phase, so
    /// the flag above is the covered root's and nothing else's.
    @Test("A covered ordinary root asks for nothing")
    func coveredPlainRootIsQuiet() {
        let harness = RenderLoopHarness()
        #expect(!harness.loop(CoveredPlainRootApp()).render().usesPulse)
    }

    /// The other half of the same fact, and NOT a defect: `requestAnimation`
    /// records a render SIDE EFFECT, a different counter from a volatile READ,
    /// deliberately — folding the two would spin the pulse clock whenever any
    /// scheduler-driven animation was on screen. So a page whose only
    /// animation is scheduler-driven leaves all three inputs to
    /// `App.renderFrame`'s `clockLive` clear, and the loop stops the cursor
    /// timer, zeroing it.
    ///
    /// That froze the translucent indeterminate bar and the mixed-width
    /// `Spinner` until §66 of `Opacity as composition.md` moved a declined
    /// run's frame onto `frameNowNanos`; `DeclinedRunClockTests` pins the
    /// four frames that now differ. What is pinned HERE is the standing
    /// condition that made it possible, so that the next animation to ask the
    /// scheduler for its frames meets the rule before it meets the symptom:
    /// asking the scheduler does not keep a clock running, so nothing that
    /// asks may read one.
    /// The throwaway tracker used to be set in the environment alone. The
    /// measure memo gates on its MIRROR on the render cache, which the whole pass
    /// shares, so the covered root's measures snapshotted the live tracker's
    /// counters while its volatile reads went to the throwaway: a size that
    /// depended on the clock was stored as safe. Debug builds trap on the
    /// disagreement in `measureChild`, and this app trapped on its first frame.
    /// Found by the Stress `notes` session's pushed notes.
    @Test("A covered root that measures is drawn under its own tracker, mirror and all")
    func aCoveredRootMeasuresUnderItsOwnTracker() {
        let app = HeadlessApp(CoveredScrollingRootApp(), width: 40, height: 12)
        app.frame(atNanos: 0)
        app.frame(atNanos: 16_666_667)
        #expect(app.screen.contains { $0.stripped.contains("detail") }, "the pushed screen is drawn")
    }

    @Test("A scheduler-driven animation keeps no clock running")
    func schedulerDrivenKeepsNoClock() {
        let harness = RenderLoopHarness()
        let scheduler = AnimationScheduler()
        let activity = harness.loop(SchedulerDrivenApp())
            .render(animationScheduler: scheduler)

        #expect(harness.terminal.allOutput.contains("spin"), "it is on screen")
        #expect(!activity.usesPulse)
        #expect(!activity.usesCursor)
        #expect(activity.animatedClocks.isEmpty)
    }
}
