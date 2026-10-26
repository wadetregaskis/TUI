//  🖥️ TUI — A Terminal UI framework for Swift
//  ButtonRepeatBehaviorTests.swift
//
//  `buttonRepeatBehavior(_:)`: under `.enabled` a mouse press is the
//  activation, repeated while held; otherwise a button acts once, on the
//  release.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// Counts presses of the button under test.
private final class PressCount: @unchecked Sendable {
    var value = 0
}

@MainActor
@Suite("buttonRepeatBehavior")
struct ButtonRepeatBehaviorTests {
    /// Lets the repeat timer's first, immediate firing run.
    private static func settle() async {
        try? await Task.sleep(nanoseconds: 5_000_000)
    }

    @Test("Enabled, the press acts at once and the release adds nothing")
    func enabledActsOnThePress() async {
        let count = PressCount()
        let harness = InputChainHarness()
        harness.frame(Button("+") { count.value += 1 }.buttonRepeatBehavior(.enabled))
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 2, y: 0))
        await Self.settle()
        #expect(count.value == 1)
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 2, y: 0))
        await Self.settle()
        #expect(count.value == 1, "the hold was the activation; letting go stops it")
    }

    @Test("By default, and disabled, the button acts once on the release")
    func defaultActsOnTheRelease() async {
        for behavior in [ButtonRepeatBehavior.automatic, .disabled] {
            let count = PressCount()
            let harness = InputChainHarness()
            harness.frame(Button("+") { count.value += 1 }.buttonRepeatBehavior(behavior))
            harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 2, y: 0))
            await Self.settle()
            #expect(count.value == 0)
            harness.mouse(MouseEvent(button: .left, phase: .released, x: 2, y: 0))
            #expect(count.value == 1)
        }
    }

    @Test("The environment value reads what was set")
    func environmentValue() {
        #expect(EnvironmentValues().buttonRepeatBehavior == .automatic)
    }
}
