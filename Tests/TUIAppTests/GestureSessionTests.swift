//  🖥️ TUI — A Terminal UI framework for Swift
//  GestureSessionTests.swift
//
//  A press that comes while a gesture still waits — a double tap waiting for
//  its next click — as measured on macOS 15.8 with synthesised NSEvents: the
//  waiting gesture is not given up, a gesture under both presses carries on
//  where it is, and one that finished stays finished until the ranked
//  gestures have all decided.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("A press while a gesture waits")
struct GestureSessionTests {
    private func makeHarness() -> InputChainHarness {
        InputChainHarness()
    }

    /// A frame at `millis` on the harness's clock.
    private func frame(_ harness: InputChainHarness, at millis: Int64, _ build: () -> some View) {
        harness.now = millis * gestureMillisecond
        harness.frame(build())
    }

    /// Two 4×1 boxes side by side, columns 0–3 and 6–9 of row 0, at the
    /// top-left of a larger page.
    private func pair(_ first: some View, _ second: some View) -> some View {
        HStack(spacing: 2) {
            first.frame(width: 4, height: 1)
            second.frame(width: 4, height: 1)
        }
        .frame(width: 40, height: 12, alignment: .topLeading)
    }

    private var box: some View { Text("").frame(width: 4, height: 1) }

    // MARK: - A click on another view

    /// Two double taps side by side, inside a single tap that reports where.
    private func siblings(_ log: GestureRecord) -> some View {
        HStack(spacing: 2) {
            box.onTapGesture(count: 2) { log("a") }
            box.onTapGesture(count: 2) { log("b") }
        }
        .onTapGesture(coordinateSpace: .global) { log("single at \($0.x),\($0.y)") }
        .frame(width: 40, height: 12, alignment: .topLeading)
    }

    /// Measured on macOS 15.8: a click on one double tap, then within the
    /// double-tap interval a click on its sibling, runs the single tap around
    /// them once — for the FIRST click, at its location — when the second
    /// double tap gives up, 0.35 s after the second release. The press on the
    /// sibling does not give the first double tap up: it waits out its own
    /// interval, and the single tap waits for both. Given up at the press, the
    /// first double tap let the single tap run at once.
    @Test("A click on a sibling double tap: the single tap around both runs once, for the first click, when the second gives up")
    func siblingDoubleTaps() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { siblings(log) }
        harness.frame(view())
        harness.click(1, 0, view)
        frame(harness, at: 100, view)
        harness.click(7, 0, view)
        frame(harness, at: 360, view)
        #expect(log.entries.isEmpty, "the first double tap gave up; the second still waits")
        frame(harness, at: 460, view)
        #expect(log.entries == ["single at 1,0"], "the second gave up: the single tap, for the first click")
        frame(harness, at: 2_000, view)
        #expect(log.entries == ["single at 1,0"], "the second click runs no single tap of its own")
    }

    /// A sibling whose gesture a quick click fails at its release.
    enum FailingSibling: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case longPress
        case drag

        var testDescription: String { rawValue }
    }

    /// A double tap and `sibling` side by side, inside a single tap that
    /// reports where.
    private func doubleBeside(_ sibling: FailingSibling, _ log: GestureRecord) -> some View {
        let second: AnyView =
            switch sibling {
            case .longPress: AnyView(box.onLongPressGesture { log("long") })
            case .drag: AnyView(box.gesture(DragGesture().onEnded { _ in log("drag ended") }))
            }
        return HStack(spacing: 2) {
            box.onTapGesture(count: 2) { log("a") }
            second
        }
        .onTapGesture(coordinateSpace: .global) { log("single at \($0.x),\($0.y)") }
        .frame(width: 40, height: 12, alignment: .topLeading)
    }

    /// Measured on macOS 15.8, with a long press or a drag beside the double
    /// tap in place of the second: a click on the double tap, then a quick
    /// click on the sibling, runs the single tap around both once, for the
    /// first click, 0.35 s after the FIRST release — the sibling's gesture
    /// failed at its release, and the first double tap still waited. Given up
    /// at the press, the double tap let the single tap run at once.
    @Test("A click on a sibling long press or drag: the single tap around both runs once, for the first click", arguments: FailingSibling.allCases)
    func siblingFailsAtRelease(_ sibling: FailingSibling) {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { doubleBeside(sibling, log) }
        harness.frame(view())
        harness.click(1, 0, view)
        frame(harness, at: 100, view)
        harness.click(7, 0, view)
        frame(harness, at: 300, view)
        #expect(log.entries.isEmpty, "the double tap still waits")
        frame(harness, at: 360, view)
        #expect(log.entries == ["single at 1,0"], "the double tap gave up: the single tap, for the first click")
        frame(harness, at: 2_000, view)
        #expect(log.entries == ["single at 1,0"], "the second click runs no single tap of its own")
    }

    @Test("A click, then a double click on a sibling: its double tap alone")
    func siblingDoubleClick() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { siblings(log) }
        harness.frame(view())
        harness.click(1, 0, view)
        frame(harness, at: 100, view)
        harness.click(7, 0, view)
        frame(harness, at: 200, view)
        harness.click(7, 0, view)
        frame(harness, at: 2_000, view)
        #expect(log.entries == ["b"])
    }

    /// Measured on macOS 15.8: clicks on A, B and A again, 0.1 s apart, are
    /// A's double tap — the click on B between them is not A's to hear.
    @Test("A click on a sibling between two clicks on a double tap does not break it")
    func siblingBetweenClicks() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { siblings(log) }
        harness.frame(view())
        harness.click(1, 0, view)
        frame(harness, at: 100, view)
        harness.click(7, 0, view)
        frame(harness, at: 200, view)
        harness.click(1, 0, view)
        frame(harness, at: 2_000, view)
        #expect(log.entries == ["a"])
    }

    /// What the second view is, in the click-elsewhere tests.
    enum Elsewhere: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case plain
        case tap
        case button

        var testDescription: String { rawValue }

        /// The action the second view runs, if any.
        var action: [String] {
            switch self {
            case .plain: []
            case .tap: ["c tap"]
            case .button: ["c button"]
            }
        }
    }

    /// A double tap ahead of a single tap, spelt `form`, and beside it
    /// `elsewhere`.
    private func doubleBeside(_ elsewhere: Elsewhere, _ form: DoubleThenSingle, _ log: GestureRecord) -> some View {
        let first: AnyView =
            switch form {
            case .gestures:
                AnyView(
                    box.gesture(TapGesture(count: 2).onEnded { log("a double") })
                        .gesture(TapGesture().onEnded { log("a single") }))
            case .onTapGestures:
                AnyView(box.onTapGesture(count: 2) { log("a double") }.onTapGesture { log("a single") })
            case .exclusive:
                AnyView(
                    box.gesture(
                        TapGesture(count: 2).onEnded { log("a double") }
                            .exclusively(before: TapGesture().onEnded { log("a single") })))
            }
        let second: AnyView =
            switch elsewhere {
            case .plain: AnyView(box)
            case .tap: AnyView(box.onTapGesture { log("c tap") })
            case .button: AnyView(Button("c") { log("c button") })
            }
        return pair(first, second)
    }

    /// Measured on macOS 15.8 with a plain view, a tap and a button beside:
    /// a click on a double tap, then a click elsewhere within the double-tap
    /// interval, runs the other view's action at its release and the single
    /// tap behind the double tap 0.35 s after the FIRST release — and so too
    /// when the second press is held past that. The press elsewhere gave the
    /// double tap up, and with it the single tap waiting behind it, in each
    /// of the three spellings.
    @Test(
        "A click elsewhere does not give a waiting double tap up, nor the single tap behind it",
        arguments: Elsewhere.allCases, DoubleThenSingle.allCases)
    func clickElsewhere(_ elsewhere: Elsewhere, _ form: DoubleThenSingle) {
        let quick = GestureRecord()
        var harness = makeHarness()
        var view = { doubleBeside(elsewhere, form, quick) }
        harness.frame(view())
        harness.click(1, 0, view)
        frame(harness, at: 100, view)
        harness.click(6, 0, view)
        #expect(quick.entries == elsewhere.action, "quick: the other view's action, at its release")
        frame(harness, at: 360, view)
        #expect(quick.entries == elsewhere.action + ["a single"], "quick: the single tap, when the double tap gives up")

        let held = GestureRecord()
        harness = makeHarness()
        view = { doubleBeside(elsewhere, form, held) }
        harness.frame(view())
        harness.click(1, 0, view)
        frame(harness, at: 100, view)
        harness.pointer([(.pressed, 6, 0)], view)
        frame(harness, at: 360, view)
        #expect(held.entries == ["a single"], "held: the single tap, the button still down")
        frame(harness, at: 700, view)
        harness.pointer([(.released, 6, 0)], view)
        #expect(held.entries == ["a single"] + elsewhere.action, "held: the other view's action at its release")
    }

    /// A single tap on each of two boxes, under a high-priority double tap.
    private func underHighDouble(_ log: GestureRecord) -> some View {
        HStack(spacing: 2) {
            box.onTapGesture { log("a single") }
            box.onTapGesture { log("b single") }
        }
        .highPriorityGesture(TapGesture(count: 2).onEnded { log("outer double") })
        .frame(width: 40, height: 12, alignment: .topLeading)
    }

    /// Measured on macOS 15.8: the double tap over both boxes hears both
    /// clicks, so a quick click on each is its double tap. With the second
    /// press held, the double tap gives up 0.35 s after the first release and
    /// the first box's single tap runs then, for the first click; the held
    /// press is no tap. The second press gave the first box's tap up.
    @Test("Under a double tap over two boxes, a click on each is the double tap; the second held, the first box's tap")
    func highPriorityDoubleOverTwo() {
        let quick = GestureRecord()
        var harness = makeHarness()
        var view = { underHighDouble(quick) }
        harness.frame(view())
        harness.click(1, 0, view)
        frame(harness, at: 100, view)
        harness.click(7, 0, view)
        frame(harness, at: 2_000, view)
        #expect(quick.entries == ["outer double"])

        let held = GestureRecord()
        harness = makeHarness()
        view = { underHighDouble(held) }
        harness.frame(view())
        harness.click(1, 0, view)
        frame(harness, at: 100, view)
        harness.pointer([(.pressed, 7, 0)], view)
        frame(harness, at: 360, view)
        #expect(held.entries == ["a single"], "the double tap gave up, the button still down")
        frame(harness, at: 1_100, view)
        harness.pointer([(.released, 7, 0)], view)
        frame(harness, at: 2_000, view)
        #expect(held.entries == ["a single"], "the held press is no tap")
    }

    // MARK: - A button behind a double tap

    private func buttonUnderDouble(_ log: GestureRecord) -> some View {
        Button("Press") { log("action") }
            .highPriorityGesture(TapGesture(count: 2).onEnded { log("double") })
            .frame(width: 40, height: 12, alignment: .topLeading)
    }

    /// Measured on macOS 15.8: a button behind a high-priority double tap,
    /// clicked, then pressed again and held, runs once, for the first click,
    /// when the double tap gives up with the button still down — and not at
    /// the second release. It was given the second press instead, and ran at
    /// its release.
    @Test("A button behind a double tap runs for the first click when a held second press gives the double tap up")
    func buttonBehindDoubleHeld() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { buttonUnderDouble(log) }
        harness.frame(view())
        harness.click(1, 0, view)
        frame(harness, at: 150, view)
        harness.pointer([(.pressed, 1, 0)], view)
        frame(harness, at: 360, view)
        #expect(log.entries == ["action"], "the double tap gave up: the first click's action")
        frame(harness, at: 1_150, view)
        harness.pointer([(.released, 1, 0)], view)
        frame(harness, at: 2_000, view)
        #expect(log.entries == ["action"], "nothing at the second release")
    }

    @Test("A button behind a double tap: a click runs it late, a double click runs the double tap alone")
    func buttonBehindDouble() {
        let single = GestureRecord()
        var harness = makeHarness()
        var view = { buttonUnderDouble(single) }
        harness.frame(view())
        harness.click(1, 0, view)
        #expect(single.entries.isEmpty)
        frame(harness, at: 360, view)
        #expect(single.entries == ["action"])

        let double = GestureRecord()
        harness = makeHarness()
        view = { buttonUnderDouble(double) }
        harness.frame(view())
        harness.click(1, 0, view)
        frame(harness, at: 150, view)
        harness.click(1, 0, view)
        frame(harness, at: 2_000, view)
        #expect(double.entries == ["double"])
    }

    /// The button's click is given whole, press and release, after the
    /// button came up — while another press, on a second button, holds the
    /// pointer's capture. That capture is set aside and restored: taken over
    /// by the late click, the second button never heard its own release.
    @Test("A button's late click leaves the capture of a press under way to its own button")
    func lateClickKeepsCapture() throws {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = {
            HStack(spacing: 2) {
                Button("Alpha") { log("a") }.highPriorityGesture(TapGesture(count: 2).onEnded { log("a double") })
                Button("Gamma") { log("c") }
            }
            .frame(width: 40, height: 12, alignment: .topLeading)
        }
        let first = harness.frame(view()).lines[0].stripped
        let alpha = try #require(first.range(of: "Alpha"), "the first button's label")
        let gamma = try #require(first.range(of: "Gamma"), "the second button's label")
        harness.click(first.distance(from: first.startIndex, to: alpha.lowerBound), 0, view)
        frame(harness, at: 100, view)
        let column = first.distance(from: first.startIndex, to: gamma.lowerBound)
        harness.pointer([(.pressed, column, 0)], view)
        frame(harness, at: 300, view)
        #expect(log.entries.isEmpty, "the double tap still waits")
        frame(harness, at: 360, view)
        #expect(log.entries == ["a"], "the first button's click, the second still held")
        frame(harness, at: 500, view)
        harness.pointer([(.released, column, 0)], view)
        #expect(log.entries == ["a", "c"], "the second button heard its release")
    }

    // MARK: - Finished stays finished

    /// Measured on macOS 15.8: a simultaneous single tap beside a double tap
    /// runs for the first click of a double click and not the second — it
    /// finished at the first, and stays finished while the double tap waits.
    @Test("A simultaneous tap that ran stays finished while a double tap waits")
    func simultaneousTapStaysFinished() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = {
            Text("").frame(width: 10, height: 3)
                .onTapGesture(count: 2) { log("double") }
                .simultaneousGesture(TapGesture().onEnded { log("sim single") })
                .frame(width: 40, height: 12, alignment: .topLeading)
        }
        harness.frame(view())
        harness.click(2, 1, view)
        frame(harness, at: 150, view)
        harness.click(2, 1, view)
        frame(harness, at: 2_000, view)
        #expect(log.entries == ["sim single", "double"])
    }

    /// Measured on macOS 15.8 (the reverse): a single tap beside a
    /// simultaneous double tap runs for both clicks of a double click. Its
    /// ranked gestures have decided at the first click, so the second starts
    /// them over; only the simultaneous one carries on.
    @Test("Once the ranked gestures have decided, a simultaneous double tap waiting does not stop the next click's")
    func rankedRestartBesideSimultaneous() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = {
            Text("").frame(width: 10, height: 3)
                .onTapGesture { log("single") }
                .simultaneousGesture(TapGesture(count: 2).onEnded { log("sim double") })
                .frame(width: 40, height: 12, alignment: .topLeading)
        }
        harness.frame(view())
        harness.click(2, 1, view)
        frame(harness, at: 150, view)
        harness.click(2, 1, view)
        frame(harness, at: 2_000, view)
        #expect(log.entries == ["single", "sim double", "single"])
    }

    private func dragBehindDouble(_ log: GestureRecord) -> some View {
        Text("").frame(width: 10, height: 3)
            .onTapGesture(count: 2) { log("double") }
            .gesture(
                DragGesture()
                    .onChanged { log("changed \($0.translation.width)") }
                    .onEnded { log("ended \($0.translation.width)") })
            .frame(width: 40, height: 12, alignment: .topLeading)
    }

    /// Measured on macOS 15.8: behind a double tap, a drag that failed at a
    /// click — it never moved — stays failed through a second press within
    /// the double-tap interval, even one that drags far enough to give the
    /// double tap up. It started over at that press.
    @Test("A drag that failed at a click stays failed through the next press while the double tap waits")
    func failedDragStaysFailed() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { dragBehindDouble(log) }
        harness.frame(view())
        harness.click(2, 1, view)
        frame(harness, at: 150, view)
        harness.pointer([(.pressed, 2, 1), (.dragged, 5, 1), (.dragged, 9, 1), (.dragged, 12, 1), (.released, 12, 1)], view)
        frame(harness, at: 2_000, view)
        #expect(log.entries.isEmpty)
    }

    /// Measured on macOS 15.8: a small drag behind a double tap ends while
    /// held back, and keeps that end: a second drag within the double-tap
    /// interval that gives the double tap up reports the first drag's end,
    /// and nothing of its own; so does a second press held past the
    /// interval, at the moment the double tap gives up.
    @Test("A drag that ended behind a double tap keeps its end through the next press")
    func endedDragKeepsItsEnd() {
        let strayed = GestureRecord()
        var harness = makeHarness()
        var view = { dragBehindDouble(strayed) }
        harness.frame(view())
        harness.pointer([(.pressed, 2, 1), (.dragged, 4, 1), (.released, 4, 1)], view)
        frame(harness, at: 150, view)
        harness.pointer([(.pressed, 2, 1), (.dragged, 9, 1)], view)
        #expect(strayed.entries == ["ended 2"], "the first drag's end, at the move that gives the double tap up")
        harness.pointer([(.dragged, 12, 1), (.released, 12, 1)], view)
        frame(harness, at: 2_000, view)
        #expect(strayed.entries == ["ended 2"], "the second drag reports nothing")

        let held = GestureRecord()
        harness = makeHarness()
        view = { dragBehindDouble(held) }
        harness.frame(view())
        harness.pointer([(.pressed, 2, 1), (.dragged, 4, 1), (.released, 4, 1)], view)
        frame(harness, at: 150, view)
        harness.pointer([(.pressed, 2, 1), (.dragged, 4, 1)], view)
        frame(harness, at: 360, view)
        #expect(held.entries == ["ended 2"], "the first drag's end, when the double tap gives up")
        frame(harness, at: 600, view)
        harness.pointer([(.dragged, 6, 1), (.released, 6, 1)], view)
        frame(harness, at: 2_000, view)
        #expect(held.entries == ["ended 2"], "the second drag reports nothing")
    }

    /// Measured on macOS 15.8: a drag beside a simultaneous double tap that
    /// failed at a click drags at the next press — its ranked gestures had
    /// all decided.
    @Test("A drag beside a simultaneous double tap starts over at the next press")
    func dragRestartsBesideSimultaneous() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = {
            Text("").frame(width: 10, height: 3)
                .gesture(DragGesture().onEnded { log("ended \($0.translation.width)") })
                .simultaneousGesture(TapGesture(count: 2).onEnded { log("sim double") })
                .frame(width: 40, height: 12, alignment: .topLeading)
        }
        harness.frame(view())
        harness.click(2, 1, view)
        frame(harness, at: 150, view)
        harness.pointer([(.pressed, 2, 1), (.dragged, 9, 1), (.released, 9, 1)], view)
        #expect(log.entries == ["ended 7"])
    }
}
