//  🖥️ TUI — A Terminal UI framework for Swift
//  TapGestureTests.swift
//
//  SwiftUI's TapGesture and SpatialTapGesture attached with
//  `gesture(_:including:)`: recognized on the release, with the thresholds
//  measured on macOS 15.8 — the release on the view, within the slop, held
//  no longer than 0.75 s, the next click of a multi-tap released within
//  0.35 s of the last.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

@MainActor
@Suite("SwiftUI's TapGesture")
struct TapGestureTests {
    /// A 10×3 box at the top-left of a larger page, holding the gesture.
    private func box(_ gesture: some Gesture) -> some View {
        Text("").frame(width: 10, height: 3).gesture(gesture).frame(width: 40, height: 12, alignment: .topLeading)
    }

    private func makeHarness() -> InputChainHarness {
        InputChainHarness()
    }

    /// A button event at a cell, with the frames it causes.
    private func send(_ phase: MousePhase, _ x: Int, _ y: Int, to app: TestApp) {
        app.mouse(MouseEvent(button: .left, phase: phase, x: x, y: y))
    }

    @Test("A click on the view taps once, on the release")
    func click() {
        let log = GestureRecord()
        let app = TestApp(width: 40, height: 12) { box(TapGesture().onEnded { log("tap") }) }
        send(.pressed, 2, 1, to: app)
        #expect(log.entries.isEmpty, "nothing on the press")
        send(.released, 2, 1, to: app)
        #expect(log.entries == ["tap"])
    }

    @Test("A release off the view, or past the slop, is no tap")
    func releaseOffOrStrayed() {
        for (label, press, release) in [("off the view", (8, 1), (11, 1)), ("past the slop", (2, 1), (8, 1))] {
            let log = GestureRecord()
            let app = TestApp(width: 40, height: 12) { box(TapGesture().onEnded { log("tap") }) }
            app.drag(from: CellPoint(x: press.0, y: press.1), to: CellPoint(x: release.0, y: release.1))
            #expect(log.entries.isEmpty, "\(label)")
        }
        let log = GestureRecord()
        let app = TestApp(width: 40, height: 12) { box(TapGesture().onEnded { log("tap") }) }
        app.drag(from: CellPoint(x: 2, y: 1), to: CellPoint(x: 6, y: 2))
        #expect(log.entries == ["tap"], "five columns and one row is within the slop")
    }

    @Test("A press held past 0.75 s is no tap")
    func heldTooLong() {
        let log = GestureRecord()
        let app = TestApp(width: 40, height: 12) { box(TapGesture().onEnded { log("tap") }) }
        send(.pressed, 2, 1, to: app)
        app.advance(by: .milliseconds(760))
        send(.released, 2, 1, to: app)
        #expect(log.entries.isEmpty)
    }

    @Test("count: 2 taps on the second of two quick clicks, not on a slow pair")
    func doubleTap() {
        let log = GestureRecord()
        let app = TestApp(width: 40, height: 12) { box(TapGesture(count: 2).onEnded { log("double") }) }
        let cell = CellPoint(x: 2, y: 1)
        app.click(at: cell)
        #expect(log.entries.isEmpty)
        app.advance(by: .milliseconds(200))
        app.click(at: cell)
        #expect(log.entries == ["double"])

        app.advance(by: .milliseconds(1_800))
        app.click(at: cell)
        app.advance(by: .milliseconds(400))
        app.click(at: cell)
        #expect(log.entries == ["double"], "0.4 s between them is too slow")
    }

    /// Measured on macOS 15.8: a second press 0.12 s after the first release,
    /// held 0.15 s, double-taps; held 0.25 s — released 0.37 s after the
    /// first — it does not, and the double tap has already given up at 0.35 s
    /// with the button still down. The interval runs release to release; the
    /// press in time is not enough.
    @Test("count: 2 wants its second click released within 0.35 s of the first, not merely pressed")
    func doubleTapReleaseToRelease() {
        // (second press, its release, whether to draw the frame at the
        // release's instant before the release arrives)
        let cases: [(press: Int64, release: Int64, frameFirst: Bool, taps: [String])] = [
            (150, 300, true, ["double"]),
            (150, 400, true, []),
            (150, 400, false, []),
            (300, 450, true, []),
        ]
        for (press, release, frameFirst, taps) in cases {
            let log = GestureRecord()
            let harness = makeHarness()
            let view = { box(TapGesture(count: 2).onEnded { log("double") }) }
            harness.frame(view())
            harness.click(2, 1, view)
            harness.now = press * gestureMillisecond
            harness.frame(view())
            harness.pointer([(.pressed, 2, 1)], view)
            harness.now = release * gestureMillisecond
            // Drawn first, the frame's tick gives the tap up before the
            // release; not, the release finds itself late by the event clock.
            if frameFirst { harness.frame(view()) }
            harness.pointer([(.released, 2, 1)], view)
            #expect(log.entries == taps, "pressed at \(press) ms, released at \(release) ms, frame first \(frameFirst)")
        }
    }

    @Test("SpatialTapGesture reports the release's cell, local or global, and only on its end")
    func spatial() {
        for space in [CoordinateSpace.local, .global] {
            let log = GestureRecord()
            let app = TestApp(width: 40, height: 12) {
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
            app.drag(from: CellPoint(x: 2, y: 2), to: CellPoint(x: 3, y: 2))
            #expect(log.entries == [space == .local ? "3,1" : "3,2"], "\(space)")
        }
    }

    @Test("A view inside .disabled(true) takes no tap")
    func disabled() {
        let log = GestureRecord()
        let app = TestApp(width: 40, height: 12) { box(TapGesture().onEnded { log("tap") }).disabled(true) }
        app.click(at: CellPoint(x: 2, y: 1))
        #expect(log.entries.isEmpty)
    }
}
