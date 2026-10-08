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

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation

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
            // The end comes at the click on the sequence at 3 s, not later.
            #expect(log.entries == (millis < 3_000 ? [] : ["seq"]), "after the click at \(millis) ms")
        }
        frame(harness, at: 5_000, view)
        #expect(log.entries == ["seq"])
    }

    // MARK: - A view that leaves

    /// How a view leaves: taken out of the tree, or disabled.
    enum Leaving: CaseIterable, Sendable {
        case removed, disabled
    }

    /// A press and its release at one cell, with no frame between or after
    /// them: as a live app drains a click before its next frame.
    private func clickUnframed(_ harness: InputChainHarness, _ x: Int, _ y: Int) {
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: x, y: y))
    }

    /// A row, a 4×1 box with a double tap and a single tap, beside a plain
    /// box inside a tap; below them a button that makes the row leave as
    /// `leaving` says, or, given `nil`, keeps it; and below that a box with a
    /// tap of its own. The button and that box are outside the tap around
    /// the row.
    private struct LeavingRow: View {
        let log: GestureRecord
        let leaving: Leaving?
        @State private var gone = false

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 2) {
                    if gone, leaving == .removed {
                        Text("").frame(width: 4, height: 1)
                    } else {
                        Text("").frame(width: 4, height: 1)
                            .onTapGesture(count: 2) { log("open") }
                            .onTapGesture { log("select") }
                            .disabled(gone && leaving == .disabled)
                    }
                    Text("").frame(width: 4, height: 1)
                }
                .onTapGesture { log("outer") }
                Button("Hide") {
                    log("hide")
                    gone = true
                }
                Text("").frame(width: 4, height: 1).onTapGesture { log("other") }
            }
            .frame(width: 40, height: 12, alignment: .topLeading)
        }
    }

    /// Where `next` lands, and what that click runs of its own.
    private func target(_ next: NextClick) -> (x: Int, y: Int, own: [String]) {
        switch next {
        case .besideIt: (7, 0, ["outer"])
        case .button: (1, 1, ["hide"])
        case .otherTap: (1, 2, ["other"])
        }
    }

    /// Measured on macOS 15.8: with the row kept, a click on it, then 0.1 s
    /// later on the button, runs the button and the single tap 0.35 s after
    /// the row's release; each click on the box runs the outer tap.
    @Test("A row kept while its double tap waits runs its single tap at the interval")
    func keptRow() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { LeavingRow(log: log, leaving: nil) }
        harness.frame(view())
        harness.click(1, 0, view)
        frame(harness, at: 100, view)
        harness.click(1, 1, view)
        frame(harness, at: 360, view)
        frame(harness, at: 1_000, view)
        #expect(log.entries == ["hide", "select"])
        harness.click(7, 0, view)
        #expect(log.entries == ["hide", "select", "outer"])
    }

    /// Measured on macOS 15.8 (F2 probes review3b R4, review4 R11 and R12):
    /// a click on the row, then 0.1 s later on a button that removes it,
    /// runs the button and nothing else — not the single tap when the double
    /// tap's interval is out, nor the outer tap behind them. The next press,
    /// wherever it lands, runs the outer tap for the row's click, at the
    /// press: on the plain box beside the row, inside the outer tap, that
    /// click runs nothing of its own; on the button again or on the box with
    /// a tap of its own, outside the outer tap, it runs what it lands on, at
    /// its release. The next click on the box runs the outer tap as usual.
    /// Given up at the next frame, the row's gestures let the outer tap run
    /// then, and the click on the box ran it a second time; kept in the
    /// arena, they waited out the double tap's interval and ran the single
    /// tap for a view no longer on screen.
    @Test(
        "A row removed while its double tap waits runs nothing until the next press, which runs the tap around it",
        arguments: NextClick.allCases)
    func removedRow(_ next: NextClick) {
        let (x, y, own) = target(next)
        let log = GestureRecord()
        let harness = makeHarness()
        let dispatcher = harness.tui.mouseEventDispatcher
        let view = { LeavingRow(log: log, leaving: .removed) }
        harness.frame(view())
        harness.click(1, 0, view)
        frame(harness, at: 100, view)
        harness.click(1, 1, view)
        frame(harness, at: 360, view)
        frame(harness, at: 1_000, view)
        #expect(log.entries == ["hide"], "the row's gestures hear no clock once it has gone, nor run what they hold")
        #expect(dispatcher.gestureDeadline == nil, "nor ask for a wake")
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        #expect(log.entries == ["hide", "outer"], "the press gives the row's gestures up: the outer tap runs its click")
        harness.mouse(MouseEvent(button: .left, phase: .released, x: x, y: y))
        frame(harness, at: 1_100, view)
        let ran = ["hide", "outer"] + (next == .besideIt ? [] : own)
        #expect(log.entries == ran, "beside the row the click was the outer tap's, already over")
        #expect(dispatcher.gestureArenas.isEmpty)
        frame(harness, at: 2_000, view)
        harness.click(7, 0, view)
        #expect(log.entries == ran + ["outer"])
    }

    /// Measured on macOS 15.8 (F2 probes review4b R11d and R12d, review4c
    /// R14d, R15d and R17d): a row DISABLED while its double tap waits is
    /// given up at the disable, as a removed one is not. The outer tap runs
    /// the row's click then — 0.1 s after the row's release, by the button
    /// or by a timer, with no click after it — and the next click runs what
    /// it lands on as usual, the box beside the row included. TUIkit treats
    /// a disabled view as one that has gone (decisions B-F2-2): the outer
    /// tap runs at the next press, and that press, beside the row, runs
    /// nothing of its own.
    @Test(
        "A row disabled while its double tap waits lets the tap around it run the row's click at once",
        arguments: NextClick.allCases)
    func disabledRow(_ next: NextClick) {
        let (x, y, own) = target(next)
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { LeavingRow(log: log, leaving: .disabled) }
        harness.frame(view())
        harness.click(1, 0, view)
        frame(harness, at: 100, view)
        harness.click(1, 1, view)
        frame(harness, at: 200, view)
        frame(harness, at: 1_000, view)
        withKnownIssue("B-F2-2: a disabled view's gestures wait for the next press, as a removed view's do") {
            #expect(log.entries == ["hide", "outer"], "the outer tap runs the row's click at the disable")
        }
        harness.click(x, y, view)
        frame(harness, at: 1_100, view)
        let ran = ["hide", "outer"] + own
        if next == .besideIt {
            withKnownIssue("B-F2-2: TUIkit's press beside the row is the outer tap's held click") {
                #expect(log.entries == ran)
            }
        } else {
            #expect(log.entries == ran)
        }
        frame(harness, at: 2_000, view)
        harness.click(7, 0, view)
        if next == .besideIt {
            withKnownIssue("B-F2-2: TUIkit's press beside the row is the outer tap's held click") {
                #expect(log.entries == ran + ["outer"])
            }
        } else {
            #expect(log.entries == ran + ["outer"])
        }
    }

    /// A sequence that waits for its second tap once clicked, on a 4×1 box
    /// beside a plain one inside a tap; below them a button that makes the
    /// sequence leave as `leaving` says; and below that a box with a tap of
    /// its own.
    private struct LeavingSequence: View {
        let log: GestureRecord
        let leaving: Leaving
        @State private var gone = false

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 2) {
                    if gone, leaving == .removed {
                        Text("").frame(width: 4, height: 1)
                    } else {
                        Text("").frame(width: 4, height: 1)
                            .gesture(
                                TapGesture(count: 2).exclusively(before: TapGesture())
                                    .sequenced(before: TapGesture())
                                    .onEnded { _ in log("seq") })
                            .disabled(gone)
                    }
                    Text("").frame(width: 4, height: 1)
                }
                .onTapGesture { log("outer") }
                Button("Hide") {
                    log("hide")
                    gone = true
                }
                Text("").frame(width: 4, height: 1).onTapGesture { log("other") }
            }
            .frame(width: 40, height: 12, alignment: .topLeading)
        }
    }

    /// Where the first click after the sequence leaves lands: the plain box
    /// beside it, the button again, or the box with a tap of its own.
    enum NextClick: CaseIterable, Sendable {
        case besideIt, button, otherTap
    }

    /// Measured on macOS 15.8: the sequence clicked once waits for its second
    /// tap, having cancelled the outer tap; a button then removes or
    /// disables it. The first click after that, wherever it lands, gives the
    /// sequence up — after it has been decided against it, so on the plain
    /// box beside it the click runs nothing, as it would have with the
    /// sequence still there, while on the button or on the other box it runs
    /// what it lands on. The click on the box after that runs the outer tap.
    /// Each whether or not a frame comes between the button and the next
    /// click, and with no frame between the clicks. Given up at the next
    /// frame instead, the sequence let the click beside it run the outer tap
    /// when a frame came first, and, when none came, kept the outer tap off
    /// every click until one did.
    @Test(
        "The first click after a waiting sequence leaves is decided against it, then gives it up",
        arguments: Leaving.allCases, NextClick.allCases)
    func leavingSequence(_ leaving: Leaving, _ next: NextClick) {
        let (x, y, ran): (Int, Int, [String]) =
            switch next {
            case .besideIt: (7, 0, [])
            case .button: (1, 1, ["hide"])
            case .otherTap: (1, 2, ["other"])
            }
        for framed in [false, true] {
            let log = GestureRecord()
            let harness = makeHarness()
            let view = { LeavingSequence(log: log, leaving: leaving) }
            harness.frame(view())
            harness.click(1, 0, view)
            frame(harness, at: 1_000, view)
            harness.click(1, 1, view)
            if framed { frame(harness, at: 1_500, view) }
            harness.now = 2_000 * gestureMillisecond
            clickUnframed(harness, x, y)
            #expect(log.entries == ["hide"] + ran, "framed: \(framed)")
            harness.now = 3_000 * gestureMillisecond
            clickUnframed(harness, 7, 0)
            #expect(log.entries == ["hide"] + ran + ["outer"], "framed: \(framed)")
        }
    }

    /// A reference the view builder reads, so a test can change the view
    /// between frames as a model would.
    private final class Gone {
        var value = false
    }

    /// Measured on macOS 15.8: a drag beside a plain box inside a tap,
    /// removed or disabled mid-drag, reports nothing more — no change at the
    /// next move, no end at the release — and a click on the box after the
    /// release runs the outer tap. Fed the move and the release before the
    /// next frame gave it up, the drag reported both for a view no longer
    /// on screen.
    @Test("A drag whose view leaves mid-drag reports nothing more", arguments: Leaving.allCases)
    func leavingDrag(_ leaving: Leaving) {
        let log = GestureRecord()
        let harness = makeHarness()
        let gone = Gone()
        let view = {
            HStack(spacing: 2) {
                if gone.value, leaving == .removed {
                    box
                } else {
                    box.gesture(
                        DragGesture()
                            .onChanged { log("changed \($0.translation.width)") }
                            .onEnded { log("ended \($0.translation.width)") }
                    )
                    .disabled(gone.value)
                }
                box
            }
            .onTapGesture { log("outer") }
            .frame(width: 40, height: 12, alignment: .topLeading)
        }
        harness.frame(view())
        harness.pointer([(.pressed, 0, 0), (.dragged, 1, 0), (.dragged, 2, 0)], view)
        #expect(log.entries == ["changed 1", "changed 2"])
        gone.value = true
        harness.frame(view())
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 3, y: 0))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 3, y: 0))
        harness.frame(view())
        #expect(log.entries == ["changed 1", "changed 2"])
        harness.click(7, 0, view)
        #expect(log.entries == ["changed 1", "changed 2", "outer"])
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
