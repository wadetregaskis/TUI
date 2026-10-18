//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GestureAdaptorTests.swift
//
//  The gesture adaptors: `modifiers(_:)`, read at the press and satisfied by
//  a superset of the keys (measured on macOS 15.8), and `map(_:)`.
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
@Suite("Gesture adaptors")
struct GestureAdaptorTests {
    private func makeHarness() -> InputChainHarness {
        InputChainHarness()
    }

    private func box(_ gesture: some Gesture) -> some View {
        Text("").frame(width: 10, height: 3).gesture(gesture).frame(width: 40, height: 12, alignment: .topLeading)
    }

    @Test("modifiers(_:) admits a press with the keys asked for, or more")
    func modifiersGate() {
        for (shift, ctrl, taps) in [(false, false, 0), (true, false, 1), (true, true, 1), (false, true, 0)] {
            let log = GestureRecord()
            let harness = makeHarness()
            let view = { box(TapGesture().modifiers(.shift).onEnded { log("tap") }) }
            harness.frame(view())
            harness.pointer([(.pressed, 1, 1), (.released, 1, 1)], modifiers: (shift, ctrl, false), view)
            #expect(log.entries.count == taps, "shift \(shift) control \(ctrl)")
        }
    }

    @Test("modifiers(_:) reads the keys at the press: letting go mid-drag does not stop the gesture")
    func modifiersReadAtPress() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { box(DragGesture().modifiers(.option).onEnded { log("ended \($0.translation.width)") }) }
        harness.frame(view())
        harness.pointer([(.pressed, 1, 1)], modifiers: (false, false, true), view)
        harness.pointer([(.dragged, 4, 1), (.released, 4, 1)], view)
        #expect(log.entries == ["ended 3"])
    }

    /// Pinned at the recognizer, where holding back is explicit: input fed
    /// with delivery off is held, and `flush()` reports the state it left. A
    /// gesture that ended while held, then a new one whose first value equals
    /// the last one's, was flushed as no change. The arena reaches this only
    /// through a recognizer kept waiting across presses — a sequence behind a
    /// double tap whose next press lands before the frame that would have
    /// failed it — so a scripted view would pin the arena's timing, not this.
    @Test("onChanged reports a held-back gesture's first value even when it equals the last gesture's last")
    func changedAfterHeldBackEnd() {
        let log = GestureRecord()
        let press = LongPressGestureNode()
        press.minimumDuration = 1
        let node = ChangedGestureNode<Bool>()
        node.child = press
        node.action = { log("changed \($0)") }
        func pointer(_ kind: GesturePointer.Kind) -> GestureInput {
            .pointer(
                GesturePointer(
                    kind: kind, location: .zero, globalLocation: .zero, modifiers: [], timeNanos: 0, isInside: true))
        }
        node.receive(pointer(.down), deliver: true)
        #expect(log.entries == ["changed true"])
        node.receive(pointer(.up), deliver: false)  // released early: the press fails, held back
        node.receive(pointer(.down), deliver: false)  // the next press: `true` again, held back
        node.flush()
        #expect(log.entries == ["changed true", "changed true"])
    }

    /// Measured on macOS 15.8: a long press with no minimum duration ends at
    /// each press, so three clicks run its action three times, in every
    /// spelling. It goes from one end straight to the next, never through a
    /// phase that is not an end, which is what the action's "already run"
    /// mark was re-armed by: only the first press ran it.
    @Test("A long press with no minimum duration runs its action at every press")
    func zeroDurationLongPressEveryPress() {
        let spellings: [(String, (GestureRecord) -> AnyView)] = [
            ("onLongPressGesture", { log in AnyView(Text("").frame(width: 10, height: 3).onLongPressGesture(minimumDuration: 0) { log("long") }) }),
            ("onEnded", { log in AnyView(box(LongPressGesture(minimumDuration: 0).onEnded { _ in log("long") })) }),
        ]
        for (name, view) in spellings {
            let log = GestureRecord()
            let harness = makeHarness()
            harness.frame(view(log))
            for time in [Int64(0), 600, 1_200] {
                harness.now = time * gestureMillisecond
                harness.frame(view(log))
                harness.click(1, 1) { view(log) }
            }
            #expect(log.entries == ["long", "long", "long"], "\(name)")
        }
    }

    /// Measured on macOS 15.8: two zero-duration long presses together end
    /// at the press and run the action once, and the release runs nothing
    /// more. The combination reports again at every input, so the action is
    /// keyed on the press that begins a gesture, not on a new report.
    @Test("Two zero-duration long presses together run the action once a press, not again at the release")
    func zeroDurationPairOncePerPress() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = {
            box(
                LongPressGesture(minimumDuration: 0).simultaneously(with: LongPressGesture(minimumDuration: 0))
                    .onEnded { _ in log("pair") })
        }
        harness.frame(view())
        harness.pointer([(.pressed, 1, 1)], view)
        #expect(log.entries == ["pair"], "at the press")
        harness.now = 300 * gestureMillisecond
        harness.frame(view())
        harness.pointer([(.released, 1, 1)], view)
        #expect(log.entries == ["pair"], "the release runs nothing more")
        harness.now = 900 * gestureMillisecond
        harness.frame(view())
        harness.click(1, 1, view)
        #expect(log.entries == ["pair", "pair"])
    }

    @Test("map(_:) transforms the gesture's value")
    func map() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { box(TapGesture().map { "mapped" }.onEnded { log($0) }) }
        harness.frame(view())
        harness.click(1, 1, view)
        #expect(log.entries == ["mapped"])
    }
}
