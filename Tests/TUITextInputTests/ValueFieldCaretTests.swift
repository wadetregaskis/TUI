//  🖥️ TUI — A Terminal UI framework for Swift
//  ValueFieldCaretTests.swift
//
//  Where the caret is once a field bound to a value through a format has
//  written what was typed back as the value, formatted. Return replaces the
//  text typed, "1234", with the value's, "1,234", which is longer, and the
//  caret stayed at the fourth character: the next digit went in between the
//  3 and the 4, and Return made 12,394 of what was typed as 12349. Leaving the
//  field commits the same way, and the caret was as stale on coming back.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIApp
import TUICore
import TUIFoundation
import TUITesting
import TUITextInput

private struct Quantity: View {
    @State private var quantity = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(
                "Quantity", value: $quantity,
                format: IntegerFormatStyle<Int>().locale(Locale(identifier: "en_US")))
            Text(verbatim: "value: \(quantity)")
            Button("Next") {}
        }
    }
}

@MainActor
@Suite("The caret of a TextField(value:format:) after Return")
struct ValueFieldCaretTests {
    @Test("Return leaves the caret at the end of the formatted value, so typing goes on after it")
    func caretAtEndAfterCommit() {
        let app = TestApp(width: 30, height: 3) { Quantity() }
        app.press(.character("u"), modifiers: .control)
        app.type("1234")
        app.press(.enter)
        #expect(app.screen.lines[0].contains("1,234"))
        app.type("9")
        #expect(app.screen.lines[0].contains("1,2349"))
        app.press(.enter)
        #expect(app.screen.lines[1] == "value: 12349")
    }

    @Test("Leaving the field does the same, so typing on coming back goes on after the value")
    func caretAtEndAfterLeaving() {
        let app = TestApp(width: 30, height: 3) { Quantity() }
        app.press(.character("u"), modifiers: .control)
        app.type("1234")
        app.press(.tab)
        app.press(.tab, modifiers: .shift)
        app.type("9")
        app.press(.enter)
        #expect(app.screen.lines[1] == "value: 12349")
    }

    @Test("Return that changes nothing leaves the caret where it was")
    func caretKeptWhenTextUnchanged() {
        let app = TestApp(width: 30, height: 3) { Quantity() }
        app.press(.character("u"), modifiers: .control)
        app.type("12")
        app.press(.left)
        app.press(.enter)
        app.type("5")
        #expect(app.screen.lines[1] == "value: 12")
        app.press(.enter)
        #expect(app.screen.lines[1] == "value: 152")
    }
}
