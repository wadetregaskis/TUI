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

    @Test("A gesture's region leaves the pointer's hover to the control behind it")
    func controlBehindKeepsItsHover() {
        let harness = makeHarness()
        harness.tui.mouseEventDispatcher.setActiveSupport(.full)
        let view = {
            Button("Press") {}
                .overlay(alignment: .topLeading) { Text("").frame(width: 1, height: 1).onTapGesture {} }
                .frame(width: 40, height: 12, alignment: .topLeading)
        }
        let resting = harness.frame(view())
        harness.mouse(MouseEvent(button: .none, phase: .moved, x: 0, y: 0))
        let hovered = harness.frame(view())
        // The tap's region is in front of the button's, but on the hover
        // observers' lane: were it an ordinary region, the pointer would
        // resolve to it, and the button under it would never light.
        #expect(hovered.lines[0] != resting.lines[0], "the gesture's region took the button's hover")
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

    /// Plays `clicks` — each a press and a release at one instant, the run
    /// loop's frame after each — into a double tap ahead of a single tap,
    /// spelt `form`, then a frame at `end`; returns what ran.
    private func play(_ form: DoubleThenSingle, clicks: [Int64], end: Int64) -> [String] {
        let log = GestureRecord()
        let harness = makeHarness()
        let view = { form.view(log) }
        harness.frame(view())
        for time in clicks {
            harness.now = time * gestureMillisecond
            harness.frame(view())
            harness.click(2, 1, view)
        }
        harness.now = end * gestureMillisecond
        harness.frame(view())
        return log.entries
    }

    /// Measured on macOS 15.8 in all three spellings: a single tap behind a
    /// double tap runs for each click the double tap gives up on, however many
    /// came before. It ran for the first only — the recognizer marked its
    /// action run, and the mark was cleared only by a click it was allowed to
    /// report, which a tap held back behind the double never is.
    @Test("A single tap behind a double tap runs for every lone click, not just the first", arguments: DoubleThenSingle.allCases)
    func singleAfterSingle(_ form: DoubleThenSingle) {
        #expect(play(form, clicks: [0, 1_000, 2_000], end: 3_000) == ["single", "single", "single"])
    }

    @Test("Between lone clicks a double click still runs the double tap alone", arguments: DoubleThenSingle.allCases)
    func doubleAmongSingles(_ form: DoubleThenSingle) {
        #expect(play(form, clicks: [0, 1_000, 1_150, 2_500], end: 3_500) == ["single", "double", "single"])
        #expect(play(form, clicks: [0, 150, 1_000], end: 2_000) == ["double", "single"])
    }

    /// Measured on macOS 15.8 in all three spellings: a click, then a second
    /// click that gives the double tap up — its press held past the
    /// double-tap interval, or strayed past the slop — runs the single tap
    /// once, for the FIRST click, the moment the double tap gives up. The
    /// second click runs nothing, even one short enough to be a tap: the
    /// single tap is waiting with the first click recognized, and does not
    /// start over at the second press. A third click is a click of its own.
    @Test("When the second click gives the double tap up, the single tap runs once, for the first", arguments: DoubleThenSingle.allCases)
    func secondClickFailsTheDouble(_ form: DoubleThenSingle) {
        let held = GestureRecord()
        var harness = makeHarness()
        var view = { form.view(held) }
        harness.frame(view())
        harness.click(2, 1, view)
        harness.now = 150 * gestureMillisecond
        harness.frame(view())
        harness.pointer([(.pressed, 2, 1)], view)
        harness.now = 360 * gestureMillisecond
        harness.frame(view())
        #expect(held.entries == ["single"], "held: when the double tap gives up, the button still down")
        harness.now = 400 * gestureMillisecond
        harness.frame(view())
        harness.pointer([(.released, 2, 1)], view)  // 250 ms: short enough to tap
        harness.now = 1_500 * gestureMillisecond
        harness.frame(view())
        #expect(held.entries == ["single"], "held: the second click is no tap of its own")

        let strayed = GestureRecord()
        harness = makeHarness()
        view = { form.view(strayed) }
        harness.frame(view())
        harness.click(2, 1, view)
        harness.now = 150 * gestureMillisecond
        harness.frame(view())
        harness.pointer([(.pressed, 2, 1), (.dragged, 9, 1)], view)
        #expect(strayed.entries == ["single"], "strayed: when the move gives the double tap up")
        harness.pointer([(.released, 9, 1)], view)
        harness.now = 300 * gestureMillisecond
        harness.frame(view())
        harness.click(2, 1, view)
        harness.now = 1_500 * gestureMillisecond
        harness.frame(view())
        #expect(strayed.entries == ["single", "single"], "strayed: the third click taps on its own")
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

/// The three ways to put a double tap ahead of a single tap, which macOS
/// treats alike (measured on macOS 15.8).
enum DoubleThenSingle: String, CaseIterable, Sendable, CustomTestStringConvertible {
    /// `.gesture(TapGesture(count: 2)…).gesture(TapGesture()…)`
    case gestures
    /// `.onTapGesture(count: 2) {…}.onTapGesture {…}`
    case onTapGestures
    /// `TapGesture(count: 2).exclusively(before: TapGesture())`
    case exclusive

    var testDescription: String { rawValue }

    /// A 10×3 box at the top-left of a larger page, holding the taps.
    @MainActor
    func view(_ log: GestureRecord) -> some View {
        let box = Text("").frame(width: 10, height: 3)
        let attached: AnyView =
            switch self {
            case .gestures:
                AnyView(
                    box.gesture(TapGesture(count: 2).onEnded { log("double") })
                        .gesture(TapGesture().onEnded { log("single") }))
            case .onTapGestures:
                AnyView(box.onTapGesture(count: 2) { log("double") }.onTapGesture { log("single") })
            case .exclusive:
                AnyView(
                    box.gesture(
                        TapGesture(count: 2).onEnded { log("double") }
                            .exclusively(before: TapGesture().onEnded { log("single") })))
            }
        return attached.frame(width: 40, height: 12, alignment: .topLeading)
    }
}

/// A tap gesture of one type for every case, so the cases can share a builder.
struct ParentTap {
    let gesture: _EndedGesture<TapGesture>

    init(_ gesture: _EndedGesture<TapGesture>) {
        self.gesture = gesture
    }
}
