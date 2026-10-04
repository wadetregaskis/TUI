//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GestureAdaptorTests.swift
//
//  The gesture adaptors: `modifiers(_:)`, read at the press and satisfied by
//  a superset of the keys (measured on macOS 15.8), and `map(_:)`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Gesture adaptors")
struct GestureAdaptorTests {
    private func makeHarness() -> InputChainHarness {
        let harness = InputChainHarness()
        harness.syncEventClock()
        return harness
    }

    private func box(_ gesture: some Gesture) -> some View {
        Text("").frame(width: 10, height: 3).gesture(gesture).frame(width: 40, height: 12, alignment: .topLeading)
    }

    @Test("modifiers(_:) admits a press with the keys asked for, or more")
    func modifiersGate() {
        for (shift, ctrl, taps) in [(false, false, 0), (true, false, 1), (true, true, 1), (false, true, 0)] {
            let log = GestureRecord()
            let harness = makeHarness()
            let view = { box(TapGesture().modifiers(.shift).onEnded { log("tap") }) }
            harness.frame(view())
            harness.pointer([(.pressed, 1, 1), (.released, 1, 1)], modifiers: (shift, ctrl, false), view)
            #expect(log.entries.count == taps, "shift \(shift) control \(ctrl)")
        }
    }

    @Test("modifiers(_:) reads the keys at the press: letting go mid-drag does not stop the gesture")
    func modifiersReadAtPress() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { box(DragGesture().modifiers(.option).onEnded { log("ended \($0.translation.width)") }) }
        harness.frame(view())
        harness.pointer([(.pressed, 1, 1)], modifiers: (false, false, true), view)
        harness.pointer([(.dragged, 4, 1), (.released, 4, 1)], view)
        #expect(log.entries == ["ended 3"])
    }

    @Test("map(_:) transforms the gesture's value")
    func map() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { box(TapGesture().map { "mapped" }.onEnded { log($0) }) }
        harness.frame(view())
        harness.click(1, 1, view)
        #expect(log.entries == ["mapped"])
    }
}
