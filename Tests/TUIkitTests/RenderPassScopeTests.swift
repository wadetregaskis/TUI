//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderPassScopeTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitView

// MARK: - Why these tests exist
//
// `RenderLoop.renderContent` walks the scene tree TWICE inside the first frame's
// `beginRenderPass()`/`endRenderPass()` bracket: a throwaway walk to find the
// chrome the content declares, then the drawn one. (It used to be any frame too:
// a correction re-render ran wherever the header's actual height disagreed with
// the estimate the frame was laid out against.) Only the last walk's buffer is
// drawn.
//
// The per-frame registries used to be reset once per PASS, so the discarded
// walk's registrations piled up on top of the drawn walk's. Nothing on either
// side of the loop could see it: `OnChangeModifier` is correct in isolation, and
// so is `KeyEventDispatcher` — the bug lived in how many times the loop ran them.
// These tests drive a whole render pass against a `MockTerminal` so that
// re-introducing it costs a failing test.

/// Counters the probe apps bump, reachable from an `App` — which the protocol
/// requires to be constructible with a bare `init()`, so it cannot carry them.
/// Test-only; the suite is `.serialized` and every test resets it first.
private final class ProbeState: @unchecked Sendable {
    static let shared = ProbeState()

    var onChangeFires = 0
    var keyTaps = 0
    /// Drives the header's height, so a test can make it change between frames.
    var headerLines = 1

    /// `isMeasuring` as seen by each walk of the scene, in order.
    var walkPhases: [Bool] = []
    /// How many walks had begun when `.onAppear` fired, or `nil` if it never did.
    var appearedDuringWalk: Int?

    func reset() {
        onChangeFires = 0
        keyTaps = 0
        headerLines = 1
        walkPhases = []
        appearedDuringWalk = nil
    }
}

/// Registers a declining key handler and an initial `.onChange`, under a header
/// whose height `ProbeState.headerLines` controls.
private struct ProbeApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("content")
                .toolbar { ToolbarItem(placement: .navigation) { ProbeHeader() } }
                .onChange(of: 1, initial: true) { _, _ in
                    ProbeState.shared.onChangeFires += 1
                }
                // Declines the key, like the blessed log-the-key pattern: dispatch
                // then walks EVERY registered handler, so a duplicate registration
                // shows up as a doubled side effect.
                .onKeyEvent { _ in
                    ProbeState.shared.keyTaps += 1
                    return false
                }
        }
    }
}

/// Records the phase of every walk, and when `.onAppear` fired relative to them.
private struct PhaseProbeApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                WalkPhaseProbe()
                Text("content")
                    .onAppear {
                        ProbeState.shared.appearedDuringWalk = ProbeState.shared.walkPhases.count
                    }
            }
            .toolbar { ToolbarItem(placement: .navigation) { ProbeHeader() } }
        }
    }
}

/// A leaf that records `context.isMeasuring` each time it is walked. Renderable
/// rather than composed, because the phase is only visible from a `RenderContext`.
private struct WalkPhaseProbe: View, Renderable {
    var body: Never { fatalError("WalkPhaseProbe renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        ProbeState.shared.walkPhases.append(context.isMeasuring)
        return FrameBuffer(lines: [""])
    }
}

private struct ProbeHeader: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<ProbeState.shared.headerLines, id: \.self) { i in
                Text("header \(i)")
            }
        }
    }
}

@MainActor
@Suite("Render-pass scope: one walk's worth of registrations", .serialized)
struct RenderPassScopeTests {

    /// The first frame always walks the scene twice — once to discover the header
    /// height, once for real. Both walks used to register into the same tables.
    @Test("The first frame registers one walk's worth of handlers and fires onChange once")
    func firstFrameRegistersOnce() {
        ProbeState.shared.reset()
        let harness = RenderLoopHarness()
        let loop = harness.loop(ProbeApp())

        _ = loop.render()

        #expect(
            ProbeState.shared.onChangeFires == 1,
            "the discarded walk must not re-fire the initial action")
        #expect(
            harness.tuiContext.keyEventDispatcher.handlerCount == 1,
            "only the drawn walk's key handler should be registered")

        // A declining handler runs for every registration dispatch walks past, so
        // this is the user-visible half: one keypress, one side effect.
        _ = harness.tuiContext.keyEventDispatcher.dispatch(KeyEvent(key: .character("x")))
        #expect(ProbeState.shared.keyTaps == 1, "one keypress must run a declining handler once")
    }

    /// The second half: a header whose height CHANGES used to send a later
    /// frame through a correction re-render, which walked the tree a second
    /// time. That walk is gone (the chrome adopts the change a frame later), and
    /// this keeps the frame's registrations single whichever way it is reached.
    @Test("A frame whose header changes height registers once")
    func correctedFrameRegistersOnce() {
        ProbeState.shared.reset()
        let harness = RenderLoopHarness()
        let loop = harness.loop(ProbeApp())

        _ = loop.render()
        let heightAfterFirstFrame = loop.windowChrome.rows(.top)

        // Grow the header. Frame 2 lays out against the previous height and
        // adopts the new one for frame 3.
        ProbeState.shared.headerLines = 3
        _ = loop.render()

        // Pre-condition, so this test fails loudly rather than silently ceasing to
        // discriminate if the correction branch stops being reached.
        #expect(
            loop.windowChrome.rows(.top) != heightAfterFirstFrame,
            "the header must actually change height, or nothing is under test")

        #expect(
            harness.tuiContext.keyEventDispatcher.handlerCount == 1,
            "the frame must register one walk's handler")

        let tapsBefore = ProbeState.shared.keyTaps
        _ = harness.tuiContext.keyEventDispatcher.dispatch(KeyEvent(key: .character("x")))
        #expect(ProbeState.shared.keyTaps == tapsBefore + 1, "one keypress, one side effect")
    }

    /// The registration half of the throwaway walk was fixed by resetting the
    /// per-frame registries per WALK. The lifecycle half was not: the walk still
    /// ran with `isMeasuring == false`, so every guard written as
    /// `!context.isMeasuring` — `onAppear`, `.task`, `onChange`, focus and mouse
    /// registration — treated a walk whose buffer is thrown away as a real
    /// render.
    ///
    /// Counting fires cannot catch that: `recordAppear` is idempotent, so
    /// `onAppear` still fires exactly once either way. What differs is *which*
    /// walk it fires in — and that matters because the two walks see different
    /// heights (the throwaway one has not subtracted the header yet), so a tree
    /// that branches on available space can contain a view in the first walk and
    /// not the second. That view would appear, mount a `.task`, and then be told
    /// it disappeared, having never been drawn.
    @Test("The first-frame header measurement is a measure pass")
    func firstFrameMeasurementWalkIsMarkedMeasuring() {
        ProbeState.shared.reset()
        let harness = RenderLoopHarness()
        let loop = harness.loop(PhaseProbeApp())

        _ = loop.render()

        // Deliberately not asserting an exact sequence: two-pass layout means a
        // leaf is walked more than once per walk of the SCENE, and pinning that
        // count would fail on any layout change without a defect. The contract
        // is only about the last one.
        let phases = ProbeState.shared.walkPhases
        #expect(!phases.isEmpty)
        #expect(
            phases.last == false,
            "the drawn walk is a render pass")
        #expect(
            phases.dropLast().allSatisfy { $0 },
            "every walk before the drawn one is a measurement. Saw \(phases)")
        // `appearedDuringWalk` is how many walks had been recorded when the
        // effect ran; the probe is the drawn walk's first child, so a fire in
        // that walk lands after every recording. Anything less means it fired
        // in a walk that was thrown away — it was 2 of 4 before this was fixed.
        #expect(
            ProbeState.shared.appearedDuringWalk == phases.count,
            "onAppear belongs to the drawn walk, not a discarded one")
    }

    /// The leak on the OTHER multi-walk path, closed.
    ///
    /// Frame 1's extra walk is known to be throwaway *before* it runs, so it is
    /// simply marked as a measurement. A header-height correction could not be:
    /// the loop rendered at the estimated height, discovered afterwards that the
    /// real height differed, and only then re-rendered — so the first, discarded
    /// walk ran every effect as a render. It was pinned here as a known gap,
    /// waiting on effects staged per walk (upstream's PR #60/#61).
    ///
    /// The window's chrome now adopts a changed height a frame LATER instead
    /// (`WindowChromeState`): the frame that sees the change is drawn at the old
    /// reservation, so there is no second walk to discard.
    @Test("A frame whose header changes height is one walk, and it is drawn")
    func headerChangeIsOneDrawnWalk() {
        ProbeState.shared.reset()
        let harness = RenderLoopHarness()
        let loop = harness.loop(PhaseProbeApp())

        _ = loop.render()
        let heightAfterFirstFrame = loop.windowChrome.rows(.top)

        ProbeState.shared.headerLines = 3
        ProbeState.shared.walkPhases = []
        _ = loop.render()

        #expect(
            loop.windowChrome.rows(.top) != heightAfterFirstFrame,
            "the header must actually change height, or nothing is under test")
        let phases = ProbeState.shared.walkPhases
        #expect(phases.filter { !$0 }.count == 1, "one drawn walk. Saw \(phases)")
        #expect(
            phases.dropLast().allSatisfy { $0 },
            "nothing before the drawn walk renders. Saw \(phases)")
    }
}
