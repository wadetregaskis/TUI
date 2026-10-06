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

    // MARK: - A recognized gesture still under way

    /// A gesture on the first box, and the second box plain, inside a tap.
    private func besidePlain(_ gesture: some Gesture, _ log: GestureRecord) -> some View {
        HStack(spacing: 2) {
            box.gesture(gesture)
            box
        }
        .onTapGesture { log("outer") }
        .frame(width: 40, height: 12, alignment: .topLeading)
    }

    /// Measured on macOS 15.8: a tap and a double tap together, beside a
    /// plain box inside a tap. Clicked once, the pair has recognized — its
    /// tap ended — and waits for the double tap's interval; a click on the
    /// box meanwhile runs nothing, the outer tap having been cancelled by the
    /// pair, and one after it the outer tap. Pinned because the arena's wait
    /// looks like a bug here: counting only an undecided gesture as waiting,
    /// the click on the box would have run the outer tap.
    @Test("A recognized simultaneous gesture still waiting holds the tap around it off a click beside it")
    func recognizedSimultaneousWaits() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = {
            besidePlain(
                TapGesture().simultaneously(with: TapGesture(count: 2))
                    .onEnded { log("sim \($0.first != nil) \($0.second != nil)") },
                log)
        }
        harness.frame(view())
        harness.click(1, 0, view)
        frame(harness, at: 100, view)
        harness.click(7, 0, view)
        frame(harness, at: 360, view)
        #expect(log.entries == ["sim true false"], "the box's click runs nothing; the pair ends with its interval")
        frame(harness, at: 1_000, view)
        harness.click(7, 0, view)
        #expect(log.entries == ["sim true false", "outer"])
    }

    /// Measured on macOS 15.8: a double tap or a tap, before a tap, beside a
    /// plain box inside a tap. A click ends the first part on its clock, the
    /// button up, and the sequence waits for its second tap with no limit:
    /// clicks on the box a second and two later run nothing, and a click on
    /// the sequence after them ends it — the outer tap does not run. The
    /// next click on the sequence starts it over, and ends nothing.
    @Test("A sequence waiting for its second gesture holds the tap around it off every click beside it")
    func sequenceWaitsWithoutLimit() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = {
            besidePlain(
                TapGesture(count: 2).exclusively(before: TapGesture()).sequenced(before: TapGesture())
                    .onEnded { _ in log("seq") },
                log)
        }
        harness.frame(view())
        harness.click(1, 0, view)
        for (millis, column) in [(1_000, 7), (2_000, 7), (3_000, 1), (4_000, 1)] {
            frame(harness, at: Int64(millis), view)
            harness.click(column, 0, view)
        }
        frame(harness, at: 5_000, view)
        #expect(log.entries == ["seq"])
    }

    // MARK: - A view that leaves

    /// A row, a 4×1 box with a double tap and a single tap, and beside it a
    /// button that removes it when `removes`.
    private struct RemovableRow: View {
        let log: GestureRecord
        let removes: Bool
        @State private var shown = true

        var body: some View {
            HStack(spacing: 2) {
                if shown {
                    Text("").frame(width: 4, height: 1)
                        .onTapGesture(count: 2) { log("open") }
                        .onTapGesture { log("select") }
                } else {
                    Text("").frame(width: 4, height: 1)
                }
                Button("Hide") {
                    log("hide")
                    if removes { shown = false }
                }
            }
            .frame(width: 40, height: 12, alignment: .topLeading)
        }
    }

    /// Measured on macOS 15.8: a click on the row, then 0.1 s later on a
    /// button that removes it, runs the button and nothing else; with a
    /// button that leaves the row, the single tap runs 0.35 s after the
    /// row's release. Kept in the arena, the removed row's gestures waited
    /// out the double tap's interval and ran the single tap for a view no
    /// longer on screen, and the arena kept them, and their closures, alive
    /// until then.
    @Test("A gesture whose view leaves is given up: a removed row's single tap does not run", arguments: [true, false])
    func departedViewsGestureGivesUp(_ removes: Bool) {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { RemovableRow(log: log, removes: removes) }
        harness.frame(view())
        harness.click(1, 0, view)
        frame(harness, at: 100, view)
        harness.click(6, 0, view)
        frame(harness, at: 200, view)
        #expect(log.entries == ["hide"])
        if removes {
            #expect(harness.tui.mouseEventDispatcher.gestureArenas.isEmpty, "the removed row's gestures are given up")
        }
        frame(harness, at: 360, view)
        frame(harness, at: 1_000, view)
        #expect(log.entries == (removes ? ["hide"] : ["hide", "select"]))
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
