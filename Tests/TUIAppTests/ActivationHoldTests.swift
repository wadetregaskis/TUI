//  🖥️ TUI — A Terminal UI framework for Swift
//  ActivationHoldTests.swift
//
//  What the run loop stops reading input for: a control's action, by whichever
//  route it ran, and nothing else. `Tools/Smoke/activation_batch_smoke.py` is
//  what shows the real loop doing it; `drainTerminalEvents` is reached by nothing
//  a unit test can drive.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// The rule of the hold itself, on the caller's clock.
@Suite("ActivationHold")
struct ActivationHoldTests {
    private static let limit = ActivationHold.backlogLimitNanos

    @Test("An action stops the reading, until a frame has drawn it")
    func holdsUntilAFrame() {
        var hold = ActivationHold()
        #expect(!hold.isHolding)
        let stopped = hold.actionRan(atNanos: 1_000)
        #expect(stopped)
        #expect(hold.isHolding)
        // The frame was the hold's: what is behind it is read at once.
        let waited = hold.frameDrawn()
        #expect(waited)
        #expect(!hold.isHolding)
        // Any other frame was nobody's.
        let waitedAgain = hold.frameDrawn()
        #expect(!waitedAgain)
    }

    @Test("Actions behind one another each stop, until the reading has been behind too long")
    func stopsWhileBehindIsShort() {
        var hold = ActivationHold()
        let first = hold.actionRan(atNanos: 1_000)
        hold.frameDrawn()
        let atTheLimit = hold.actionRan(atNanos: 1_000 + Self.limit)
        hold.frameDrawn()
        let pastIt = hold.actionRan(atNanos: 1_000 + Self.limit + 1)
        let isHolding = hold.isHolding
        // And the rest of the backlog goes through as a batch did.
        let further = hold.actionRan(atNanos: 1_000 + Self.limit + 2)
        #expect(first && atTheLimit)
        #expect(!pastIt && !isHolding && !further)
    }

    @Test("Reading everything waiting starts the count again")
    func caughtUpStartsAgain() {
        var hold = ActivationHold()
        _ = hold.actionRan(atNanos: 1_000)
        hold.frameDrawn()
        hold.readEverything()
        let muchLater = 1_000 + 100 * Self.limit
        let afresh = hold.actionRan(atNanos: muchLater)
        hold.frameDrawn()
        let stillInLimit = hold.actionRan(atNanos: muchLater + Self.limit)
        #expect(afresh && stillInLimit)
    }

    /// A held key at 30 presses a second, with a frame of `frameNanos`: every
    /// press runs, and the last within a bound of the release, a press read only
    /// when the loop is reading. The loop's own order, as `runLoop` plays it.
    private func held(frameNanos: UInt64) -> (ran: Int, lateNanos: UInt64) {
        let repeatNanos: UInt64 = 33_000_000
        let presses = 90
        var hold = ActivationHold()
        var now: UInt64 = 1_000
        var read = 0
        var lastRan = now
        func arrived(by time: UInt64) -> Int { min(presses, Int((time - 1_000) / repeatNanos) + 1) }
        while read < presses {
            guard read < arrived(by: now) else {
                // Nothing waiting: the drain found the end, and the loop sleeps
                // until the next press.
                hold.readEverything()
                now = 1_000 + UInt64(read) * repeatNanos
                continue
            }
            read += 1
            lastRan = now
            if hold.actionRan(atNanos: now) {
                now += frameNanos
                hold.frameDrawn()
            }
        }
        return (read, lastRan - (1_000 + UInt64(presses - 1) * repeatNanos))
    }

    @Test("A held key keeps up, on frames faster than its repeat")
    func heldOnFastFrames() {
        let (ran, late) = held(frameNanos: 16_700_000)
        #expect(ran == 90)
        #expect(late == 0)
    }

    @Test(
        "A held key on frames slower than its repeat is never far behind its last press",
        arguments: [100_000_000 as UInt64, 400_000_000, 2_000_000_000])
    func heldOnSlowFrames(frameNanos: UInt64) {
        let (ran, late) = held(frameNanos: frameNanos)
        #expect(ran == 90)
        // Without the limit every press would take a frame, so ninety of them at
        // 100 ms a frame end some six seconds after the last arrives.
        #expect(late <= Self.limit + frameNanos)
    }
}

/// Which routes count, marked where a control runs its action.
@MainActor
@Suite("What counts as an activation")
struct ActivationMarkTests {
    private final class Count { var value = 0 }

    /// Plays `events` against `view` in an app's work, and reports whether the
    /// last of them ran an action. The frames before each are `play`'s.
    private func activates<V: View>(
        _ events: [KeyEvent] = [], clickAt click: (x: Int, y: Int)? = nil, keyboard: KittyKeyboardFlags = [],
        @ViewBuilder _ view: () -> V
    ) -> Bool {
        let appState = AppState()
        let harness = InputChainHarness(keyboard: keyboard)
        return AmbientApp.$renderState.withValue(appState) {
            harness.frame(view())
            harness.frame(view())
            _ = appState.consumeControlActivated()
            for event in events { harness.press(event) }
            if let click {
                harness.mouse(MouseEvent(button: .left, phase: .pressed, x: click.x, y: click.y))
                harness.mouse(MouseEvent(button: .left, phase: .released, x: click.x, y: click.y))
            }
            return appState.consumeControlActivated()
        }
    }

    @Test("Return and Space on a focused button", arguments: [Key.enter, .space])
    func buttonKeys(key: Key) {
        #expect(activates([KeyEvent(key: key)]) { Button("Go") {} })
    }

    @Test("A click on a button")
    func buttonClick() {
        #expect(activates(clickAt: (2, 0)) { Button("Go") {} })
    }

    @Test("A keyboard shortcut")
    func shortcut() {
        #expect(
            activates([KeyEvent(key: .character("k"), ctrl: true)]) {
                VStack {
                    Text("leaf").focusable()
                    Button("Go") {}.keyboardShortcut("k", modifiers: .control)
                }
            })
    }

    @Test("A button of a primitive style, whose body triggers it")
    func primitiveStyle() {
        struct Plainly: PrimitiveButtonStyle {
            func makeBody(configuration: Configuration) -> some View { Button(configuration) }
        }
        #expect(activates([KeyEvent(key: .enter)]) { Button("Go") {}.buttonStyle(Plainly()) })
    }

    @Test("A toggle, by Space, by a click and by a shortcut")
    func toggle() {
        let isOn = Count()
        let binding = Binding(get: { isOn.value == 1 }, set: { isOn.value = $0 ? 1 : 0 })
        #expect(activates([KeyEvent(key: .space)]) { Toggle("On", isOn: binding) })
        #expect(activates(clickAt: (1, 0)) { Toggle("On", isOn: binding) })
        #expect(
            activates([KeyEvent(key: .character("k"), ctrl: true)]) {
                Toggle("On", isOn: binding).keyboardShortcut("k", modifiers: .control)
            })
    }

    @Test("A tap")
    func tap() {
        #expect(activates(clickAt: (1, 0)) { Text("Go").onTapGesture {} })
    }

    @Test("A Link, whose button runs it")
    func link() {
        #expect(
            activates([KeyEvent(key: .enter)]) {
                Link("Go", destination: URL(string: "https://example.com")!)
                    .environment(\.openURL, OpenURLAction { _ in .handled })
            })
    }

    @Test("A link in a Text")
    func textLink() {
        #expect(
            activates([KeyEvent(key: .enter)]) {
                Text("[Go](https://example.com)")
                    .environment(\.openURL, OpenURLAction { _ in .handled })
            })
    }

    @Test("A status-bar item's action, and not an item that only names a key")
    func statusBarItem() {
        let appState = AppState()
        AmbientApp.$renderState.withValue(appState) {
            StatusBarItem(shortcut: "h", label: "help", key: .character("h"), action: {}).execute()
            #expect(appState.consumeControlActivated())
            StatusBarItem(shortcut: "h", label: "help", key: .character("h")).execute()
            #expect(!appState.consumeControlActivated())
        }
    }

    @Test("A press that runs nothing does not count")
    func nothingRan() {
        // A key no one takes.
        #expect(!activates([KeyEvent(key: .character("z"))]) { Button("Go") {} })
        // A disabled button: not registered, so nothing to run.
        #expect(!activates([KeyEvent(key: .enter)]) { Button("Go") {}.disabled(true) })
        #expect(!activates(clickAt: (2, 0)) { Button("Go") {}.disabled(true) })
        // A repeat the button declines: a held key at one action.
        #expect(
            !activates([KeyEvent(key: .enter, phase: .repeat)], keyboard: .requested) {
                Button("Go") {}.buttonRepeatBehavior(.disabled)
            })
    }

    @Test("Moving the focus does not count")
    func focusMoves() {
        #expect(
            !activates([KeyEvent(key: .tab)]) {
                VStack {
                    Button("One") {}
                    Button("Two") {}
                }
            })
    }

    @Test("With no app's work under way, an action runs and notes nothing")
    func noAmbientApp() {
        let count = Count()
        let harness = InputChainHarness()
        harness.play([KeyEvent(key: .enter)]) { Button("Go") { count.value += 1 } }
        #expect(count.value == 1)
    }
}
