//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CompositeGestureTests.swift
//
//  The gesture algebra as measured on macOS 15.8's SwiftUI: a sequence hands
//  its second gesture the first event after the first succeeds; an exclusive
//  gesture holds its second back until the first fails; a simultaneous one
//  drops a part that failed and ends once neither is undecided.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

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

    @Test("A sequence hands its second gesture the first event after the first succeeds")
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
        #expect(log.entries == ["ended second(true, 3)"])
        harness.now = 600 * gestureMillisecond
        harness.frame(view())
        harness.pointer([(.pressed, 1, 1)], view)
        #expect(log.entries == ["ended second(true, 3)"], "the second press ends nothing")
        harness.pointer([(.dragged, 3, 1), (.dragged, 6, 1), (.released, 6, 1)], view)
        #expect(log.entries == ["ended second(true, 3)", "ended second(true, 3)"])
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
