//  🖥️ TUI — A Terminal UI framework for Swift
//  DropDestinationIsEnabledTests.swift
//
//  SwiftUI's dropDestination(for:isEnabled:action:): a drop is taken while
//  the view is enabled for drops, and the action hears the values and where
//  they landed; while it is not, the view is no destination and the drag
//  goes home. The 2026-08 audit (#115) found the isEnabled: spelling absent.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// What the destination under test was handed.
private final class Dropped: @unchecked Sendable {
    var entries: [String] = []
}

@MainActor
@Suite("SwiftUI's dropDestination(for:isEnabled:action:)")
struct DropDestinationIsEnabledTests {
    /// A chip on row 0 and a drop zone on row 4.
    private func tree(_ dropped: Dropped, enabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CHIP").draggable("apple")
            Text("").frame(height: 3)
            Text("ZONE========")
                .dropDestination(for: String.self, isEnabled: enabled) { titles, info in
                    dropped.entries.append("\(titles) at \(info.location.x),\(info.location.y)")
                }
        }
    }

    /// Carries the chip from row 0 onto the zone at (3, 4) and lets go.
    private func carry(_ harness: InputChainHarness, _ build: () -> some View) {
        harness.frame(build())
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 2, y: 2))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 3, y: 4))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 3, y: 4))
    }

    @Test("Enabled, the drop is taken, with its location in the zone")
    func enabledTakesTheDrop() {
        let dropped = Dropped()
        let harness = InputChainHarness(width: 30, height: 8)
        carry(harness) { tree(dropped, enabled: true) }
        #expect(dropped.entries == ["[\"apple\"] at 3,0"])
        #expect(harness.tui.dragAndDropSession.returnFlight == nil, "a drop that landed does not fly home")
    }

    @Test("Disabled, the view is no destination and the drag goes home")
    func disabledIsNoDestination() {
        let dropped = Dropped()
        let harness = InputChainHarness(width: 30, height: 8)
        carry(harness) { tree(dropped, enabled: false) }
        #expect(dropped.entries.isEmpty)
        #expect(harness.tui.dragAndDropSession.returnFlight != nil, "the refused drag flies home")
    }
}
