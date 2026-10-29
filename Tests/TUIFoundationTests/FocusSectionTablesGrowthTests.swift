//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusSectionTablesGrowthTests.swift
//
//  The focus manager remembers, per section, the control that held the focus
//  there and the section to go back to when it is dismissed. Both tables are
//  keyed by section id and were emptied only by `clear()` (and a revert target
//  by its own dismissal), so sections that came and went — one per row of
//  churning data — were remembered for the life of the app.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Focus section tables stay bounded")
struct FocusSectionTablesGrowthTests {

    private func tableSize(_ manager: FocusManager) -> Int {
        manager.sectionFocusMemory.count + manager.sectionRevertTarget.count
    }

    @Test("Tab cycling through sections that come and go keeps a bounded memory")
    func churningSectionsStayBounded() {
        let manager = FocusManager()
        let page = MockFocusable(id: "page-control")
        for frame in 0..<500 {
            // One section per frame, new each time, the focus Tabbed into it.
            let section = "row-\(frame)"
            manager.beginRenderPass()
            manager.register(page)
            manager.registerSection(id: section)
            manager.register(MockFocusable(id: "control-\(frame)"), inSection: section)
            manager.activateSection(id: section, focusBoundary: .forward)
            manager.endRenderPass()
        }
        #expect(
            tableSize(manager) <= FocusManager.minimumSectionSweepThreshold * 4,
            "kept \(tableSize(manager)) entries for 500 sections")
    }

    /// A pushed navigation renders only its root and its top screen, so the
    /// screens between register no section: their memory must survive a sweep,
    /// or popping back to one lands on its first control rather than the one
    /// the user left.
    @Test("A sweep keeps the memory of the screens buried under a navigation")
    func buriedScreensKeepTheirMemory() {
        let manager = FocusManager()
        let page = MockFocusable(id: "page")
        let depth1 = (first: MockFocusable(id: "d1-first"), chosen: MockFocusable(id: "d1-chosen"))
        let depth2 = (first: MockFocusable(id: "d2-first"), chosen: MockFocusable(id: "d2-chosen"))
        let depth3 = MockFocusable(id: "d3")

        /// One frame drawing the page, and the screen on top in `section`.
        func frame(top section: String, _ controls: [MockFocusable], body: () -> Void = {}) {
            manager.beginRenderPass()
            manager.register(page)
            manager.registerSection(id: section)
            for control in controls { manager.register(control, inSection: section) }
            body()
            manager.endRenderPass()
        }

        frame(top: "d1", [depth1.first, depth1.chosen]) { manager.activateSection(id: "d1") }
        manager.focus(depth1.chosen)
        frame(top: "d2", [depth2.first, depth2.chosen]) { manager.activateSection(id: "d2") }
        manager.focus(depth2.chosen)
        frame(top: "d3", [depth3]) { manager.activateSection(id: "d3") }

        // An alert from each of a stream of rows, presented over the top
        // screen and dismissed: enough sections to sweep many times.
        for row in 0..<300 {
            let alert = "alert-\(row)"
            frame(top: "d3", [depth3]) {
                manager.registerSection(id: alert)
                manager.register(MockFocusable(id: "ok-\(row)"), inSection: alert)
                manager.activateSection(id: alert)
            }
            frame(top: "d3", [depth3]) { manager.deactivateSection(id: alert) }
        }
        #expect(tableSize(manager) < FocusManager.minimumSectionSweepThreshold * 2, "kept \(tableSize(manager))")

        // Pop to depth 2, then to depth 1: each comes back where it was left.
        frame(top: "d2", [depth2.first, depth2.chosen]) { manager.deactivateSection(id: "d3") }
        #expect(manager.currentFocusedID == "d2-chosen")
        frame(top: "d1", [depth1.first, depth1.chosen]) { manager.deactivateSection(id: "d2") }
        #expect(manager.currentFocusedID == "d1-chosen")
    }
}
