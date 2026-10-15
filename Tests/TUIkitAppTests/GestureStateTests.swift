//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GestureStateTests.swift
//
//  `@GestureState` and `updating(_:body:)` as measured on macOS 15.8's
//  SwiftUI: the state follows the gesture, and resets when the gesture is
//  over — however it ends — before `onEnded` runs.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("SwiftUI's @GestureState")
struct GestureStateTests {
    private func makeHarness() -> InputChainHarness {
        let harness = InputChainHarness()
        harness.syncEventClock()
        return harness
    }

    /// A view whose body reads the gesture state, and logs each value it draws
    /// with, and each reset its reset callback is told of.
    private struct Dragged: View {
        let log: GestureRecord
        @GestureState private var offset: CellSize

        init(log: GestureRecord) {
            self.log = log
            _offset = GestureState(wrappedValue: CellSize(width: 0, height: 0)) { value, _ in
                log("reset from \(value.width)")
            }
        }

        var body: some View {
            log("draw \(offset.width)")
            return Text("").frame(width: 10, height: 3)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($offset) { value, state, _ in state = value.translation }
                        .onEnded { [log] _ in log("ended") })
                .frame(width: 40, height: 12, alignment: .topLeading)
        }
    }

    @Test("@GestureState follows the gesture and resets when it ends, before onEnded")
    func resetsOnEnd() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { Dragged(log: log) }
        harness.frame(view())
        harness.pointer([(.pressed, 1, 1), (.dragged, 4, 1)], view)
        #expect(log.entries.last == "draw 3")
        harness.pointer([(.released, 4, 1)], view)
        #expect(log.entries.suffix(3) == ["reset from 3", "ended", "draw 0"])
    }

    /// A long press that only ever reads `true` into a gesture state.
    private struct PressingBox: View {
        let log: GestureRecord
        @GestureState var pressing = false

        var body: some View {
            log("pressing \(pressing)")
            return Text("").frame(width: 10, height: 3)
                .gesture(LongPressGesture(minimumDuration: 2).updating($pressing) { value, state, _ in state = value })
        }
    }

    @Test("@GestureState resets when its gesture fails")
    func resetsOnFailure() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { PressingBox(log: log).frame(width: 40, height: 12, alignment: .topLeading) }
        harness.frame(view())
        harness.pointer([(.pressed, 1, 1)], view)
        #expect(log.entries.last == "pressing true")
        harness.pointer([(.released, 1, 1)], view)
        #expect(log.entries.last == "pressing false", "released before the minimum duration")
    }

    @Test("A gesture held back by one that outranks it writes nothing, so a cancel owes no reset")
    func heldBackWritesNothing() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = {
            PressingBox(log: log)
                .highPriorityGesture(DragGesture().onEnded { _ in log("outer drag") })
                .frame(width: 40, height: 12, alignment: .topLeading)
        }
        harness.frame(view())
        harness.pointer([(.pressed, 1, 1)], view)
        #expect(!log.entries.contains("pressing true"), "held back behind the undecided drag")
        harness.pointer([(.dragged, 3, 1), (.released, 3, 1)], view)
        #expect(log.entries.contains("outer drag"))
        #expect(!log.entries.contains("pressing true"))
    }
}
