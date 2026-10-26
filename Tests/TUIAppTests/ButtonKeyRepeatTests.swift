//  🖥️ TUI — A Terminal UI framework for Swift
//  ButtonKeyRepeatTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// `buttonRepeatBehavior(_:)` for a held key, which a terminal speaking the
/// kitty keyboard protocol reports as a press followed by repeats.
@MainActor
@Suite("Button repeat behavior, by keyboard")
struct ButtonKeyRepeatTests {

    private final class Count { var value = 0 }

    private static let held: [KeyEvent] = [
        KeyEvent(key: .enter), KeyEvent(key: .enter, phase: .repeat),
        KeyEvent(key: .enter, phase: .repeat), KeyEvent(key: .enter, phase: .release),
    ]

    @Test(
        "A held Return on a focused button acts once, unless repeat is enabled",
        arguments: [(ButtonRepeatBehavior.automatic, 1), (.disabled, 1), (.enabled, 3)])
    func heldReturn(behavior: ButtonRepeatBehavior, expected: Int) {
        let count = Count()
        let harness = InputChainHarness(keyboard: .requested)
        harness.play(Self.held) {
            Button("Go") { count.value += 1 }.buttonRepeatBehavior(behavior)
        }
        #expect(count.value == expected)
    }

    @Test(
        "A held shortcut acts once, unless repeat is enabled",
        arguments: [(ButtonRepeatBehavior.automatic, 1), (.disabled, 1), (.enabled, 3)])
    func heldShortcut(behavior: ButtonRepeatBehavior, expected: Int) {
        let count = Count()
        let harness = InputChainHarness(keyboard: .requested)
        let chord = { (phase: KeyEvent.Phase) in KeyEvent(key: .character("k"), ctrl: true, phase: phase) }
        harness.play([chord(.press), chord(.repeat), chord(.repeat), chord(.release)]) {
            VStack {
                Text("leaf").focusable()
                Button("Go") { count.value += 1 }
                    .keyboardShortcut("k", modifiers: .control)
                    .buttonRepeatBehavior(behavior)
            }
        }
        #expect(count.value == expected)
    }

    @Test("A repeat a focused button does not act on is still taken, and reaches no default button")
    func repeatDoesNotFallThrough() {
        let focused = Count()
        let fallback = Count()
        let harness = InputChainHarness(keyboard: .requested)
        let consumed = harness.play(Array(Self.held.prefix(2))) {
            VStack {
                Button("Focused") { focused.value += 1 }
                Button("Default") { fallback.value += 1 }.keyboardShortcut(.defaultAction)
            }
        }
        #expect(consumed == [true, true])
        #expect(focused.value == 1)
        #expect(fallback.value == 0)
    }

    @Test("In a legacy encoding every arrival is a press, and acts under every behavior")
    func legacyActsEveryTime() {
        let count = Count()
        let harness = InputChainHarness()
        harness.play([KeyEvent(key: .enter), KeyEvent(key: .enter), KeyEvent(key: .enter)]) {
            Button("Go") { count.value += 1 }.buttonRepeatBehavior(.disabled)
        }
        #expect(count.value == 3)
    }
}
