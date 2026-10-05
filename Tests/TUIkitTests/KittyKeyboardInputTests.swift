//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KittyKeyboardInputTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// The kitty keyboard protocol's reports through the live parser, and what
/// the input chain does with a repeat and a release.
@MainActor
@Suite("Kitty keyboard protocol input")
struct KittyKeyboardInputTests {

    /// A terminal reading `bytes`, all in one read, with the protocol's
    /// enhancements on or off.
    private func terminal(_ bytes: String, enhanced: Bool = true) -> Terminal {
        let terminal = Terminal()
        var staged = Array(bytes.utf8)
        terminal.readSource = { buffer in
            let count = min(staged.count, buffer.count)
            for index in 0..<count { buffer[index] = staged[index] }
            staged.removeFirst(count)
            return count
        }
        if enhanced { terminal.keyboardEnhancement = .requested }
        return terminal
    }

    /// Every event the terminal's buffered bytes decode to.
    private func events(_ terminal: Terminal) -> [TerminalInput] {
        var seen: [TerminalInput] = []
        while let event = terminal.readEvent() { seen.append(event) }
        return seen
    }

    // MARK: - The parser

    @Test("With the protocol on, CSI u reports decode, and typed text is what the terminal composed")
    func reportsDecode() {
        let parsed = events(terminal("\u{1B}[104;5u\u{1B}[97:65;2;65u\u{1B}[27u"))
        #expect(
            parsed == [
                .key(KeyEvent(key: .character("h"), ctrl: true)),
                .key(KeyEvent(key: .character("A"), shift: true)),
                .key(KeyEvent(key: .escape)),
            ])
    }

    @Test("Off, a CSI u report decodes to nothing, as it always did")
    func legacyIgnoresReports() {
        #expect(events(terminal("\u{1B}[104;5ux", enhanced: false)) == [.key(KeyEvent(character: "x"))])
    }

    @Test("Off, bit 8 of a legacy modifier is still Option; on, it is ⌘ and the key is dropped")
    func bitEightMeansDifferentThings() {
        #expect(
            events(terminal("\u{1B}[1;9C", enhanced: false)) == [.key(KeyEvent(key: .right, alt: true))])
        #expect(
            events(terminal("\u{1B}[1;9C")) == [.modifierKeys(ModifierKeyState(command: true))])
    }

    @Test("A report that typed several characters delivers them all, in order, before what follows")
    func queuedCharacters() {
        let parsed = events(terminal("\u{1B}[0;;26085:26412ux"))
        #expect(
            parsed == [
                .key(KeyEvent(key: .character("日"))), .key(KeyEvent(key: .character("本"))),
                .key(KeyEvent(character: "x")),
            ])
    }

    @Test("Bracketed paste, mouse and focus reports are untouched by the protocol")
    func otherInputUntouched() {
        let parsed = events(terminal("\u{1B}[200~hi\u{1B}[201~\u{1B}[<0;3;4M\u{1B}[I"))
        #expect(parsed.count == 3)
        #expect(parsed.first == .key(KeyEvent(key: .paste("hi"))))
        #expect(parsed.last == .focusChanged(isFocused: true))
    }

    @Test("The legacy bytes a terminal still sends with only flag 1 on decode as before")
    func legacyBytesStillDecode() {
        #expect(events(terminal("\r\ta")) == [
            .key(KeyEvent(key: .enter)), .key(KeyEvent(key: .tab)), .key(KeyEvent(character: "a")),
        ])
    }

    // MARK: - The input chain

    @Test("A release reaches no layer but the key-press handlers: a button acts once")
    func releaseActsNowhere() {
        let harness = InputChainHarness()
        let count = Counter()
        let consumed = harness.play([
            KeyEvent(key: .enter), KeyEvent(key: .enter, phase: .release),
        ]) {
            Button("Go") { count.value += 1 }
        }
        #expect(count.value == 1)
        #expect(consumed == [true, false])
    }

    @Test("A release does not fire an app's shortcut, the status bar or the quit key")
    func releaseFiresNoShortcut() {
        let harness = InputChainHarness()
        let count = Counter()
        harness.play([
            KeyEvent(key: .character("k"), ctrl: true),
            KeyEvent(key: .character("k"), ctrl: true, phase: .release),
            KeyEvent(character: "q"),
            KeyEvent(key: .character("q"), phase: .release),
        ]) {
            Button("Go") { count.value += 1 }.keyboardShortcut("k", modifiers: .control)
        }
        #expect(count.value == 1)
        #expect(harness.quits == 1)
    }

    @Test("A repeat is a press to every layer")
    func repeatIsAPress() {
        let harness = InputChainHarness()
        let count = Counter()
        harness.play([KeyEvent(key: .enter), KeyEvent(key: .enter, phase: .repeat)]) {
            Button("Go") { count.value += 1 }
        }
        #expect(count.value == 2)
    }

    @Test("A default onKeyPress hears the press and its repeats, never the release")
    func onKeyPressDefaultPhases() {
        let harness = InputChainHarness()
        let log = Log()
        harness.play([
            KeyEvent(character: "x"), KeyEvent(key: .character("x"), phase: .repeat),
            KeyEvent(key: .character("x"), phase: .release),
        ]) {
            Text("x").focusable().onKeyPress { press in
                log.entries.append(press.phase.debugDescription)
                return .handled
            }
        }
        #expect(log.entries == [".down", ".repeat"])
    }

    // MARK: - The chords the legacy bytes spent on other keys

    @Test("Ctrl-H nothing binds rubs out, as the legacy Backspace it was")
    func unboundControlHIsBackspace() {
        let harness = InputChainHarness()
        let text = TextBox(value: "ab")
        harness.play([KeyEvent(key: .end), KeyEvent(key: .character("h"), ctrl: true)]) {
            TextField("Name", text: Binding(get: { text.value }, set: { text.value = $0 }))
        }
        #expect(text.value == "a")
    }

    @Test("Ctrl-H an app binds fires the binding, and does not rub out")
    func boundControlHIsTheBinding() {
        let harness = InputChainHarness()
        let text = TextBox(value: "ab")
        let count = Counter()
        harness.play([KeyEvent(key: .end), KeyEvent(key: .character("h"), ctrl: true)]) {
            VStack {
                TextField("Name", text: Binding(get: { text.value }, set: { text.value = $0 }))
                Button("Help") { count.value += 1 }.keyboardShortcut("h", modifiers: .control)
            }
        }
        #expect(count.value == 1)
        #expect(text.value == "ab")
    }

    @Test("Each of the five chords falls back to its legacy key, keeping Option")
    func legacyEquivalents() {
        func fallback(_ character: Character, alt: Bool = false) -> KeyEvent? {
            KeyEvent(key: .character(character), ctrl: true, alt: alt).legacyControlEquivalent
        }
        #expect(fallback("h") == KeyEvent(key: .backspace))
        #expect(fallback("i") == KeyEvent(key: .tab))
        #expect(fallback("j") == KeyEvent(key: .enter))
        #expect(fallback("m") == KeyEvent(key: .enter))
        #expect(fallback("[") == KeyEvent(key: .escape))
        #expect(fallback("h", alt: true) == KeyEvent(key: .backspace, alt: true))
        #expect(fallback("a") == nil)
        #expect(KeyEvent(key: .character("H"), ctrl: true, shift: true).legacyControlEquivalent == nil)
        #expect(KeyEvent(key: .character("h")).legacyControlEquivalent == nil)
    }

    private final class Counter { var value = 0 }
    private final class Log { var entries: [String] = [] }
    private final class TextBox {
        var value: String
        init(value: String) { self.value = value }
    }
}
