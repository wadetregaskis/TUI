//  🖥️ TUI — A Terminal UI framework for Swift
//  ControlReturnTests.swift
//
//  Ctrl-Return as itself, which only a terminal speaking the kitty keyboard
//  protocol sends, offered as macOS layers it (owner ruling B63-KITTY,
//  2026-10-26): to the app's handlers and shortcuts, then as the context-menu
//  key, then to a vertical field as a line separator (U+2028), and else as
//  Return. A legacy terminal sends a plain CR, which is Return.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// What the page heard.
@MainActor
private final class Heard {
    var log: [String] = []
    var text = ""
}

private let controlReturn = KeyEvent(key: .enter, ctrl: true)

@MainActor
@Suite("Ctrl-Return")
struct ControlReturnTests {

    @Test("It opens the focused view's context menu")
    func opensTheContextMenu() {
        let heard = Heard()
        let harness = InputChainHarness(width: 40, height: 8)
        harness.play([controlReturn]) {
            Button("Target") { heard.log.append("pressed") }
                .contextMenu { Button("Rename") {} }
        }
        let drawn = harness.frame(
            Button("Target") { heard.log.append("pressed") }.contextMenu { Button("Rename") {} })
        let screen = (drawn.lines + drawn.overlays.flatMap(\.content.lines)).map(\.stripped).joined(separator: "\n")
        #expect(screen.contains("Rename"), "\(screen)")
        #expect(heard.log.isEmpty, "the button was pressed instead")
    }

    @Test("An app's ⌘↩ shortcut takes it before a context menu does")
    func appShortcutWins() {
        let heard = Heard()
        let harness = InputChainHarness(width: 40, height: 8)
        let taken = harness.play([controlReturn]) {
            VStack {
                Button("Target") {}.contextMenu { Button("Rename") {} }
                Button("Send") { heard.log.append("send") }.keyboardShortcut(.return)
            }
        }
        #expect(taken == [true])
        #expect(heard.log == ["send"])
    }

    @Test("A vertical field puts in a line separator; one on one line submits")
    func fields() {
        let heard = Heard()
        let harness = InputChainHarness(width: 40, height: 8)
        harness.play([KeyEvent(character: "a"), controlReturn, KeyEvent(character: "b")]) {
            TextField("T", text: Binding(get: { heard.text }, set: { heard.text = $0 }), axis: .vertical)
        }
        #expect(heard.text == "a\u{2028}b")

        let line = Heard()
        let other = InputChainHarness(width: 40, height: 8)
        other.play([controlReturn]) {
            TextField("T", text: Binding(get: { line.text }, set: { line.text = $0 }))
                .onSubmit { line.log.append("submit") }
        }
        #expect(line.log == ["submit"])
    }

    /// `.contextMenu` makes its content a focus stop of its own, which holds
    /// the focus here, as for Shift-F10; a field focused inside it hears
    /// Shift-F10 as its own editing menu, and Ctrl-Return as its line break
    /// (the test above).
    @Test("An app's context menu around a text field opens on it, and the field takes nothing")
    func appMenuAroundAFieldOpens() {
        let heard = Heard()
        let harness = InputChainHarness(width: 40, height: 10)
        let field = {
            TextField("T", text: Binding(get: { heard.text }, set: { heard.text = $0 }), axis: .vertical)
                .contextMenu { Button("Rename") {} }
        }
        harness.play([controlReturn]) { field() }
        let drawn = harness.frame(field())
        let screen = (drawn.lines + drawn.overlays.flatMap(\.content.lines)).map(\.stripped).joined(separator: "\n")
        #expect(screen.contains("Rename"), "\(screen)")
        #expect(heard.text.isEmpty, "the field took the chord as well")
    }

    @Test("With nothing else to take it, it is Return")
    func fallsBackToReturn() {
        let heard = Heard()
        let harness = InputChainHarness(width: 40, height: 8)
        harness.play([controlReturn]) {
            Button("Target") { heard.log.append("pressed") }
        }
        #expect(heard.log == ["pressed"])
    }

    @Test("A legacy terminal's plain Return is not Ctrl-Return")
    func plainReturnIsNotTheChord() {
        #expect(!KeyEvent(key: .enter).isControlReturn)
        #expect(controlReturn.isControlReturn)
        #expect(KeyEvent(key: .enter, ctrl: true, alt: true).isControlReturn)
        #expect(!KeyEvent(key: .enter, ctrl: true, shift: true).isControlReturn)
    }
}
