//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CommandChordTests.swift
//
//  A ⌘ chord, which only the kitty keyboard protocol delivers, through the
//  input chain (the owner's ruling B-D1K-1, 2026-10-23): `onKeyPress` sees
//  `.command`; nothing that matches a bare key hears it; a shortcut written
//  with ⌘ keeps to its stand-in unless the app asks for a real ⌘ too.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("⌘ chords under the kitty keyboard protocol")
struct CommandChordTests {

    /// `key` with ⌘ held, as the protocol reports it.
    private func command(_ key: Character, shift: Bool = false) -> KeyEvent {
        KeyEvent(key: .character(key), shift: shift, command: true)
    }

    @Test("onKeyPress sees a ⌘ chord's Command, as in SwiftUI")
    func onKeyPressSeesCommand() {
        let harness = InputChainHarness(keyboard: .requested)
        let log = Log()
        let consumed = harness.play([command("k")]) {
            Text("x").focusable().onKeyPress { press in
                log.entries.append("\(press.characters) \(press.modifiers == .command)")
                return .handled
            }
        }
        #expect(log.entries == ["k true"])
        #expect(consumed == [true])
    }

    @Test("⌘K types nothing into a focused text field")
    func textFieldRefusesCommand() {
        let harness = InputChainHarness(keyboard: .requested)
        let text = Box("ab")
        let consumed = harness.play([command("k"), command("K", shift: true)]) {
            TextField("Field", text: Binding(get: { text.value }, set: { text.value = $0 }))
        }
        #expect(text.value == "ab")
        #expect(consumed == [false, false])
    }

    @Test("⌘ with a bare key's letter fires no bare-key binding: not the quit key, not an onKeyEvent")
    func bareBindingsRefuseCommand() {
        let harness = InputChainHarness(keyboard: .requested)
        let heard = Counter()
        let fired = Counter()
        harness.play([command("q"), command("x")]) {
            Button("Go") { fired.value += 1 }
                .keyboardShortcut("x", modifiers: [])
                .onKeyEvent { _ in
                    heard.value += 1
                    return false
                }
        }
        #expect(harness.quits == 0)
        #expect(fired.value == 0)
        #expect(heard.value == 0)
    }

    @Test("By default a ⌘ shortcut fires on its stand-in, not on a real ⌘")
    func standInOnlyByDefault() {
        let harness = InputChainHarness(keyboard: .requested)
        let fired = Counter()
        let consumed = harness.play([command("s"), KeyEvent(key: .character("s"), ctrl: true)]) {
            Button("Save") { fired.value += 1 }.keyboardShortcut("s")
        }
        #expect(fired.value == 1)
        #expect(consumed == [false, true])
    }

    @Test("With keyboardShortcutsMatchCommand a ⌘ shortcut fires on a real ⌘ and on its stand-in")
    func realCommandWhenAsked() {
        let harness = InputChainHarness(keyboard: .requested)
        let fired = Counter()
        let consumed = harness.play([command("s"), KeyEvent(key: .character("s"), ctrl: true), command("S", shift: true)]) {
            VStack {
                Button("Save") { fired.value += 1 }.keyboardShortcut("s")
            }
            .keyboardShortcutsMatchCommand()
        }
        #expect(fired.value == 2)
        #expect(consumed == [true, true, false], "⇧⌘S is another shortcut")
    }

    @Test("A real ⌘ never fires a shortcut written with Control, asked for or not")
    func controlShortcutStaysControl() {
        let harness = InputChainHarness(keyboard: .requested)
        let fired = Counter()
        harness.play([command("d")]) {
            VStack {
                Button("Duplicate") { fired.value += 1 }.keyboardShortcut("d", modifiers: .control)
            }
            .keyboardShortcutsMatchCommand()
        }
        #expect(fired.value == 0)
    }

    @Test("A real ⌘ shortcut served from a value memo still fires")
    func memoReplayRegistersTheCommandChord() {
        let harness = InputChainHarness(keyboard: .requested)
        let fired = Counter()
        let page = {
            VStack {
                Button("Save") { fired.value += 1 }.keyboardShortcut("s")
            }
            .keyboardShortcutsMatchCommand()
        }
        harness.frame(page())
        harness.frame(page())
        harness.handler.handle(command("s"))
        #expect(fired.value == 1)
    }

    private final class Counter { var value = 0 }
    private final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }
    private final class Log { var entries: [String] = [] }
}
