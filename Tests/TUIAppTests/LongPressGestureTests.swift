//  🖥️ TUI — A Terminal UI framework for Swift
//  LongPressGestureTests.swift
//
//  SwiftUI's onLongPressGesture: the left button held on the view for the
//  minimum duration runs the action; onPressingChanged hears true on the
//  press and false when it ends — on success (just before the action, the
//  order macOS 15.8 uses), on an early release, or on a drag past the maximum
//  distance, neither of which then runs the action. The frames are driven on
//  the harness's own clock, so nothing waits on real time.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// What the gesture under test reported, in order.
private final class GestureLog: @unchecked Sendable {
    var entries: [String] = []
}

private let millisecond: Int64 = 1_000_000

@MainActor
@Suite("SwiftUI's onLongPressGesture")
struct LongPressGestureTests {
    /// "XYZ" at the top-left, holding the gesture under test.
    private func view(_ log: GestureLog, maximumDistance: Int = 1) -> some View {
        Text("XYZ")
            .onLongPressGesture(minimumDuration: 0.5, maximumDistance: maximumDistance) {
                log.entries.append("perform")
            } onPressingChanged: { pressing in
                log.entries.append("pressing \(pressing)")
            }
    }

    private func mouse(_ harness: InputChainHarness, _ phase: MousePhase, _ x: Int, _ y: Int) {
        harness.mouse(MouseEvent(button: .left, phase: phase, x: x, y: y))
    }

    @Test("Held for the minimum duration, the press runs the action, then ends")
    func heldLongEnough() {
        let log = GestureLog()
        let harness = InputChainHarness()
        harness.frame(view(log))
        mouse(harness, .pressed, 1, 0)
        harness.frame(view(log))  // the clock starts: the deadline is 500 ms on
        harness.now = 499 * millisecond
        harness.frame(view(log))
        #expect(log.entries == ["pressing true"])
        harness.now = 500 * millisecond
        harness.frame(view(log))
        #expect(log.entries == ["pressing true", "pressing false", "perform"])
        mouse(harness, .released, 1, 0)
        harness.frame(view(log))
        #expect(log.entries == ["pressing true", "pressing false", "perform"], "the release adds nothing")
    }

    @Test("Released early, the press ends without the action")
    func releasedEarly() {
        let log = GestureLog()
        let harness = InputChainHarness()
        harness.frame(view(log))
        mouse(harness, .pressed, 1, 0)
        harness.frame(view(log))
        harness.now = 200 * millisecond
        mouse(harness, .released, 1, 0)
        harness.frame(view(log))
        harness.now = 900 * millisecond
        harness.frame(view(log))
        #expect(log.entries == ["pressing true", "pressing false"])
    }

    @Test("A drag past the maximum distance ends the press; one within it does not")
    func dragDistance() {
        for (distance, expected) in [(1, ["pressing true", "pressing false", "perform"]), (0, ["pressing true", "pressing false"])] {
            let log = GestureLog()
            let harness = InputChainHarness()
            harness.frame(view(log, maximumDistance: distance))
            mouse(harness, .pressed, 1, 0)
            harness.frame(view(log, maximumDistance: distance))
            mouse(harness, .dragged, 2, 0)
            harness.now = 600 * millisecond
            harness.frame(view(log, maximumDistance: distance))
            #expect(log.entries == expected, "maximumDistance \(distance)")
        }
    }

    /// A memo above an idle gesture stores it — so the press itself has to
    /// drop what was cached, or the frame that starts the clock is served
    /// and the deadline is never set.
    @Test("A press inside a memoized subtree still reaches its deadline")
    func insideAMemo() {
        let log = GestureLog()
        let harness = InputChainHarness()
        let page = { VStack { PressLeaf(log: log).equatable() } }
        harness.frame(page())
        harness.frame(page())
        harness.frame(page())
        #expect(harness.tui.renderCache.rowWork.served >= 1, "the idle leaf was served from the memo")
        mouse(harness, .pressed, 1, 0)
        harness.frame(page())
        harness.now = 500 * millisecond
        harness.frame(page())
        #expect(log.entries == ["perform"])
    }

    @Test("A view inside .disabled(true) takes no press")
    func disabled() {
        let log = GestureLog()
        let harness = InputChainHarness()
        harness.frame(view(log).disabled(true))
        mouse(harness, .pressed, 1, 0)
        harness.now = 600 * millisecond
        harness.frame(view(log).disabled(true))
        #expect(log.entries.isEmpty)
    }
}

/// A long-press leaf behind an `.equatable()` boundary, equal to any other with
/// the same log.
private struct PressLeaf: View, @MainActor Equatable {
    let log: GestureLog

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.log === rhs.log }

    var body: some View {
        Text("XYZ").onLongPressGesture(minimumDuration: 0.5) { [log] in log.entries.append("perform") }
    }
}
