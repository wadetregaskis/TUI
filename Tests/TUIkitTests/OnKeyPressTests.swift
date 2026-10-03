//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OnKeyPressTests.swift
//
//  SwiftUI's onKeyPress, as measured on macOS 15 (offscreen NSHostingView in
//  a key window, NSEvents sent through it): a handler hears a press only while
//  the focus is on its view or inside it; the handlers on the focus path are
//  asked outermost first, and a `.handled` stops the rest; and they are asked
//  before the focused control — a TextField does not type a handled letter,
//  and a handled Tab does not move the focus — and before keyboard shortcuts.
//  KeyPress reports Shift-A as the key "A", Control-A's characters as "a",
//  Shift-Tab as the back-tab character, and an arrow as its private-use scalar.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

/// What the handlers under test saw, in the order they ran.
private final class PressLog: @unchecked Sendable {
    var entries: [String] = []
}

/// The string a field under test is bound to.
private final class FieldText: @unchecked Sendable {
    var value = ""
}

private func key(_ character: Character, ctrl: Bool = false) -> KeyEvent {
    ctrl ? KeyEvent(key: .character(character), ctrl: true) : KeyEvent(character: character)
}

@MainActor
@Suite("SwiftUI's onKeyPress")
struct OnKeyPressTests {

    // MARK: - Who hears a press

    @Test("Only the view holding the focus hears a press, and a sibling does not")
    func focusGatesTheHandler() {
        let log = PressLog()
        let harness = InputChainHarness()
        // The first registrant takes the focus; Tab moves it to the second.
        harness.play([key("x"), KeyEvent(key: .tab), key("y")]) {
            VStack {
                Text("A").focusable()
                    .onKeyPress { press in log.entries.append("A \(press.characters)"); return .ignored }
                Text("B").focusable()
                    .onKeyPress { press in log.entries.append("B \(press.characters)"); return .ignored }
            }
        }
        // A hears the Tab that moves the focus away, as SwiftUI's does: the
        // handler is asked before the focus system, and ignored it.
        #expect(log.entries == ["A x", "A \t", "B y"])
    }

    @Test("A view that neither holds nor contains the focus never hears a press")
    func noFocusNoPress() {
        let log = PressLog()
        let harness = InputChainHarness()
        // Nothing focusable at all: SwiftUI hands no view a key press then.
        harness.play([key("x")]) {
            Text("plain").onKeyPress { _ in log.entries.append("plain"); return .ignored }
        }
        // Something focusable beside it, but not inside it.
        harness.play([key("y")]) {
            VStack {
                Text("plain").onKeyPress { _ in log.entries.append("plain"); return .ignored }
                Button("Focused") {}
            }
        }
        #expect(log.entries.isEmpty)
    }

    @Test("A container hears a press while the focus is inside it")
    func containerHearsFocusedDescendant() {
        let log = PressLog()
        let harness = InputChainHarness()
        harness.play([key("x")]) {
            VStack {
                Text("title")
                HStack { Button("Inner") {} }
            }
            .onKeyPress { press in log.entries.append("container \(press.characters)"); return .ignored }
        }
        #expect(log.entries == ["container x"])
    }

    // MARK: - In what order

    @Test("The focus path is asked outermost first, and a handled press stops there")
    func outermostFirst() {
        for outerResult in [KeyPress.Result.ignored, .handled] {
            let log = PressLog()
            let harness = InputChainHarness()
            let consumed = harness.play([key("x")]) {
                VStack {
                    Text("leaf").focusable()
                        .onKeyPress { _ in log.entries.append("inner"); return .ignored }
                        .onKeyPress { _ in log.entries.append("outer modifier"); return .ignored }
                }
                .onKeyPress { _ in log.entries.append("container"); return outerResult }
            }
            if outerResult == .handled {
                #expect(log.entries == ["container"])
                #expect(consumed == [true])
            } else {
                #expect(log.entries == ["container", "outer modifier", "inner"])
                #expect(consumed == [false], "every handler ignored it, and nothing else binds x")
            }
        }
    }

    @Test("The focus path is asked before a focused text field types the key")
    func beforeTheTextField() {
        let text = FieldText()
        let harness = InputChainHarness()
        harness.play([key("a"), key("1"), key("b")]) {
            VStack {
                TextField("Name", text: Binding(get: { text.value }, set: { text.value = $0 }))
            }
            .onKeyPress(characters: .letters) { _ in .handled }
        }
        #expect(text.value == "1", "the handled letters were never typed, and the digit was")
    }

    @Test("A handled Tab does not move the focus")
    func beforeFocusNavigation() {
        let log = PressLog()
        let harness = InputChainHarness()
        harness.play([KeyEvent(key: .tab), key("x")]) {
            VStack {
                Text("A").focusable()
                    .onKeyPress(.tab) { log.entries.append("tab"); return .handled }
                    .onKeyPress("x") { log.entries.append("A x"); return .handled }
                Text("B").focusable()
                    .onKeyPress("x") { log.entries.append("B x"); return .handled }
            }
        }
        #expect(log.entries == ["tab", "A x"])
    }

    @Test("The focus path is asked before the app's keyboard shortcuts")
    func beforeKeyboardShortcuts() {
        for result in [KeyPress.Result.ignored, .handled] {
            let log = PressLog()
            let harness = InputChainHarness()
            harness.play([key("k")]) {
                VStack {
                    Text("leaf").focusable()
                    Button("Shortcut") { log.entries.append("shortcut") }
                        .keyboardShortcut("k", modifiers: [])
                }
                .onKeyPress("k") { log.entries.append("onKeyPress"); return result }
            }
            #expect(
                log.entries == (result == .handled ? ["onKeyPress"] : ["onKeyPress", "shortcut"]),
                "\(result)")
        }
    }

    // MARK: - What matches

    @Test("A key matches by its case, as SwiftUI's KeyEquivalent does")
    func keyMatching() {
        let log = PressLog()
        let harness = InputChainHarness()
        let events = [
            key("a"), KeyEvent(character: "A"), KeyEvent(key: .up), KeyEvent(key: .tab, shift: true),
            KeyEvent(key: .enter), KeyEvent(key: .backspace), KeyEvent(key: .f1),
        ]
        harness.play(events) {
            Text("leaf").focusable()
                .onKeyPress("a") { log.entries.append("a"); return .ignored }
                .onKeyPress("A") { log.entries.append("A"); return .ignored }
                .onKeyPress(.upArrow) { log.entries.append("up"); return .ignored }
                .onKeyPress(.tab) { log.entries.append("tab"); return .ignored }
                .onKeyPress(keys: [.return, .delete]) { press in
                    log.entries.append(press.key == .return ? "return" : "delete")
                    return .ignored
                }
                .onKeyPress(KeyEquivalent("\u{F704}")) { log.entries.append("F1"); return .ignored }
        }
        // Shift-Tab is the back-tab key, not Tab — `onKeyPress(.tab)` hears
        // only the unshifted one.
        #expect(log.entries == ["a", "A", "up", "return", "delete", "F1"])
    }

    @Test("Characters match the press's characters: Control-A is a letter, an arrow is not")
    func charactersMatching() {
        let log = PressLog()
        let harness = InputChainHarness()
        harness.play([key("a"), key("a", ctrl: true), key("1"), KeyEvent(key: .up), KeyEvent(key: .space)]) {
            Text("leaf").focusable()
                .onKeyPress(characters: .letters) { press in
                    log.entries.append(press.debugDescription)
                    return .ignored
                }
        }
        #expect(log.entries == ["KeyPress(.down, \"a\")", "KeyPress(.down, \"a\")"])
    }

    @Test("A bracketed paste is not a key press")
    func pasteIsNotAKeyPress() {
        let log = PressLog()
        let harness = InputChainHarness()
        harness.play([KeyEvent(key: .paste("hello"))]) {
            Text("leaf").focusable()
                .onKeyPress { press in log.entries.append(press.characters); return .ignored }
        }
        #expect(log.entries.isEmpty)
    }

    @Test("Every press is a down, and a handler for any phase a press could be hears it")
    func phases() {
        let log = PressLog()
        let harness = InputChainHarness()
        harness.play([key("x")]) {
            Text("leaf").focusable()
                .onKeyPress(phases: .down) { press in log.entries.append("down \(press.phase)"); return .ignored }
                .onKeyPress(phases: .repeat) { press in log.entries.append("repeat \(press.phase)"); return .ignored }
                .onKeyPress(phases: .all) { press in log.entries.append("all \(press.phase)"); return .ignored }
                .onKeyPress(keys: ["x"], phases: KeyPress.Phases(rawValue: 1 << 2)) { _ in
                    log.entries.append("release")
                    return .ignored
                }
        }
        #expect(log.entries == ["all .down", "repeat .down", "down .down"])
    }

    // MARK: - KeyPress and its phases, as values

    /// SwiftUI on macOS 15, field by field, for the keys a terminal sends.
    @Test("A key event becomes the KeyPress SwiftUI would report")
    func keyPressFromEvent() throws {
        let shiftA = try #require(KeyPress(KeyEvent(character: "A")))
        #expect(shiftA.key == "A")
        #expect(shiftA.characters == "A")
        #expect(shiftA.modifiers == .shift)
        #expect(shiftA.phase == .down)

        let controlA = try #require(KeyPress(KeyEvent(key: .character("a"), ctrl: true)))
        #expect(controlA.key == "a")
        #expect(controlA.characters == "a")
        #expect(controlA.modifiers == .control)

        let up = try #require(KeyPress(KeyEvent(key: .up, alt: true)))
        #expect(up.key == .upArrow)
        #expect(up.characters == "\u{F700}")
        #expect(up.modifiers == .option)

        let backTab = try #require(KeyPress(KeyEvent(key: .tab, shift: true)))
        #expect(backTab.key == KeyEquivalent("\u{19}"))
        #expect(backTab.modifiers == .shift)

        #expect(KeyPress(KeyEvent(key: .enter))?.characters == "\r")
        #expect(KeyPress(KeyEvent(key: .escape))?.key == .escape)
        #expect(KeyPress(KeyEvent(key: .backspace))?.key == .delete)
        #expect(KeyPress(KeyEvent(key: .delete))?.key == .deleteForward)
        #expect(KeyPress(KeyEvent(key: .f12))?.key == KeyEquivalent("\u{F70F}"))
        #expect(KeyPress(KeyEvent(key: .paste("text"))) == nil)
        #expect(shiftA.debugDescription == "KeyPress(.down, \"A\")")
    }

    @Test("Phases have SwiftUI's raw values and spellings")
    func phaseValues() {
        #expect(KeyPress.Phases.down.rawValue == 1)
        #expect(KeyPress.Phases.repeat.rawValue == 2)
        #expect(KeyPress.Phases.all.rawValue == .max)
        #expect(KeyPress.Phases.down.debugDescription == ".down")
        #expect(KeyPress.Phases.all.debugDescription == ".all")
        #expect(([.down, .repeat] as KeyPress.Phases).debugDescription == "[.down, .repeat]")
        #expect(KeyPress.Phases().debugDescription == "[]")
    }

    // MARK: - Registration

    @Test("A disabled view registers no handler")
    func disabledRegistersNothing() {
        let harness = InputChainHarness()
        harness.frame(
            VStack {
                Text("leaf").focusable().onKeyPress { _ in .handled }
            }
            .disabled(true))
        #expect(harness.tui.keyEventDispatcher.focusPathHandlerCount == 0)
        harness.frame(Text("leaf").focusable().onKeyPress { _ in .handled })
        #expect(harness.tui.keyEventDispatcher.focusPathHandlerCount == 1)
    }

    /// A focused control breathes, so a memo is never served around one; the
    /// replay is exercised by a handler on a view the memo CAN serve, and what
    /// it must get right is the scope, which the replay context cannot supply.
    @Test("A memo that serves a handler's view registers it again, at the same scope")
    func memoReplaysTheScope() {
        let harness = InputChainHarness()
        let view = { VStack { HandlerLeaf().equatable() } }
        harness.frame(view())
        let rendered = harness.tui.keyEventDispatcher.focusPathScopes
        #expect(rendered.count == 1)
        harness.frame(view())
        harness.frame(view())
        #expect(harness.tui.renderCache.rowWork.served >= 2, "the leaf was served, not rendered")
        #expect(harness.tui.keyEventDispatcher.focusPathScopes == rendered)
    }
}

/// A handler on a leaf behind an `.equatable()` boundary, equal to every other,
/// so every frame after the first serves it from the memo.
private struct HandlerLeaf: View, @MainActor Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool { true }

    var body: some View {
        Text("leaf").onKeyPress { _ in .handled }
    }
}
