//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContinuousHoverTests.swift
//
//  SwiftUI's onContinuousHover: the action hears `.active` with the pointer's
//  location as it comes into the view and as it moves within, and `.ended`
//  when it leaves; the location is in the view's own cells by default and the
//  terminal's under `.global`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// What the hover actions under test saw, in order.
private final class PhaseLog: @unchecked Sendable {
    var phases: [HoverPhase] = []
}

/// "0123" on the top row; on the second, "ab" and then the hovered "XYZ",
/// which therefore spans columns 2…4 of row 1.
@MainActor
private func page(_ space: CoordinateSpace, _ log: PhaseLog) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        Text("0123")
        HStack(spacing: 0) {
            Text("ab")
            Text("XYZ").onContinuousHover(coordinateSpace: space) { log.phases.append($0) }
        }
    }
}

@MainActor
@Suite("SwiftUI's onContinuousHover")
struct ContinuousHoverTests {
    @Test("The pointer coming in and moving is active, at its cell in the view; leaving is ended")
    func localPhases() {
        let log = PhaseLog()
        let harness = InputChainHarness()
        harness.hover([(x: 1, y: 0), (x: 2, y: 1), (x: 4, y: 1), (x: 0, y: 1)]) { page(.local, log) }
        #expect(log.phases == [.active(CellPoint(x: 0, y: 0)), .active(CellPoint(x: 2, y: 0)), .ended])
    }

    @Test("Under .global the location is the terminal's cell")
    func globalPhases() {
        let log = PhaseLog()
        let harness = InputChainHarness()
        harness.hover([(x: 3, y: 1), (x: 4, y: 1), (x: 9, y: 5)]) { page(.global, log) }
        #expect(log.phases == [.active(CellPoint(x: 3, y: 1)), .active(CellPoint(x: 4, y: 1)), .ended])
    }

    @Test("A view inside .disabled(true) hears nothing")
    func disabledHearsNothing() {
        let log = PhaseLog()
        let harness = InputChainHarness()
        harness.hover([(x: 3, y: 1), (x: 9, y: 5)]) { page(.local, log).disabled(true) }
        #expect(log.phases.isEmpty)
    }
}
