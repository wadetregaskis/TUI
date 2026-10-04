//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GestureArbitrationTests.swift
//
//  Which gesture gets a click when several are under it, as measured on
//  macOS 15.8's SwiftUI: a view's own gestures (its subviews', a control's
//  press) before one attached with `gesture`, one attached with
//  `highPriorityGesture` before them, one attached with `simultaneousGesture`
//  beside them; and the masks that switch either side off.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Gesture arbitration")
struct GestureArbitrationTests {
    private func makeHarness() -> InputChainHarness {
        let harness = InputChainHarness()
        harness.syncEventClock()
        return harness
    }

    /// A 10×6 stack: a 10×3 child with its own tap on top, a plain 10×3 area
    /// below, and `attach` putting the parent's gesture on the stack.
    private func parentAndChild(
        _ log: GestureRecord, attach: (AnyView, ParentTap) -> AnyView
    ) -> some View {
        let child = Text("").frame(width: 10, height: 3).gesture(TapGesture().onEnded { log("child") })
        let stack = AnyView(VStack(spacing: 0) {
            child
            Text("").frame(width: 10, height: 3)
        })
        return attach(stack, ParentTap(TapGesture().onEnded { log("parent") }))
            .frame(width: 40, height: 12, alignment: .topLeading)
    }

    /// Clicks the child, then the plain area, and reports what ran.
    private func clicks(_ attach: @escaping (AnyView, ParentTap) -> AnyView) -> (child: [String], sibling: [String]) {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { parentAndChild(log, attach: attach) }
        harness.frame(view())
        harness.click(2, 1, view)
        let child = log.entries
        log.entries = []
        harness.now = 1_000 * gestureMillisecond
        harness.frame(view())
        harness.click(2, 4, view)
        return (child, log.entries)
    }

    @Test("A child's gesture comes before one attached with gesture(_:)")
    func childBeforeParent() {
        let result = clicks { AnyView($0.gesture($1.gesture)) }
        #expect(result.child == ["child"])
        #expect(result.sibling == ["parent"])
    }

    @Test("highPriorityGesture comes before the child's")
    func highPriority() {
        let result = clicks { AnyView($0.highPriorityGesture($1.gesture)) }
        #expect(result.child == ["parent"])
        #expect(result.sibling == ["parent"])
    }

    @Test("simultaneousGesture runs beside the child's, and first")
    func simultaneous() {
        let result = clicks { AnyView($0.simultaneousGesture($1.gesture)) }
        #expect(result.child == ["parent", "child"])
        #expect(result.sibling == ["parent"])
    }

    @Test("The masks switch the gesture or its subviews' gestures off")
    func masks() {
        let gestureOnly = clicks { AnyView($0.gesture($1.gesture, including: .gesture)) }
        #expect(gestureOnly.child == ["parent"], ".gesture: the child's is off")
        let subviewsOnly = clicks { AnyView($0.gesture($1.gesture, including: .subviews)) }
        #expect(subviewsOnly.child == ["child"])
        #expect(subviewsOnly.sibling.isEmpty, ".subviews: the parent's is off")
        let none = clicks { AnyView($0.gesture($1.gesture, including: .none)) }
        #expect(none.child.isEmpty && none.sibling.isEmpty, ".none: both are off")
        let disabled = clicks { AnyView($0.highPriorityGesture($1.gesture, isEnabled: false)) }
        #expect(disabled.child == ["child"] && disabled.sibling.isEmpty, "isEnabled: false is .subviews")
    }

    // MARK: - A button's own press

    private func button(_ log: GestureRecord, attach: (AnyView) -> AnyView) -> some View {
        attach(AnyView(Button("Press") { log("action") }))
            .frame(width: 40, height: 12, alignment: .topLeading)
    }

    private func clickButton(_ attach: @escaping (AnyView) -> AnyView, drag: Bool = false) -> [String] {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { button(log, attach: attach) }
        harness.frame(view())
        if drag {
            harness.pointer([(.pressed, 1, 0), (.dragged, 3, 0), (.released, 3, 0)], view)
        } else {
            harness.click(1, 0, view)
        }
        return log.entries
    }

    @Test("A button's press comes before gesture(_:) and onTapGesture-like taps attached to it")
    func buttonBeforeAttached() {
        #expect(clickButton { AnyView($0.gesture(TapGesture().onEnded { _ in })) } == ["action"])
        let log = GestureRecord()
        #expect(clickButton { AnyView($0.gesture(TapGesture().onEnded { log("tap") })) } == ["action"])
        #expect(log.entries.isEmpty)
    }

    @Test("A high-priority tap takes a button's click; a simultaneous one shares it, first")
    func buttonHighAndSimultaneous() {
        let high = GestureRecord()
        let highResult = clickButton { AnyView($0.highPriorityGesture(TapGesture().onEnded { high("tap") })) }
        #expect(high.entries == ["tap"])
        #expect(!highResult.contains("action"))

        let both = GestureRecord()
        let view = { button(both) { AnyView($0.simultaneousGesture(TapGesture().onEnded { both("tap") })) } }
        let harness = makeHarness()
        harness.frame(view())
        harness.click(1, 0, view)
        #expect(both.entries == ["tap", "action"])
    }

    @Test("A high-priority drag lets a click through to a button and takes a drag from it")
    func buttonHighDrag() {
        let log = GestureRecord()
        let attach: (AnyView) -> AnyView = {
            AnyView($0.highPriorityGesture(
                DragGesture().onChanged { _ in log("drag changed") }.onEnded { _ in log("drag ended") }))
        }
        let clicked = clickButton(attach)
        #expect(clicked == ["action"])
        #expect(log.entries.isEmpty)
        let dragged = clickButton(attach, drag: true)
        #expect(!dragged.contains("action"))
        #expect(log.entries == ["drag changed", "drag ended"])
    }

    // MARK: - Taps that wait

    @Test("A double tap inside a single tap holds the single tap until the double-tap interval passes")
    func doubleBeforeSingle() {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = {
            Text("").frame(width: 10, height: 3)
                .gesture(TapGesture(count: 2).onEnded { log("double") })
                .gesture(TapGesture().onEnded { log("single") })
                .frame(width: 40, height: 12, alignment: .topLeading)
        }
        harness.frame(view())
        harness.click(2, 1, view)
        #expect(log.entries.isEmpty, "held: the double tap may still come")
        harness.now = 360 * gestureMillisecond
        harness.frame(view())
        #expect(log.entries == ["single"], "the double tap gave up after 0.35 s")

        log.entries = []
        harness.now = 2_000 * gestureMillisecond
        harness.frame(view())
        harness.click(2, 1, view)
        harness.now = 2_150 * gestureMillisecond
        harness.frame(view())
        harness.click(2, 1, view)
        harness.now = 3_000 * gestureMillisecond
        harness.frame(view())
        #expect(log.entries == ["double"], "a double-click runs the double tap alone")
    }

    @Test("A long press inside a tap: held, the press wins; clicked, the tap")
    func longPressBeforeTap() {
        for (hold, expected) in [(Int64(600), ["long"]), (Int64(20), ["tap"])] {
            let log = GestureRecord()
            let harness = makeHarness()
            let view = {
                Text("").frame(width: 10, height: 3)
                    .gesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in log("long") })
                    .gesture(TapGesture().onEnded { log("tap") })
                    .frame(width: 40, height: 12, alignment: .topLeading)
            }
            harness.frame(view())
            harness.pointer([(.pressed, 2, 1)], view)
            harness.now = hold * gestureMillisecond
            harness.frame(view())
            harness.pointer([(.released, 2, 1)], view)
            #expect(log.entries == expected, "held \(hold) ms")
        }
    }
}

/// A tap gesture of one type for every case, so the cases can share a builder.
struct ParentTap {
    let gesture: _EndedGesture<TapGesture>

    init(_ gesture: _EndedGesture<TapGesture>) {
        self.gesture = gesture
    }
}
