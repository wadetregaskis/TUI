//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnyGestureTests.swift
//
//  `AnyGesture` and an optional gesture: each is recognized as the gesture it
//  holds, and an absent one as nothing.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("AnyGesture and optional gestures")
struct AnyGestureTests {
    private func makeHarness() -> InputChainHarness {
        let harness = InputChainHarness()
        harness.syncEventClock()
        return harness
    }

    private func box(_ gesture: some Gesture) -> some View {
        Text("").frame(width: 10, height: 3).gesture(gesture).frame(width: 40, height: 12, alignment: .topLeading)
    }

    @Test("AnyGesture is recognized as the gesture it erases, and starts afresh when that changes type")
    func anyGesture() {
        let log = GestureRecord()
        let harness = makeHarness()
        var double = false
        let view = {
            box(
                (double
                    ? AnyGesture(TapGesture(count: 2).map { "double" })
                    : AnyGesture(SpatialTapGesture().map { "single at \($0.location.x)" }))
                    .onEnded { log($0) })
        }
        harness.frame(view())
        harness.click(2, 1, view)
        #expect(log.entries == ["single at 2"])
        double = true
        harness.now = 1_000 * gestureMillisecond
        harness.frame(view())
        harness.click(2, 1, view)
        #expect(log.entries == ["single at 2"], "one click of a double tap is not a tap")
        harness.click(2, 1, view)
        #expect(log.entries == ["single at 2", "double"])
    }

    @Test("An optional gesture is recognized when present, and recognizes nothing when nil")
    func optionalGesture() {
        let log = GestureRecord()
        let harness = makeHarness()
        var enabled = true
        let view = { box(enabled ? TapGesture().onEnded { log("tap") } : nil) }
        harness.frame(view())
        harness.click(1, 1, view)
        #expect(log.entries == ["tap"])
        enabled = false
        harness.now = 1_000 * gestureMillisecond
        harness.frame(view())
        harness.click(1, 1, view)
        #expect(log.entries == ["tap"])
    }
}
