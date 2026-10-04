//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TapGestureTests.swift
//
//  SwiftUI's TapGesture and SpatialTapGesture attached with
//  `gesture(_:including:)`: recognized on the release, with the thresholds
//  measured on macOS 15.8 — the release on the view, within the slop, held
//  no longer than 0.75 s, the next click of a multi-tap within 0.35 s.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("SwiftUI's TapGesture")
struct TapGestureTests {
    /// A 10×3 box at the top-left of a larger page, holding the gesture.
    private func box(_ gesture: some Gesture) -> some View {
        Text("").frame(width: 10, height: 3).gesture(gesture).frame(width: 40, height: 12, alignment: .topLeading)
    }

    private func makeHarness() -> InputChainHarness {
        let harness = InputChainHarness()
        harness.syncEventClock()
        return harness
    }

    @Test("A click on the view taps once, on the release")
    func click() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { box(TapGesture().onEnded { log("tap") }) }
        harness.frame(view())
        harness.pointer([(.pressed, 2, 1)], view)
        #expect(log.entries.isEmpty, "nothing on the press")
        harness.pointer([(.released, 2, 1)], view)
        #expect(log.entries == ["tap"])
    }

    @Test("A release off the view, or past the slop, is no tap")
    func releaseOffOrStrayed() {
        for (label, press, release) in [("off the view", (8, 1), (11, 1)), ("past the slop", (2, 1), (8, 1))] {
            let log = GestureRecord()
            let harness = makeHarness()
            let view = { box(TapGesture().onEnded { log("tap") }) }
            harness.frame(view())
            harness.pointer(
                [(.pressed, press.0, press.1), (.dragged, release.0, release.1), (.released, release.0, release.1)], view)
            #expect(log.entries.isEmpty, "\(label)")
        }
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { box(TapGesture().onEnded { log("tap") }) }
        harness.frame(view())
        harness.pointer([(.pressed, 2, 1), (.dragged, 6, 2), (.released, 6, 2)], view)
        #expect(log.entries == ["tap"], "five columns and one row is within the slop")
    }

    @Test("A press held past 0.75 s is no tap")
    func heldTooLong() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { box(TapGesture().onEnded { log("tap") }) }
        harness.frame(view())
        harness.pointer([(.pressed, 2, 1)], view)
        harness.now = 760 * gestureMillisecond
        harness.frame(view())
        harness.pointer([(.released, 2, 1)], view)
        #expect(log.entries.isEmpty)
    }

    @Test("count: 2 taps on the second of two quick clicks, not on a slow pair")
    func doubleTap() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { box(TapGesture(count: 2).onEnded { log("double") }) }
        harness.frame(view())
        harness.click(2, 1, view)
        #expect(log.entries.isEmpty)
        harness.now = 200 * gestureMillisecond
        harness.frame(view())
        harness.click(2, 1, view)
        #expect(log.entries == ["double"])

        harness.now = 2_000 * gestureMillisecond
        harness.frame(view())
        harness.click(2, 1, view)
        harness.now = 2_400 * gestureMillisecond
        harness.frame(view())
        harness.click(2, 1, view)
        #expect(log.entries == ["double"], "0.4 s between them is too slow")
    }

    @Test("SpatialTapGesture reports the release's cell, local or global, and only on its end")
    func spatial() {
        for space in [CoordinateSpace.local, .global] {
            let log = GestureRecord()
            let harness = makeHarness()
            let view = {
                VStack(spacing: 0) {
                    Text("header")
                    Text("").frame(width: 10, height: 3)
                        .gesture(
                            SpatialTapGesture(coordinateSpace: space)
                                .onChanged { log("changed \($0.location)") }
                                .onEnded { log("\($0.location.x),\($0.location.y)") })
                }
                .frame(width: 40, height: 12, alignment: .topLeading)
            }
            harness.frame(view())
            harness.pointer([(.pressed, 2, 2), (.dragged, 3, 2), (.released, 3, 2)], view)
            #expect(log.entries == [space == .local ? "3,1" : "3,2"], "\(space)")
        }
    }

    @Test("A view inside .disabled(true) takes no tap")
    func disabled() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { box(TapGesture().onEnded { log("tap") }).disabled(true) }
        harness.frame(view())
        harness.click(2, 1, view)
        #expect(log.entries.isEmpty)
    }
}
