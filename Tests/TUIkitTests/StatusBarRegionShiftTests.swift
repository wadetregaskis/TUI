//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StatusBarRegionShiftTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation

/// Drives the probe header's height from outside the app: `App` requires a bare
/// `init()`, so it cannot carry test state itself. Same trick as
/// `RenderPassScopeTests.ProbeState`, whose own copy is `private` to that file.
private final class HeaderLines: @unchecked Sendable {
    static let shared = HeaderLines()
    var count = 1
}

private struct ShiftProbeApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("content")
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        VStack(spacing: 0) {
                            ForEach(0..<HeaderLines.shared.count, id: \.self) { i in
                                Text("header \(i)")
                            }
                        }
                    }
                    ToolbarItem(placement: .bottomBar) { StatusBar() }
                }
        }
        // Compact bars: the bottom one is one row, its items at local y = 0.
        .windowToolbarStyle(.unifiedCompact)
    }
}

@MainActor
@Suite("Status-bar hit regions follow the drawn header height", .serialized)
struct StatusBarRegionShiftTests {

    /// A one-row bar whose item regions sit at local y = 0, so the screen row a
    /// click on the bar arrives on is exactly the bar's row — no bar chrome to
    /// add. System items off so the only clickable thing in the bar is the probe
    /// item.
    private func makeHarness(itemFired: @escaping () -> Void) -> RenderLoopHarness {
        let harness = RenderLoopHarness()
        harness.statusBar.showSystemItems = false
        harness.statusBar.setItems([
            StatusBarItem(shortcut: "x", label: "run", action: itemFired)
        ])
        return harness
    }

    /// The screen row (0-based, as the pointer reports it) the bar is drawn on:
    /// the last row of the screen, whatever the header's height, since a click
    /// arrives in the frame's coordinates untranslated.
    private func barRow(_ harness: RenderLoopHarness) -> Int {
        harness.terminal.size.height - 1
    }

    /// Presses and releases at every column of one content row — a click is a
    /// press AND a release (an unpaired release is deliberately not routed),
    /// and sweeping the row avoids depending on where `.justified` alignment
    /// happens to place the item.
    private func clickRow(_ harness: RenderLoopHarness, y: Int) {
        let dispatcher = harness.tuiContext.mouseEventDispatcher
        for x in 0..<harness.terminal.size.width {
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))
        }
    }

    @Test("A frame whose header grew still routes a click on the status bar")
    func statusBarStaysClickableAfterHeaderGrows() {
        HeaderLines.shared.count = 1
        var fired = 0
        let harness = makeHarness { fired += 1 }
        let loop = harness.loop(ShiftProbeApp())

        _ = loop.render()  // frame 1: measure walk + draw
        _ = loop.render()  // frame 2: estimate == actual

        // Sanity, so the test fails loudly rather than passing vacuously if the
        // bar ever stops emitting regions at all.
        #expect(barRow(harness) == 23)
        clickRow(harness, y: barRow(harness))
        #expect(fired >= 1, "pre-condition: the bar is clickable on a steady frame")

        // Grow the header by one line. The frame lays out against the previous
        // height (3) and re-renders at the real one (4).
        HeaderLines.shared.count = 2
        let headerBefore = loop.windowChrome.rows(.top)
        _ = loop.render()
        #expect(
            loop.windowChrome.rows(.top) == headerBefore + 1,
            "pre-condition: the header must change height, or nothing is under test")
        #expect(barRow(harness) == 23)

        fired = 0
        clickRow(harness, y: barRow(harness))
        #expect(fired >= 1, "a click on the bar's row must reach the item after the header grew")
    }

    @Test("A frame whose header shrank does not park status-bar regions on a content row")
    func statusBarRegionsLeaveContentRowsAloneAfterHeaderShrinks() {
        HeaderLines.shared.count = 3
        var fired = 0
        let harness = makeHarness { fired += 1 }
        let loop = harness.loop(ShiftProbeApp())

        _ = loop.render()
        _ = loop.render()
        #expect(barRow(harness) == 23)

        HeaderLines.shared.count = 1
        let headerBefore = loop.windowChrome.rows(.top)
        _ = loop.render()
        #expect(
            loop.windowChrome.rows(.top) == headerBefore - 2,
            "pre-condition: the header must shrink by two rows")

        let row = barRow(harness)
        #expect(row == 23)

        // A stale estimate once put the regions two rows up — a real page row
        // above the bar. `matchingRegions` searches reversed and the status-bar
        // regions are appended last, so they would beat the page's own control.
        fired = 0
        clickRow(harness, y: row - 2)
        #expect(fired == 0, "a click on a page row must not reach a status-bar item")

        fired = 0
        clickRow(harness, y: row)
        #expect(fired >= 1, "a click on the bar's own row must reach the item")
    }
}
