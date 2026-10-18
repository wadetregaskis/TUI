//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GestureDeadlineTests.swift
//
//  A timed gesture's deadline runs from the event that armed it, not from
//  the first frame after that event (decisions B92). A long press ends, and
//  a double tap gives up, at the first frame at or past the event's time plus
//  the duration; before, the deadline was counted from the frame after the
//  event, which put it up to a frame late.
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
@Suite("Timed gestures count their deadlines from the event")
struct GestureDeadlineTests {
    /// The press at 1 s; the first frame after it 10 ms on, as a slow frame
    /// or the frame-rate cap leaves it. 500 ms after the press, the long
    /// press has ended: 500 ms after that frame it had not.
    @Test("A long press ends its minimum duration after the press, not after the frame that followed it")
    func longPressFromThePress() {
        let log = GestureRecord()
        let harness = InputChainHarness()
        func view() -> some View {
            Text("XYZ")
                .onLongPressGesture(minimumDuration: 0.5) {
                    log("perform")
                }
                .frame(width: 40, height: 12, alignment: .topLeading)
        }
        harness.now = 1_000 * gestureMillisecond
        harness.frame(view())
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        harness.now = 1_010 * gestureMillisecond
        harness.frame(view())
        #expect(harness.tui.mouseEventDispatcher.gestureDeadline == 1_500 * gestureMillisecond)
        harness.now = 1_499 * gestureMillisecond
        harness.frame(view())
        #expect(log.entries.isEmpty)
        harness.now = 1_500 * gestureMillisecond
        harness.frame(view())
        #expect(log.entries == ["perform"])
    }

    /// The same for a double tap's wait: it gives up 0.35 s after the first
    /// click's release, so the single tap it held back runs then.
    @Test("A double tap gives up 0.35 s after the release, not after the frame that followed it")
    func doubleTapFromTheRelease() {
        let log = GestureRecord()
        let harness = InputChainHarness()
        func view() -> some View {
            Text("").frame(width: 10, height: 3)
                .onTapGesture(count: 2) { log("double") }
                .onTapGesture { log("single") }
                .frame(width: 40, height: 12, alignment: .topLeading)
        }
        harness.now = 1_000 * gestureMillisecond
        harness.frame(view())
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 2, y: 1))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 2, y: 1))
        harness.now = 1_016 * gestureMillisecond
        harness.frame(view())
        #expect(log.entries.isEmpty, "held: the double tap may still come")
        harness.now = 1_350 * gestureMillisecond
        harness.frame(view())
        #expect(log.entries == ["single"])
    }
}
