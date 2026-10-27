//  🖥️ TUI — A Terminal UI framework for Swift
//  ControlPressRecognizerTests.swift
//
//  A control that acts on its click takes its press as a recognizer
//  (decisions B89): a release off it fails it, it draws pressed at once
//  behind a gesture that has not decided, and a gesture attached to it hears
//  the press once it fails.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// Draws "DOWN" while the button is pressed and "up" otherwise.
private struct PressProbeStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Text(configuration.isPressed ? "DOWN" : "up")
    }
}

@MainActor
@Suite("A control's press is a recognizer")
struct ControlPressRecognizerTests {
    /// A 4×1 button at the top left of a 40×12 page, with `attach` putting
    /// gestures on it.
    private func button(_ log: GestureRecord, attach: (AnyView) -> AnyView = { $0 }) -> some View {
        attach(AnyView(Button("Press") { log("action") }.buttonStyle(PressProbeStyle())))
            .frame(width: 40, height: 12, alignment: .topLeading)
    }

    /// What the button draws in `buffer`.
    private func face(_ buffer: FrameBuffer) -> String {
        buffer.lines.first?.stripped.trimmingCharacters(in: .whitespaces) ?? ""
    }

    @Test("Released off the button, the click acts on nothing; released back over it, it acts")
    func releaseOffFails() {
        let log = GestureRecord()
        let harness = InputChainHarness()
        let view = { button(log) }
        harness.frame(view())
        harness.pointer([(.pressed, 1, 0), (.dragged, 20, 5), (.released, 20, 5)], view)
        #expect(log.entries.isEmpty)
        harness.pointer([(.pressed, 1, 0), (.dragged, 20, 5), (.dragged, 1, 0), (.released, 1, 0)], view)
        #expect(log.entries == ["action"])
    }

    @Test("The pressed look follows the pointer off the button and back")
    func pressedFollowsPointer() {
        let log = GestureRecord()
        let harness = InputChainHarness()
        let view = { button(log) }
        harness.frame(view())
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        #expect(face(harness.frame(view())) == "DOWN")
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 20, y: 5))
        #expect(face(harness.frame(view())) == "up")
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 1, y: 0))
        #expect(face(harness.frame(view())) == "DOWN")
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 20, y: 5))
        #expect(face(harness.frame(view())) == "up")
        #expect(log.entries.isEmpty)
    }

    @Test("Behind an undecided high-priority long press, the button draws pressed at once and acts once it fails")
    func pressedAtOnceBehindAGesture() {
        let log = GestureRecord()
        let harness = InputChainHarness()
        let view = {
            button(log) {
                AnyView($0.highPriorityGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in log("long") }))
            }
        }
        harness.frame(view())
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        #expect(face(harness.frame(view())) == "DOWN")
        harness.now = 100 * gestureMillisecond
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 1, y: 0))
        harness.frame(view())
        #expect(log.entries == ["action"])

        // Held past the long press's minimum: the long press wins, and the
        // button is cancelled, drawn up again, and acts on nothing.
        log.entries = []
        harness.now = 2_000 * gestureMillisecond
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        harness.frame(view())
        harness.now += 500 * gestureMillisecond
        #expect(face(harness.frame(view())) == "up")
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 1, y: 0))
        harness.frame(view())
        #expect(log.entries == ["long"])
    }

    @Test("A drag attached to a button hears the press once a release off the button fails it")
    func attachedDragAfterTheButtonFails() {
        let log = GestureRecord()
        let harness = InputChainHarness()
        let view = {
            button(log) {
                AnyView($0.gesture(
                    DragGesture().onChanged { _ in log("drag changed") }.onEnded { _ in log("drag ended") }))
            }
        }
        harness.frame(view())
        harness.pointer([(.pressed, 1, 0), (.dragged, 20, 5), (.released, 20, 5)], view)
        #expect(log.entries == ["drag ended"])

        // Released over it, the button acts, and the drag is cancelled.
        log.entries = []
        harness.pointer([(.pressed, 1, 0), (.dragged, 3, 0), (.released, 3, 0)], view)
        #expect(log.entries == ["action"])
    }

    @Test("A toggle released off it toggles nothing")
    func toggleReleaseOff() {
        final class Box { var on = false }
        let box = Box()
        let harness = InputChainHarness()
        let view = {
            Toggle("Wi-Fi", isOn: Binding(get: { box.on }, set: { box.on = $0 }))
                .frame(width: 40, height: 12, alignment: .topLeading)
        }
        harness.frame(view())
        harness.pointer([(.pressed, 1, 0), (.dragged, 30, 8), (.released, 30, 8)], view)
        #expect(!box.on)
        harness.click(1, 0, view)
        #expect(box.on)
    }
}
