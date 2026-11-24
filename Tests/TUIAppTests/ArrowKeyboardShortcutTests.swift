//  🖥️ TUI — A Terminal UI framework for Swift
//  ArrowKeyboardShortcutTests.swift
//
//  An app's `.keyboardShortcut` on an arrow takes the key before the focus
//  system moves the focus with it, bare or with any modifier, Shift included
//  (the owner's ruling O-11 (a), 2026-11-21; hunt FOCUS-3). The focused
//  control still has the arrow first, as it has every key.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting

/// How many times the actions under test ran.
private final class Count: @unchecked Sendable {
    var value = 0
}

@MainActor
@Suite("Keyboard shortcuts on the arrow keys")
struct ArrowKeyboardShortcutTests {

    /// The shortcut's modifiers, and the key the terminal sends for it under
    /// the default `.commandKey(.control)`.
    nonisolated static let chords: [(EventModifiers, KeyEvent)] = [
        (.command, KeyEvent(key: .right, ctrl: true)),
        (.shift, KeyEvent(key: .right, shift: true)),
        (.option, KeyEvent(key: .right, alt: true)),
        ([], KeyEvent(key: .right)),
    ]

    @Test(
        "A shortcut on an arrow fires, and the focus stays where it was",
        arguments: chords.indices)
    func arrowShortcutFires(index: Int) {
        let (modifiers, event) = Self.chords[index]
        let next = Count()
        let app = TestApp(width: 40, height: 6) {
            VStack {
                Button("Back") {}.focusID("back")
                Button("Next") { next.value += 1 }
                    .focusID("next")
                    .keyboardShortcut(.rightArrow, modifiers: modifiers)
            }
        }
        #expect(app.focusedID == "back")
        #expect(app.press(event))
        #expect(next.value == 1)
        #expect(app.focusedID == "back")
    }

    @Test("Without a shortcut on it, an arrow still moves the focus")
    func unboundArrowMovesFocus() {
        let next = Count()
        let app = TestApp(width: 40, height: 6) {
            VStack {
                Button("Back") {}.focusID("back")
                Button("Next") { next.value += 1 }
                    .focusID("next")
                    .keyboardShortcut(.rightArrow)
            }
        }
        // The shortcut is on Control-→; the bare arrow is not it.
        #expect(app.press(KeyEvent(key: .right)))
        #expect(next.value == 0)
        #expect(app.focusedID == "next")
    }

    @Test("A move command around the focus keeps the arrow ahead of the shortcut")
    func moveCommandHasTheArrowFirst() {
        let moves = Count()
        let shortcut = Count()
        let app = TestApp(width: 40, height: 6) {
            VStack {
                Text("board").focusable()
                    .onMoveCommand { _ in moves.value += 1 }
                Button("Down") { shortcut.value += 1 }
                    .keyboardShortcut(.downArrow, modifiers: [])
            }
        }
        let board = app.focusedID
        #expect(board != nil)
        #expect(app.press(KeyEvent(key: .down)))
        #expect(moves.value == 1)
        #expect(shortcut.value == 0)
        #expect(app.focusedID == board)
    }
}
