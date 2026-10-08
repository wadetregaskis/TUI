//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LongPressAndDragGestureTests.swift
//
//  SwiftUI's LongPressGesture and DragGesture as measured on macOS 15.8: a
//  long press is `true` from the press and ends at its minimum duration with
//  the button still down; a drag starts at its minimum distance, keeps the
//  press as its start, and ends on the release only if it started.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation

@MainActor
@Suite("SwiftUI's LongPressGesture and DragGesture")
struct LongPressAndDragGestureTests {
    private func box(_ gesture: some Gesture) -> some View {
        Text("").frame(width: 10, height: 3).gesture(gesture).frame(width: 40, height: 12, alignment: .topLeading)
    }

    private func makeHarness() -> InputChainHarness {
        let harness = InputChainHarness()
        harness.syncEventClock()
        return harness
    }

    // MARK: Long press

    private func longPress(_ log: GestureRecord, maximumDistance: Int = 1) -> some View {
        box(
            LongPressGesture(minimumDuration: 0.5, maximumDistance: maximumDistance)
                .onChanged { log("changed \($0)") }
                .onEnded { log("ended \($0)") })
    }

    @Test("A long press is true from the press, and ends at its minimum duration with the button down")
    func longPressHeld() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { longPress(log) }
        harness.frame(view())
        harness.pointer([(.pressed, 2, 1)], view)
        #expect(log.entries == ["changed true"])
        harness.now = 499 * gestureMillisecond
        harness.frame(view())
        #expect(log.entries == ["changed true"])
        harness.now = 500 * gestureMillisecond
        harness.frame(view())
        #expect(log.entries == ["changed true", "ended true"])
        harness.pointer([(.released, 2, 1)], view)
        #expect(log.entries == ["changed true", "ended true"], "the release adds nothing")
    }

    @Test("Released early, or moved too far, a long press fails without ending")
    func longPressFails() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { longPress(log) }
        harness.frame(view())
        harness.pointer([(.pressed, 2, 1)], view)
        harness.now = 200 * gestureMillisecond
        harness.pointer([(.released, 2, 1)], view)
        harness.now = 900 * gestureMillisecond
        harness.frame(view())
        #expect(log.entries == ["changed true"])

        for (distance, ends) in [(1, true), (0, false)] {
            let log = GestureRecord()
            let harness = makeHarness()
            let view = { longPress(log, maximumDistance: distance) }
            harness.frame(view())
            harness.pointer([(.pressed, 2, 1), (.dragged, 3, 1)], view)
            harness.now = 600 * gestureMillisecond
            harness.frame(view())
            #expect(log.entries.contains("ended true") == ends, "maximumDistance \(distance)")
        }
    }

    @Test("The long press reports the wake it needs, and the run loop's tick ends it")
    func longPressWakes() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { longPress(log) }
        harness.frame(view())
        harness.pointer([(.pressed, 2, 1)], view)
        #expect(harness.tui.mouseEventDispatcher.gestureDeadline == 500 * gestureMillisecond)
    }

    // MARK: Drag

    @Test("A drag starts at its minimum distance, from the press, and ends on the release")
    func dragStarts() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = {
            box(
                DragGesture(minimumDistance: 2)
                    .onChanged { log("changed \($0.startLocation.x),\($0.location.x) \($0.translation.width)") }
                    .onEnded { log("ended \($0.translation.width),\($0.translation.height)") })
        }
        harness.frame(view())
        harness.pointer([(.pressed, 2, 1), (.dragged, 3, 1)], view)
        #expect(log.entries.isEmpty, "one cell is short of two")
        harness.pointer([(.dragged, 4, 1), (.dragged, 6, 2), (.released, 6, 2)], view)
        #expect(log.entries == ["changed 2,4 2", "changed 2,6 4", "ended 4,1"])
    }

    @Test("A drag that never started does not end; one of minimum distance zero starts at the press")
    func dragNeverStarted() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { box(DragGesture().onEnded { _ in log("ended") }) }
        harness.frame(view())
        harness.click(2, 1, view)
        #expect(log.entries.isEmpty)

        let zero = GestureRecord()
        let view0 = {
            box(DragGesture(minimumDistance: 0).onChanged { zero("changed \($0.translation.width)") }.onEnded { zero("ended \($0.translation.width)") })
        }
        harness.frame(view0())
        harness.click(2, 1, view0)
        #expect(zero.entries == ["changed 0", "ended 0"])
    }

    @Test("A drag's velocity comes from the event times, and predicts a quarter-second on")
    func dragVelocity() {
        var values: [DragGesture.Value] = []
        let harness = makeHarness()
        let view = { box(DragGesture(minimumDistance: 0).onChanged { values.append($0) }.onEnded { values.append($0) }) }
        harness.frame(view())
        harness.pointer([(.pressed, 0, 0)], view)
        harness.now = 100 * gestureMillisecond
        harness.pointer([(.dragged, 4, 0)], view)
        #expect(values.last?.velocity == CellVector(dx: 40, dy: 0), "four cells in a tenth of a second")
        #expect(values.last?.predictedEndLocation == CellPoint(x: 14, y: 0))
        #expect(values.last?.predictedEndTranslation == CellSize(width: 14, height: 0))
        harness.now = 200 * gestureMillisecond
        harness.pointer([(.dragged, 4, 2)], view)
        #expect(values.last?.velocity == CellVector(dx: 20, dy: 10), "averaged with the last estimate")
        harness.now = 900 * gestureMillisecond
        harness.pointer([(.released, 4, 2)], view)
        #expect(values.last?.velocity == CellVector(dx: 20, dy: 10), "a still pointer reports nothing, so its velocity stands")
    }

    @Test("A drag in the global space reports terminal cells")
    func dragGlobal() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = {
            VStack(spacing: 0) {
                Text("header")
                Text("").frame(width: 10, height: 3)
                    .gesture(DragGesture(coordinateSpace: .global).onEnded { log("\($0.startLocation.y)→\($0.location.y)") })
            }
            .frame(width: 40, height: 12, alignment: .topLeading)
        }
        harness.frame(view())
        harness.pointer([(.pressed, 2, 1), (.dragged, 2, 3), (.released, 2, 3)], view)
        #expect(log.entries == ["1→3"])
    }
}
