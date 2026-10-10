//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderLoopRegionMergeTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitChrome
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

// MARK: - Why these tests exist
//
// The bug fixed in commit e5382a77 (status-bar items unclickable) and
// the related bug fixed in 714d3577 (app-header content
// likewise unclickable) both lived between unit-tested layers:
//
//   - `StatusBar.applyHitTestRegions` was unit-tested in isolation
//     and emitted regions correctly.
//   - `MouseEventDispatcher.dispatch` was unit-tested in isolation
//     and routed events correctly.
//   - The bar renderers sat between them (then the run loop's own,
//     now the scene's chrome host and `_ChromeBarFrame`), and each
//     silently discarded the hit-test regions before they could reach
//     the dispatcher's `setRegions` call.
//
// The shared pattern: a separately-rendered FrameBuffer's
// `hitTestRegions` get dropped on the floor before they reach
// `setRegions`. The unit tests on either side don't catch it because
// the dropped step happens between them. These integration tests
// exercise the full path so that re-introducing the bug requires a
// test failure to land alongside it.
@MainActor
@Suite("RenderLoop region merge integration", .serialized)
struct RenderLoopRegionMergeTests {

    private func makeContext(width: Int = 80, height: Int = 24) -> RenderContext {
        let tuiContext = TUIContext()
        var environment = EnvironmentValues()
        // A status bar of this frame's own: the environment no longer
        // hands out a shared instance, which is what let a parallel
        // neighbour's items be read back as this test's.
        environment.statusBar = StatusBarState()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tuiContext)
        return RenderContext(
            availableWidth: width,
            availableHeight: height,
            environment: environment,
            tuiContext: tuiContext
        )
    }

    // MARK: - A bar's frame

    /// Regression for the header-frame half of commit 714d3577.
    /// Before the fix, the wrap-and-divider step constructed
    /// `FrameBuffer(lines:)` from the contentBuffer's lines, which
    /// leaves `hitTestRegions` empty by default — silently dropping
    /// anything the bar's content emitted.
    @Test("A bar's frame preserves its content buffer's hit-test regions")
    func barFramePreservesContentBufferRegions() {
        // Build a content buffer with a synthetic region so we
        // don't depend on any particular control's rendering
        // details — the test is about whether the wrap-and-
        // divider step preserves whatever the content carried.
        var contentBuffer = FrameBuffer(lines: ["title-bar content"])
        let marker = HitTestRegion.HandlerID(99)
        contentBuffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0,
                offsetY: 0,
                width: contentBuffer.width,
                height: 1,
                handlerID: marker
            )
        )

        let header = _ChromeBarFrame(contentBuffer: contentBuffer, style: .rule)
        let rendered = renderToBuffer(header, context: makeContext(width: 40))

        #expect(rendered.hitTestRegions.contains(where: { $0.handlerID == marker }),
                "_ChromeBarFrame.renderToBuffer must carry contentBuffer's regions through")
    }

    // MARK: - StatusBar

    /// Sanity check that a rendered StatusBar carries the
    /// hit-test regions ``StatusBar/applyHitTestRegions``
    /// emits. This doesn't replicate the bug class on its own
    /// — that bug was in RenderLoop, not in this render step
    /// — but it pins the contract the merge-logic test below
    /// depends on.
    @Test("StatusBar render emits hit-test regions for clickable items")
    func statusBarRendersWithRegions() {
        var fired = false
        let item = StatusBarItem(
            shortcut: "x",
            label: "Run",
            action: { fired = true }
        )
        let bar = StatusBar(
            userItems: [item],
            systemItems: [],
            style: .compact,
            alignment: .leading,
            highlightColor: .cyan,
            labelColor: .white
        )

        let context = makeContext(width: 40, height: bar.height)
        let buffer = renderToBuffer(bar, context: context)

        #expect(!buffer.hitTestRegions.isEmpty,
                "Clickable StatusBarItem must emit at least one hit-test region")

        // Pin the action-fired side too so a future refactor
        // that drops the click → execute path also fails here.
        // We invoke the registered handler directly because
        // there's no dispatcher in this scope to drive a real
        // click; the merge-logic test below exercises a real
        // dispatch.
        item.execute()
        #expect(fired, "Item's action must be invocable")
    }

    // MARK: - End-to-end

    /// The regression test for the bug class, end to end: a page, a top bar
    /// and a bottom bar of key hints, each holding something clickable, drawn
    /// by the run loop into one frame; a click on each row of the SCREEN —
    /// where a pointer reports it, untranslated — must reach that one's
    /// handler and no other. Before the e5382a77 / 714d3577 fixes the header's
    /// and the status bar's handlers were never reached; before the chrome
    /// moved into the scene, their regions were shifted by hand to meet
    /// translated pointer rows.
    @Test("A click on the page, the top bar or the bottom bar reaches that one's control")
    func clicksReachEachBar() throws {
        RegionMergeProbe.shared.fired = []
        let harness = RenderLoopHarness()
        harness.terminal.size = (40, 12)
        let loop = harness.loop(RegionMergeProbeApp())
        _ = loop.render()
        _ = loop.render()
        let screen = loop.diffWriter.shownLines.map(\.stripped)
        let dispatcher = harness.tuiContext.mouseEventDispatcher
        func click(_ label: String) throws {
            let row = try #require(screen.firstIndex { $0.contains(label) }, "\(label) on \(screen)")
            let column = screen[row].distance(
                from: screen[row].startIndex, to: try #require(screen[row].range(of: label)).lowerBound)
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: column, y: row))
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: column, y: row))
        }
        try click("PAGE")
        try click("TOP")
        try click("run")
        #expect(RegionMergeProbe.shared.fired == ["page", "top", "status"])
    }

    // MARK: - StatusBarItem identity stability

    /// Regression for #37 — the hover underline that
    /// disappeared after a click that didn't change the page.
    /// The bug was that `StatusBarItem.id` was
    /// `"\(shortcut)-\(label)"`, so an item whose action
    /// mutated its own label ended up with a new id on the
    /// next render — and the hover state machine, which
    /// stores `hoveredItemID` and compares it against
    /// `item.id` per render, lost the match.
    @Test("StatusBarItem identity is stable across label changes")
    func statusBarItemIdentityIsStable() {
        let staticID = StatusBarItem(
            shortcut: "x", label: "X: A", action: {}
        ).id
        let mutatedLabelID = StatusBarItem(
            shortcut: "x", label: "X: B (next state)", action: {}
        ).id
        #expect(staticID == mutatedLabelID,
                "Items sharing a shortcut must share an id regardless of label changes")
    }

    // MARK: - Action-less item clickability

    /// Regression for #36 — system items like "Back" (esc),
    /// "Quit" (q), and "Show" (enter) declare a `triggerKey`
    /// but no `action`. They were silently filtered out of
    /// the click / hover path because the guard in
    /// `applyHitTestRegions` skipped items whose
    /// `hasAction` was false. They should still be clickable
    /// — their click synthesises the corresponding key event
    /// through the full InputHandler chain.
    @Test("Action-less StatusBarItem with triggerKey gets a hit-test region")
    func actionLessItemWithTriggerKeyGetsRegion() {
        // The "Back" pattern — Shortcut.escape resolves to
        // .escape; no action argument.
        let backItem = StatusBarItem(shortcut: "esc", label: "back")
        let bar = StatusBar(
            userItems: [backItem],
            systemItems: [],
            style: .compact,
            alignment: .leading,
            highlightColor: .cyan,
            labelColor: .white
        )

        let context = makeContext(width: 40, height: bar.height)
        let buffer = renderToBuffer(bar, context: context)

        #expect(!buffer.hitTestRegions.isEmpty,
                "Action-less StatusBarItem with a triggerKey must still emit a hit-test region")
        #expect(backItem.triggerKey != nil,
                "Pre-condition: the 'esc' shortcut must derive a triggerKey for the regression to be meaningful")
    }

    /// Companion to the above — a click on an action-less
    /// item with a triggerKey routes a synthesised key event
    /// through the environment's `synthesizeKeyEvent` closure
    /// (which AppRunner wires to InputHandler.handle).
    @Test("Click on action-less StatusBarItem fires synthesizeKeyEvent")
    func clickOnActionLessItemFiresSynthesizeKey() {
        var synthesisedKey: KeyEvent?
        var environment = EnvironmentValues()
        // A status bar of this frame's own: the environment no longer
        // hands out a shared instance, which is what let a parallel
        // neighbour's items be read back as this test's.
        environment.statusBar = StatusBarState()
        let tuiContext = TUIContext()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tuiContext)
        // Inject a synthesis recorder so the test can observe
        // which key the click produced.
        environment.synthesizeKeyEvent = { event in
            synthesisedKey = event
        }
        let context = RenderContext(
            availableWidth: 40,
            availableHeight: 1,
            environment: environment,
            tuiContext: tuiContext
        )
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)

        let backItem = StatusBarItem(shortcut: "esc", label: "back")
        let bar = StatusBar(
            userItems: [backItem],
            systemItems: [],
            style: .compact,
            alignment: .leading,
            highlightColor: .cyan,
            labelColor: .white
        )

        let buffer = renderToBuffer(bar, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)

        guard let region = buffer.hitTestRegions.first else {
            Issue.record("Pre-condition: rendered bar must have at least one region")
            return
        }

        // Press and release: an unpaired release is not routed at all.
        for phase in [MousePhase.pressed, .released] {
            _ = dispatcher.dispatch(MouseEvent(
                button: .left, phase: phase,
                x: region.offsetX + 1, y: region.offsetY
            ))
        }

        #expect(synthesisedKey?.key == .escape,
                "Click on the 'back' item must synthesise an ESC KeyEvent through the environment closure")
    }
}

/// What the region-merge probe's controls did.
private final class RegionMergeProbe: @unchecked Sendable {
    static let shared = RegionMergeProbe()
    var fired: [String] = []
}

/// A page button, a top-bar button, and a bottom bar of key hints with an
/// item that names a key of its own.
private struct RegionMergeProbeApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Button("PAGE") { RegionMergeProbe.shared.fired.append("page") }
                .statusBarItems {
                    StatusBarItem(shortcut: "x", label: "run") { RegionMergeProbe.shared.fired.append("status") }
                }
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button("TOP") { RegionMergeProbe.shared.fired.append("top") }
                    }
                    ToolbarItem(placement: .bottomBar) { StatusBar() }
                }
        }
    }
}
