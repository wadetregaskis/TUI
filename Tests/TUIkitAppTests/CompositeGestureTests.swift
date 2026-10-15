//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CompositeGestureTests.swift
//
//  The gesture algebra as measured on macOS 15.8's SwiftUI: a sequence hands
//  its second gesture the event that ended the first, or the next one after
//  a first that ended on its clock; an exclusive
//  gesture holds its second back until the first fails; a simultaneous one
//  drops a part that failed and ends once neither is undecided.
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
@Suite("SwiftUI's composite gestures")
struct CompositeGestureTests {
    private func makeHarness() -> InputChainHarness {
        let harness = InputChainHarness()
        harness.syncEventClock()
        return harness
    }

    private func box(_ gesture: some Gesture) -> some View {
        Text("").frame(width: 10, height: 3).gesture(gesture).frame(width: 40, height: 12, alignment: .topLeading)
    }

    // MARK: Sequence

    private func sequence(_ log: GestureRecord) -> some View {
        box(
            LongPressGesture(minimumDuration: 0.3).sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { log("changed \(Self.describe($0))") }
                .onEnded { log("ended \(Self.describe($0))") })
    }

    private static func describe(_ value: SequenceGesture<LongPressGesture, DragGesture>.Value) -> String {
        switch value {
        case .first(let pressed): "first(\(pressed))"
        case .second(let pressed, let drag): "second(\(pressed), \(drag.map { "\($0.translation.width)" } ?? "nil"))"
        }
    }

    @Test("A sequence whose first gesture ends on its clock hands its second the next event")
    func sequenceHandsOn() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { sequence(log) }
        harness.frame(view())
        harness.pointer([(.pressed, 1, 1)], view)
        harness.now = 300 * gestureMillisecond
        harness.frame(view())
        harness.pointer([(.dragged, 3, 1), (.dragged, 5, 1), (.released, 5, 1)], view)
        #expect(log.entries == [
            "changed first(true)", "changed second(true, nil)", "changed second(true, 0)",
            "changed second(true, 2)", "ended second(true, 2)",
        ])
    }

    @Test("A sequence whose first gesture fails never ends")
    func sequenceFails() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { sequence(log) }
        harness.frame(view())
        harness.pointer([(.pressed, 1, 1), (.dragged, 4, 1)], view)
        harness.now = 600 * gestureMillisecond
        harness.pointer([(.released, 4, 1)], view)
        #expect(log.entries == ["changed first(true)"])
    }

    /// A sequence that restarted at a press read its second gesture as the
    /// last sequence left it — ended — so when the long press ended on its
    /// clock the sequence ended too, with the last drag's value: `onEnded`
    /// ran at that tick and again at the release.
    @Test("A sequence run a second time reports nothing of the first run's second gesture")
    func sequenceRunTwice() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { sequence(log) }
        harness.frame(view())
        for start: Int64 in [0, 1_000] {
            harness.now = start * gestureMillisecond
            harness.frame(view())
            harness.pointer([(.pressed, 1, 1)], view)
            harness.now = (start + 300) * gestureMillisecond
            harness.frame(view())
            harness.pointer([(.dragged, 3, 1), (.dragged, 5, 1), (.released, 5, 1)], view)
        }
        let run = [
            "changed first(true)", "changed second(true, nil)", "changed second(true, 0)",
            "changed second(true, 2)", "ended second(true, 2)",
        ]
        #expect(log.entries == run + run)
    }

    /// The same with a long press that ends at the press: the second press
    /// ended the sequence on the spot, with the first drag's value, before
    /// its own drag ended it again at the release — three ends for two drags.
    /// Measured on macOS 15.8: one end per drag, at the release, its
    /// translation the whole drag's — the drag starts at the press that
    /// ended the long press.
    @Test("A sequence after a long press with no minimum duration ends once per drag, at the release")
    func zeroDurationSequenceRunTwice() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = {
            box(
                LongPressGesture(minimumDuration: 0).sequenced(before: DragGesture())
                    .onEnded { log("ended \(Self.describe($0))") })
        }
        harness.frame(view())
        harness.pointer([(.pressed, 1, 1), (.dragged, 3, 1), (.dragged, 6, 1), (.released, 6, 1)], view)
        #expect(log.entries == ["ended second(true, 5)"])
        harness.now = 600 * gestureMillisecond
        harness.frame(view())
        harness.pointer([(.pressed, 1, 1)], view)
        #expect(log.entries == ["ended second(true, 5)"], "the second press ends nothing")
        harness.pointer([(.dragged, 3, 1), (.dragged, 6, 1), (.released, 6, 1)], view)
        #expect(log.entries == ["ended second(true, 5)", "ended second(true, 5)"])
    }

    /// Measured on macOS 15.8: a tap before a tap ends at every click — the
    /// release that ends the first tap is the second's press and release —
    /// clicks a second apart and five apart alike. Fed only the events after
    /// the first tap's end, the sequence waited for another click, with no
    /// limit, and ended at every second click.
    @Test("A tap before a tap ends at every click")
    func tapBeforeTap() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { box(TapGesture().sequenced(before: TapGesture()).onEnded { _ in log("seq") }) }
        harness.frame(view())
        for (index, start) in [0, 1_000, 2_000, 7_000].enumerated() {
            harness.now = Int64(start) * gestureMillisecond
            harness.frame(view())
            harness.click(1, 1, view)
            #expect(log.entries.count == index + 1, "click \(index + 1)")
        }
    }

    /// Measured on macOS 15.8: a tap before a drag, or before a long press,
    /// never ends. The tap's release is the second gesture's press, already
    /// over, at which a drag that has not moved and a long press short of
    /// its minimum duration both fail, and the sequence with them; the next
    /// press starts the sequence over at the tap, and a drag of seven
    /// columns (past a tap's five) or a press held 0.8 s is no tap. The
    /// inner tap's `onEnded` runs at every click, and the second gesture's
    /// callbacks never run. Fed the release as a live press, the long press
    /// ran `onChanged(true)` at every click; and before the commit "A
    /// sequence's second gesture starts with the event that ended the
    /// first", the press after the click began the drag or the long press,
    /// and the sequence ended.
    @Test("A tap before a drag or a long press fails at the tap's release", arguments: [false, true])
    func tapBeforeDragOrLongPress(_ longPress: Bool) {
        let log = GestureRecord()
        let harness = makeHarness()
        let tap = TapGesture().onEnded { log("tap") }
        let view = {
            longPress
                ? AnyView(
                    box(
                        tap.sequenced(
                            before: LongPressGesture()
                                .onChanged { log("long \($0)") }
                                .onEnded { log("long ended \($0)") }
                        )
                        .onEnded { _ in log("seq") }))
                : AnyView(
                    box(
                        tap.sequenced(
                            before: DragGesture()
                                .onChanged { log("drag \($0.translation.width)") }
                                .onEnded { log("drag ended \($0.translation.width)") }
                        )
                        .onEnded { _ in log("seq") }))
        }
        harness.frame(view())
        harness.click(1, 1, view)
        #expect(log.entries == ["tap"])
        harness.now = 500 * gestureMillisecond
        harness.frame(view())
        if longPress {
            harness.pointer([(.pressed, 1, 1)], view)
            harness.now = 1_300 * gestureMillisecond
            harness.frame(view())
            harness.pointer([(.released, 1, 1)], view)
        } else {
            harness.pointer([(.pressed, 1, 1), (.dragged, 4, 1), (.dragged, 8, 1), (.released, 8, 1)], view)
        }
        #expect(log.entries == ["tap"], "a drag or a long hold is no tap, and nothing waits for it")
        harness.now = 2_000 * gestureMillisecond
        harness.frame(view())
        harness.click(1, 1, view)
        #expect(log.entries == ["tap", "tap"])
    }

    /// Measured on macOS 15.8: after a tap, a long press with no minimum
    /// duration, or a drag with no minimum distance, ends at the tap's
    /// release, which it takes as a press already over: it reports its end
    /// alone, never to `onChanged` — the long press `false`, the button
    /// being up, the drag a translation of nothing — and the sequence ends
    /// with it, at every click. Fed the release as a live press, the long
    /// press ran `onChanged(true)` and ended `true`, and the drag ran
    /// `onChanged` with its start.
    ///
    /// The drag's sequence ends AT the release, every click: 22 clicks on
    /// fresh views (F2 probe review4e). The one end the first probe saw
    /// 0.43 s after its release (review3d) was the probe's own: its log line
    /// described the drag's value, and a value's first description is slow
    /// and is built before the line takes its timestamp (review4f: 13 ms
    /// then, and none for a line logged before describing).
    @Test("A tap before a zero-duration long press or a zero-distance drag ends at the tap's release", arguments: [false, true])
    func tapBeforeInstantSecond(_ longPress: Bool) {
        let log = GestureRecord()
        let harness = makeHarness()
        let tap = TapGesture().onEnded { log("tap") }
        let view = {
            longPress
                ? AnyView(
                    box(
                        tap.sequenced(
                            before: LongPressGesture(minimumDuration: 0)
                                .onChanged { log("long \($0)") }
                                .onEnded { log("long ended \($0)") }
                        )
                        .onEnded { value in
                            if case .second(_, let pressed) = value { log("seq \(pressed.map { "\($0)" } ?? "nil")") }
                        }))
                : AnyView(
                    box(
                        tap.sequenced(
                            before: DragGesture(minimumDistance: 0)
                                .onChanged { log("drag \($0.translation.width)") }
                                .onEnded { log("drag ended \($0.translation.width)") }
                        )
                        .onEnded { value in
                            if case .second(_, let drag) = value {
                                log("seq \(drag.map { "\($0.translation.width)" } ?? "nil")")
                            }
                        }))
        }
        let click = longPress ? ["tap", "long ended false", "seq false"] : ["tap", "drag ended 0", "seq 0"]
        harness.frame(view())
        harness.click(1, 1, view)
        #expect(log.entries == click)
        harness.now = 600 * gestureMillisecond
        harness.frame(view())
        harness.click(1, 1, view)
        #expect(log.entries == click + click)
    }

    /// Measured on macOS 15.8 (F2 probe review4, N1): after a tap, a
    /// sequence of two zero-duration long presses ends at the tap's release
    /// with both `false`: the press already over that starts the inner
    /// sequence is still over when its first long press hands it to its
    /// second. Taking that press for a press of its own, the second ended
    /// `true`.
    @Test("A tap before a sequence of zero-duration long presses ends both false at the tap's release")
    func tapBeforeInstantSequence() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = {
            box(
                TapGesture().onEnded { log("tap") }
                    .sequenced(
                        before: LongPressGesture(minimumDuration: 0).onEnded { log("a \($0)") }
                            .sequenced(before: LongPressGesture(minimumDuration: 0).onEnded { log("b \($0)") })
                            .onEnded { value in
                                if case .second(let a, let b) = value { log("inner \(a) \(b.map { "\($0)" } ?? "nil")") }
                            }
                    )
                    .onEnded { _ in log("seq") })
        }
        let click = ["tap", "a false", "b false", "inner false false", "seq"]
        harness.frame(view())
        harness.click(1, 1, view)
        #expect(log.entries == click)
        harness.now = 600 * gestureMillisecond
        harness.frame(view())
        harness.click(1, 1, view)
        #expect(log.entries == click + click)
    }

    /// Measured on macOS 15.8 (F2 probe review4, S): a tap before a drag, or
    /// before a long press, inside an `.onTapGesture` — around it and a
    /// plain box beside it, or on the same view after it. The sequence fails
    /// at the tap's release, so it holds nothing back: every click on it runs
    /// the inner tap's `onEnded` and then the tap around it, and a click on
    /// the box beside it runs that tap alone. Pinned because it follows from
    /// the commit "A sequence's second gesture starts with the event that
    /// ended the first" and was unmeasured: before it, the sequence went on
    /// to wait for its second gesture and kept the tap around it off every
    /// click.
    @Test(
        "A tap before a drag or a long press, inside a tap, runs both taps at every click",
        arguments: [false, true], [false, true])
    func tapBeforeDragOrLongPressInsideATap(_ longPress: Bool, _ around: Bool) {
        let log = GestureRecord()
        let harness = makeHarness()
        let tap = TapGesture().onEnded { log("tap") }
        let sequence =
            longPress
            ? AnyGesture(tap.sequenced(before: LongPressGesture()).map { _ in () })
            : AnyGesture(tap.sequenced(before: DragGesture()).map { _ in () })
        let seqBox = Text("").frame(width: 4, height: 1).gesture(sequence.onEnded { log("seq") })
        let view = {
            around
                ? AnyView(
                    HStack(spacing: 2) { seqBox; Text("").frame(width: 4, height: 1) }
                        .onTapGesture { log("outer") }
                        .frame(width: 40, height: 12, alignment: .topLeading))
                : AnyView(seqBox.onTapGesture { log("outer") }.frame(width: 40, height: 12, alignment: .topLeading))
        }
        harness.frame(view())
        harness.click(1, 0, view)
        #expect(log.entries == ["tap", "outer"])
        harness.now = 600 * gestureMillisecond
        harness.frame(view())
        harness.click(1, 0, view)
        #expect(log.entries == ["tap", "outer", "tap", "outer"])
        harness.now = 1_200 * gestureMillisecond
        harness.frame(view())
        harness.click(7, 0, view)
        let expected: [String] = ["tap", "outer", "tap", "outer"] + (around ? ["outer"] : [])
        #expect(log.entries == expected)
    }

    /// Measured on macOS 15.8: a drag before a tap ends at the drag's
    /// release — the drag's end, then the tap's, then the sequence's — and
    /// a click after it, which is no drag, ends nothing.
    @Test("A drag before a tap ends at the drag's release")
    func dragBeforeTap() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = {
            box(
                DragGesture().onEnded { log("drag ended \($0.translation.width)") }
                    .sequenced(before: TapGesture().onEnded { log("tap") })
                    .onEnded { value in
                        if case .second(let drag, let tap) = value {
                            log("seq \(drag.translation.width) \(tap != nil)")
                        }
                    })
        }
        harness.frame(view())
        harness.pointer([(.pressed, 1, 1), (.dragged, 4, 1), (.dragged, 8, 1), (.released, 8, 1)], view)
        #expect(log.entries == ["drag ended 7", "tap", "seq 7 true"])
        harness.now = 600 * gestureMillisecond
        harness.frame(view())
        harness.click(1, 1, view)
        #expect(log.entries == ["drag ended 7", "tap", "seq 7 true"])
    }

    /// Measured on macOS 15.8: a click on a long press with no minimum
    /// duration before a drag with none either ends the sequence at the
    /// release, a drag of nothing — the drag started at the press.
    @Test("A click on a zero-duration long press before a zero-distance drag ends it at the release")
    func zeroDurationThenZeroDistanceClick() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = {
            box(
                LongPressGesture(minimumDuration: 0).sequenced(before: DragGesture(minimumDistance: 0))
                    .onEnded { log("ended \(Self.describe($0))") })
        }
        harness.frame(view())
        harness.pointer([(.pressed, 1, 1)], view)
        #expect(log.entries.isEmpty)
        harness.pointer([(.released, 1, 1)], view)
        harness.now = 600 * gestureMillisecond
        harness.frame(view())
        harness.click(1, 1, view)
        #expect(log.entries == ["ended second(true, 0)", "ended second(true, 0)"])
    }

    // MARK: Exclusive

    private static func describe(_ value: ExclusiveGesture<DragGesture, LongPressGesture>.Value) -> String {
        switch value {
        case .first(let drag): "first(\(drag.translation.width))"
        case .second(let pressed): "second(\(pressed))"
        }
    }

    @Test("An exclusive gesture holds its second back until the first fails, then reports its end alone")
    func exclusiveHoldsBack() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = {
            box(
                DragGesture().exclusively(before: LongPressGesture(minimumDuration: 0.3))
                    .onChanged { log("changed \(Self.describe($0))") }
                    .onEnded { log("ended \(Self.describe($0))") })
        }
        harness.frame(view())
        harness.pointer([(.pressed, 1, 1)], view)
        harness.now = 500 * gestureMillisecond
        harness.frame(view())
        #expect(log.entries.isEmpty, "the long press has ended, but the drag may still start")
        harness.pointer([(.released, 1, 1)], view)
        #expect(log.entries == ["ended second(true)"])
    }

    @Test("An exclusive gesture holds back the callbacks inside its second, too")
    func exclusiveHoldsBackInside() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = {
            box(DragGesture().exclusively(before: LongPressGesture(minimumDuration: 0.3).onEnded { _ in log("long") }))
        }
        harness.frame(view())
        harness.pointer([(.pressed, 1, 1)], view)
        harness.now = 500 * gestureMillisecond
        harness.frame(view())
        #expect(log.entries.isEmpty)
        harness.pointer([(.released, 1, 1)], view)
        #expect(log.entries == ["long"])
    }

    @Test("An exclusive gesture's first, once it recognizes, cancels the second")
    func exclusiveFirstWins() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = {
            box(
                DragGesture().exclusively(before: LongPressGesture(minimumDuration: 0.3))
                    .onEnded { log("ended \(Self.describe($0))") })
        }
        harness.frame(view())
        harness.pointer([(.pressed, 1, 1), (.dragged, 3, 1)], view)
        harness.now = 500 * gestureMillisecond
        harness.pointer([(.released, 3, 1)], view)
        #expect(log.entries == ["ended first(2)"])
    }

    // MARK: Simultaneous

    @Test("A simultaneous gesture drops a part that failed, and ends once neither is undecided")
    func simultaneousParts() {
        let log = GestureRecord()
        let harness = makeHarness()
        let describe: (SimultaneousGesture<DragGesture, LongPressGesture>.Value) -> String = {
            "\($0.first.map { "\($0.translation.width)" } ?? "nil") \(String(describing: $0.second))"
        }
        let view = {
            box(
                DragGesture().simultaneously(with: LongPressGesture(minimumDuration: 0.3))
                    .onChanged { log("changed \(describe($0))") }
                    .onEnded { log("ended \(describe($0))") })
        }
        harness.frame(view())
        harness.pointer([(.pressed, 1, 1), (.dragged, 4, 1), (.released, 4, 1)], view)
        #expect(log.entries == ["changed nil Optional(true)", "changed 3 nil", "ended 3 nil"])
    }

    @Test("A simultaneous tap and double tap end together once the double tap gives up")
    func simultaneousWaits() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = {
            box(
                TapGesture().simultaneously(with: TapGesture(count: 2))
                    .onEnded { log("ended \($0.first != nil) \($0.second != nil)") })
        }
        harness.frame(view())
        harness.click(1, 1, view)
        #expect(log.entries.isEmpty, "the double tap may still come")
        harness.now = 400 * gestureMillisecond
        harness.frame(view())
        #expect(log.entries == ["ended true false"])
    }
}
