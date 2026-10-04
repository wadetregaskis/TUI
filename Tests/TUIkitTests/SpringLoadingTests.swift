//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SpringLoadingTests.swift
//
//  SwiftUI's spring loading: a drag held still over a spring-loaded control
//  for half a second activates it, and the drag carries on. Which controls
//  spring-load under which behavior is what macOS 15.8 does (measured): a
//  button only under `.enabled`, a tab unless `.disabled`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// How many times something was activated.
private final class Count: @unchecked Sendable {
    var value = 0
}

@MainActor
@Suite("Spring loading: a paused drag activates the control under it")
struct SpringLoadingTests {
    private static let delay = Int64(DragAndDropSession.SpringLoading.delayNanos)

    /// A draggable chip on row 0 and a button on row 3.
    private func page(_ count: Count, button behavior: SpringLoadingBehavior, outer: SpringLoadingBehavior = .automatic)
        -> some View
    {
        VStack(alignment: .leading, spacing: 0) {
            Text("CHIP").draggable("apple")
            Text("").frame(height: 2)
            Button("GO") { count.value += 1 }
                .springLoadingBehavior(behavior)
        }
        .springLoadingBehavior(outer)
    }

    /// Picks the chip up and carries it to `(x, 3)`, over the button, a frame
    /// after each event as the run loop draws one.
    private func carry(_ harness: InputChainHarness, to x: Int = 1, _ build: () -> some View) {
        harness.frame(build())
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 2, y: 1))
        harness.frame(build())
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: x, y: 3))
        harness.frame(build())
    }

    /// One turn of the run loop's spring-loading drive, at `nanos`, then the
    /// frame it would draw.
    @discardableResult
    private func drive(_ harness: InputChainHarness, at nanos: Int64, _ build: () -> some View) -> Int64? {
        let deadline = harness.tui.dragAndDropSession.driveSpringLoading(nowNanos: UInt64(nanos))
        harness.now = nanos
        harness.frame(build())
        return deadline.map { Int64($0) }
    }

    @Test("Under .enabled, half a second's pause presses the button once, and the drag carries on")
    func enabledButtonIsPressedByAPause() {
        let count = Count()
        let harness = InputChainHarness(width: 30, height: 8)
        let build = { page(count, button: .enabled) }
        carry(harness, build)
        #expect(drive(harness, at: 0, build) == Self.delay, "the pause asks for a frame when it will have lasted")
        #expect(drive(harness, at: Self.delay - 1, build) == Self.delay)
        #expect(count.value == 0, "not before the delay")
        #expect(drive(harness, at: Self.delay, build) == nil)
        #expect(count.value == 1, "pressed once the pause lasted the delay")
        #expect(harness.tui.dragAndDropSession.active != nil, "the drag is still in the hand")
        drive(harness, at: 4 * Self.delay, build)
        #expect(count.value == 1, "once per arrival: resting on longer does not press it again")
    }

    @Test("Under .automatic a button is not spring-loaded, as on macOS")
    func automaticButtonIsNot() {
        let count = Count()
        let harness = InputChainHarness(width: 30, height: 8)
        let build = { page(count, button: .automatic) }
        carry(harness, build)
        #expect(drive(harness, at: 0, build) == nil, "nothing to wait for")
        drive(harness, at: 4 * Self.delay, build)
        #expect(count.value == 0)
    }

    @Test("An inner .enabled overrides an outer .disabled, rather than being unioned with it")
    func innerOverridesOuter() {
        let count = Count()
        let harness = InputChainHarness(width: 30, height: 8)
        let build = { page(count, button: .enabled, outer: .disabled) }
        carry(harness, build)
        drive(harness, at: 0, build)
        drive(harness, at: Self.delay, build)
        #expect(count.value == 1)
    }

    @Test("Moving to another cell is not a pause: the clock starts again")
    func movingRestartsThePause() {
        let count = Count()
        let harness = InputChainHarness(width: 30, height: 8)
        let build = { page(count, button: .enabled) }
        carry(harness, to: 1, build)
        drive(harness, at: 0, build)
        drive(harness, at: Self.delay * 4 / 5, build)
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 2, y: 3))
        #expect(drive(harness, at: Self.delay, build) == Self.delay + Self.delay)
        #expect(count.value == 0, "the move restarted the pause")
        drive(harness, at: 2 * Self.delay, build)
        #expect(count.value == 1)
    }

    @Test("Leaving the button and coming back presses it again")
    func leavingRearms() {
        let count = Count()
        let harness = InputChainHarness(width: 30, height: 8)
        let build = { page(count, button: .enabled) }
        carry(harness, build)
        drive(harness, at: 0, build)
        drive(harness, at: Self.delay, build)
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 1, y: 1))
        drive(harness, at: Self.delay + 1, build)
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 1, y: 3))
        drive(harness, at: Self.delay + 2, build)
        drive(harness, at: 2 * Self.delay + 2, build)
        #expect(count.value == 2)
    }

    @Test("The view being carried is never pressed by a pause over its own place")
    func theCarriedViewIsNot() {
        let count = Count()
        let harness = InputChainHarness(width: 30, height: 8)
        let build = {
            Button("GO") { count.value += 1 }
                .draggable("apple")
                .springLoadingBehavior(.enabled)
        }
        harness.frame(build())
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 2, y: 0))
        harness.frame(build())
        drive(harness, at: 0, build)
        drive(harness, at: 4 * Self.delay, build)
        #expect(harness.tui.dragAndDropSession.active != nil)
        #expect(count.value == 0)
    }

    @Test("A pause with no drag in flight does nothing")
    func noDragNoSpringLoading() {
        let count = Count()
        let harness = InputChainHarness(width: 30, height: 8)
        let build = { page(count, button: .enabled) }
        harness.frame(build())
        harness.mouse(MouseEvent(button: .none, phase: .moved, x: 1, y: 3))
        harness.frame(build())
        #expect(drive(harness, at: 0, build) == nil)
        drive(harness, at: 4 * Self.delay, build)
        #expect(count.value == 0)
    }

    @Test("A disclosure group under .enabled opens on a pause, and does not shut on the next")
    func disclosureOpensOnAPause() {
        let open = Count()
        let harness = InputChainHarness(width: 30, height: 8)
        let isExpanded = Binding(get: { open.value == 1 }, set: { open.value = $0 ? 1 : 0 })
        let build = {
            VStack(alignment: .leading, spacing: 0) {
                Text("CHIP").draggable("apple")
                Text("").frame(height: 2)
                DisclosureGroup("More", isExpanded: isExpanded) { Text("inside") }
                    .springLoadingBehavior(.enabled)
            }
        }
        carry(harness, to: 4, build)
        drive(harness, at: 0, build)
        drive(harness, at: Self.delay, build)
        #expect(open.value == 1, "the pause opened it")
        drive(harness, at: 4 * Self.delay, build)
        #expect(open.value == 1, "and resting on did not shut it again")
    }

    /// A toggle on row 3, under `.enabled`, drawn as a button or a checkbox.
    private func togglePage(_ on: Count, asButton: Bool) -> some View {
        let isOn = Binding(get: { on.value == 1 }, set: { on.value = $0 ? 1 : 0 })
        return VStack(alignment: .leading, spacing: 0) {
            Text("CHIP").draggable("apple")
            Text("").frame(height: 2)
            if asButton {
                Toggle("Flag", isOn: isOn).toggleStyle(.button)
            } else {
                Toggle("Flag", isOn: isOn).toggleStyle(.checkbox)
            }
        }
        .springLoadingBehavior(.enabled)
    }

    @Test("A .button toggle flips on a pause under .enabled; a checkbox never does, as on macOS")
    func buttonToggleFlipsCheckboxDoesNot() {
        for asButton in [true, false] {
            let on = Count()
            let harness = InputChainHarness(width: 30, height: 8)
            let build = { togglePage(on, asButton: asButton) }
            carry(harness, to: 2, build)
            drive(harness, at: 0, build)
            drive(harness, at: Self.delay, build)
            #expect(on.value == (asButton ? 1 : 0), "as a button: \(asButton)")
        }
    }

    @Test("Mid-drag the keyboard presses the focused button without a pause, and the drag carries on")
    func keyboardPressesWithoutAPause() {
        let count = Count()
        let harness = InputChainHarness(width: 30, height: 8)
        let build = { page(count, button: .automatic) }
        carry(harness, build)
        harness.press(KeyEvent(key: .tab))
        harness.frame(build())
        harness.press(KeyEvent(key: .enter))
        harness.frame(build())
        #expect(count.value == 1, "Tab reached the button and Return pressed it")
        #expect(harness.tui.dragAndDropSession.active != nil, "the drag is still in the hand")
    }
}
