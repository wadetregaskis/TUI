//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarVisibilityTests.swift
//
//  `.toolbarVisibility(_:for:)` takes a window bar away — a frame later, as
//  any change to the bars is adopted — and the keys of a hidden line of hints
//  still work.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// Which bars the probe hides, reachable from an `App`.
private final class HiddenBars: @unchecked Sendable {
    static let shared = HiddenBars()
    var top: Visibility = .automatic
    var bottom: Visibility = .automatic
    var innerTop: Visibility = .automatic
    var fired = 0
}

/// A page with a top bar and a bottom bar of key hints, each bar's visibility
/// stated from outside — and the top bar's again, closer to the content.
private struct VisibilityApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("PAGE")
                .toolbarVisibility(HiddenBars.shared.innerTop, for: .windowToolbar)
                .statusBarItems {
                    StatusBarItem(shortcut: "x", label: "act") { HiddenBars.shared.fired += 1 }
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { Text("TOP-ITEM") }
                    ToolbarItem(placement: .bottomBar) { StatusBar() }
                }
                .toolbarVisibility(HiddenBars.shared.top, for: .windowToolbar)
                .toolbarVisibility(HiddenBars.shared.bottom, for: .bottomBar)
        }
    }
}

@MainActor
@Suite("Toolbar visibility", .serialized)
struct ToolbarVisibilityTests {

    private func reset() {
        HiddenBars.shared.top = .automatic
        HiddenBars.shared.bottom = .automatic
        HiddenBars.shared.innerTop = .automatic
        HiddenBars.shared.fired = 0
    }

    /// The screen two frames in: one to declare, one to draw.
    private func screen(_ harness: RenderLoopHarness, _ loop: RenderLoop<VisibilityApp>) -> [String] {
        _ = loop.render()
        _ = loop.render()
        return loop.diffWriter.shownLines.map(\.stripped)
    }

    @Test("Hiding the window toolbar takes the top bar away, and only it")
    func hidesTheTopBar() {
        reset()
        HiddenBars.shared.top = .hidden
        let harness = RenderLoopHarness()
        let loop = harness.loop(VisibilityApp())
        let rows = screen(harness, loop)
        #expect(!rows.contains { $0.contains("TOP-ITEM") }, "\(rows)")
        #expect(rows.contains { $0.contains("x act") }, "the bottom bar stays: \(rows)")
        #expect(loop.windowChrome.rows(.top) == 0)
    }

    @Test("Hiding the bottom bar hides the line of hints, and its keys still work")
    func hidesTheBottomBar() {
        reset()
        HiddenBars.shared.bottom = .hidden
        let harness = RenderLoopHarness()
        let loop = harness.loop(VisibilityApp())
        let rows = screen(harness, loop)
        #expect(rows.contains { $0.contains("TOP-ITEM") }, "\(rows)")
        #expect(!rows.contains { $0.contains("act") || $0.contains("quit") }, "\(rows)")
        #expect(loop.windowChrome.rows(.bottom) == 0)
        #expect(harness.statusBar.handleKeyEvent(KeyEvent(key: .character("x"))))
        #expect(HiddenBars.shared.fired == 1, "the item's key works with its line hidden")
    }

    @Test("The statement closest to the content wins")
    func innermostWins() {
        reset()
        HiddenBars.shared.top = .hidden
        HiddenBars.shared.innerTop = .visible
        let harness = RenderLoopHarness()
        let rows = screen(harness, harness.loop(VisibilityApp()))
        #expect(rows.contains { $0.contains("TOP-ITEM") }, "\(rows)")
    }

    @Test("A bar hidden after it was drawn goes the frame after")
    func hidingIsAdoptedAFrameLater() {
        reset()
        let harness = RenderLoopHarness()
        let loop = harness.loop(VisibilityApp())
        _ = screen(harness, loop)
        #expect(loop.windowChrome.rows(.top) == 1)
        HiddenBars.shared.top = .hidden
        _ = loop.render()
        #expect(loop.windowChrome.rows(.top) == 0, "adopted for the next frame")
        _ = loop.render()
        let rows = loop.diffWriter.shownLines.map(\.stripped)
        #expect(!rows.contains { $0.contains("TOP-ITEM") }, "\(rows)")
    }
}
