//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GestureArenaLifetimeTests.swift
//
//  How long a gesture arena lives once presses overlap it: one dropped at a
//  press hands the clock of a gesture it shared to the arena still waiting,
//  and one whose release was lost is superseded by the next press.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Gesture arenas across presses")
struct GestureArenaLifetimeTests {
    private func makeHarness() -> InputChainHarness {
        let harness = InputChainHarness()
        harness.syncEventClock()
        return harness
    }

    /// A frame at `millis` on the harness's clock.
    private func frame(_ harness: InputChainHarness, at millis: Int64, _ build: () -> some View) {
        harness.now = millis * gestureMillisecond
        harness.frame(build())
    }

    /// A 4×1 box; two side by side in an `HStack(spacing: 2)` take columns
    /// 0–3 and 6–9 of row 0.
    private var box: some View { Text("").frame(width: 4, height: 1) }

    /// A gesture in two arenas is fed by the newer. When that one is dropped
    /// at a press — its ranked gestures all decided — while the older still
    /// waits, the older feeds the gesture from then on: left unfed, a
    /// simultaneous triple tap around two boxes, two clicks into it, never
    /// heard the clock that gives it up, and its deadline, long past, kept
    /// asking the run loop for a wake on every turn.
    @Test("A gesture whose newer arena is dropped hears the clock through the older one")
    func droppedArenaHandsOnTheClock() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = {
            HStack(spacing: 2) {
                box.onTapGesture(count: 2) { log("a double") }.onTapGesture { log("a single") }
                box.onTapGesture { log("b single") }
            }
            .simultaneousGesture(TapGesture(count: 3).onEnded { log("triple") })
            .frame(width: 40, height: 12, alignment: .topLeading)
        }
        harness.frame(view())
        harness.click(1, 0, view)
        frame(harness, at: 100, view)
        harness.click(7, 0, view)
        #expect(log.entries == ["b single"])
        frame(harness, at: 150, view)
        harness.click(20, 5, view)
        frame(harness, at: 360, view)
        #expect(log.entries == ["b single", "a single"], "the double tap gave up")
        frame(harness, at: 1_000, view)
        #expect(harness.tui.mouseEventDispatcher.gestureDeadline == nil, "the triple tap gave up too")
        #expect(harness.tui.mouseEventDispatcher.gestureArenas.isEmpty)
    }

    // MARK: - A sequence beside a plain view

    /// Measured on macOS 15.8, the review of a0fd0e4e4's case: a tap before
    /// a tap beside a plain box, inside a tap, ends at one click, so clicks
    /// on the box a second and two seconds later run the outer tap, and one
    /// on the sequence after them runs it again. Fed only the events after
    /// its first tap's end, the sequence waited for a second click with
    /// nothing to limit the wait, and held the outer tap off the box until
    /// the sequence was clicked again.
    @Test("A tap before a tap ends at one click, so a click beside it runs the tap around both")
    func tapSequenceBesideAPlainBox() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = {
            HStack(spacing: 2) {
                box.gesture(TapGesture().sequenced(before: TapGesture()).onEnded { _ in log("seq") })
                box
            }
            .onTapGesture { log("outer") }
            .frame(width: 40, height: 12, alignment: .topLeading)
        }
        harness.frame(view())
        harness.click(1, 0, view)
        frame(harness, at: 1_000, view)
        harness.click(7, 0, view)
        frame(harness, at: 2_000, view)
        harness.click(7, 0, view)
        frame(harness, at: 3_000, view)
        harness.click(1, 0, view)
        frame(harness, at: 4_000, view)
        #expect(log.entries == ["seq", "outer", "outer", "seq"])
    }

    // MARK: - A press whose release was lost

    /// A press whose release never came — a terminal that dropped it, a
    /// mouse-mode change mid-gesture — is superseded by the next press, as
    /// the dispatcher's own press record is. Its arena does not wait on: a
    /// drag still under way in it never hears a release, and kept waiting it
    /// held the tap around both presses back for good, so the click on the
    /// plain box beside the drag never ran it.
    @Test("A press whose release was lost does not hold up the next press's gestures")
    func lostReleaseIsSuperseded() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = {
            HStack(spacing: 2) {
                box.gesture(DragGesture().onEnded { _ in log("drag") })
                box
            }
            .onTapGesture { log("outer") }
            .frame(width: 40, height: 12, alignment: .topLeading)
        }
        harness.frame(view())
        harness.pointer([(.pressed, 1, 0)], view)
        frame(harness, at: 100, view)
        harness.click(7, 0, view)
        frame(harness, at: 2_000, view)
        #expect(log.entries == ["outer"])
    }
}
