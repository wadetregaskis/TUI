//  🖥️ TUI — A Terminal UI framework for Swift
//  ScalarAtATimeInputTests.swift
//
//  A terminal's input reaches a text control a Unicode scalar at a time: the
//  reader peels one UTF-8 sequence off the bytes per key (`Terminal+Input`'s
//  `tryExtractPlainText`). So a character of several scalars — an emoji joined
//  with ZWJ, a heart with its emoji variation selector, a Thai syllable with
//  its tone mark, an accent typed or inserted decomposed — arrives as a base
//  followed by keys that are a mark or a format character on their own. The
//  text controls typed only letters, digits, punctuation, symbols and spaces,
//  and dropped those keys: 👨‍👩‍👧 became 👨👩👧 and ❤️ lost its emoji form.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
import TUICore
import TUIFoundation
import TUITesting
import TUITextInput

/// The scalars of `text`, each as the key a terminal's input makes of it.
private func scalarKeys(_ text: String) -> [KeyEvent] {
    text.unicodeScalars.map { KeyEvent(character: Character($0)) }
}

/// Text that needs a mark or a format character typed after its base.
private let samples = [
    "e\u{301}",  // e and a combining acute, decomposed
    "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}",  // 👨‍👩‍👧, joined with ZWJ
    "\u{2764}\u{FE0F}",  // ❤️, the emoji variation selector after the heart
    "\u{E01}\u{E48}",  // ก่, Thai ko kai with mai ek, a non-spacing tone mark
    "\u{645}\u{6CC}\u{200C}\u{62E}",  // Persian, with a zero-width non-joiner
]

private struct FieldProbe: View {
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Name", text: $text)
            Text(verbatim: scalarLine(text))
        }
    }
}

private struct EditorProbe: View {
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $text).frame(height: 2)
            Text(verbatim: scalarLine(text))
        }
    }
}

/// What the probes print for `text`: its scalars, in hexadecimal.
private func scalarLine(_ text: String) -> String {
    "[\(text.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " "))]"
}

@MainActor
@Suite("Text typed a scalar at a time, as a terminal sends it")
struct ScalarAtATimeInputTests {
    @Test("A text field keeps the marks and joiners that follow a base", arguments: samples)
    func textField(sample: String) {
        let app = TestApp(width: 40, height: 3) { FieldProbe() }
        for key in scalarKeys(sample) { app.press(key) }
        #expect(app.screen.lines[1] == scalarLine(sample))
    }

    @Test("A text editor keeps the marks and joiners that follow a base", arguments: samples)
    func textEditor(sample: String) {
        let app = TestApp(width: 40, height: 4) { EditorProbe() }
        for key in scalarKeys(sample) { app.press(key) }
        #expect(app.screen.lines[2] == scalarLine(sample))
    }

    @Test("A control character still types nothing")
    func controlsStayOut() {
        let app = TestApp(width: 40, height: 3) { FieldProbe() }
        app.press(KeyEvent(character: "a"))
        app.press(KeyEvent(character: "\u{7F}"))
        app.press(KeyEvent(character: "\u{1B}"))
        app.press(KeyEvent(character: "\u{9B}"))  // C1's CSI
        #expect(app.screen.lines[1] == scalarLine("a"))
    }
}
