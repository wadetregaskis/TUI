//  🖥️ TUI — A Terminal UI framework for Swift
//  ValueFieldReturnTests.swift
//
//  Return in a field bound to a value through a format. A field with no
//  `onSubmit` lets Return carry on to the dialog's default button, which is
//  what the docs promise for every text field. A value field kept it: its own
//  commit of the draft was an `onSubmit` too, so the field always took Return
//  and the default button never heard it.
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

/// A format whose output is the same on every machine.
private let number = IntegerFormatStyle<Int>().locale(Locale(identifier: "en_US"))

/// A quantity field and a default button that saves it, the field's own
/// `onSubmit` and an enclosing one each optional.
private struct Dialog: View {
    let fieldSubmits: Bool
    let stackSubmits: Bool
    @State private var quantity = 1
    @State private var log: [String] = []

    var body: some View {
        if stackSubmits {
            rows.onSubmit { log.append("stack \(quantity)") }
        } else {
            rows
        }
    }

    private var rows: some View {
        let field = TextField("Quantity", value: $quantity, format: number)
        return VStack(alignment: .leading, spacing: 0) {
            if fieldSubmits {
                field.onSubmit { log.append("field \(quantity)") }
            } else {
                field
            }
            Button("Save") { log.append("saved \(quantity)") }
                .keyboardShortcut(.defaultAction)
            Text(verbatim: "log: \(log.joined(separator: ", "))")
        }
    }
}

@MainActor
@Suite("Return in a TextField(value:format:)")
struct ValueFieldReturnTests {
    /// Erases the field and types `text` into it.
    private func retype(_ text: String, in app: TestApp) {
        app.press(.character("u"), modifiers: .control)
        app.type(text)
    }

    @Test("With no onSubmit, Return commits what was typed and goes on to the default button")
    func returnReachesDefaultButton() {
        let app = TestApp(width: 40, height: 4) { Dialog(fieldSubmits: false, stackSubmits: false) }
        retype("42", in: app)
        app.press(.enter)
        #expect(app.screen.contains("log: saved 42"))
        #expect(app.screen.lines[0].contains("42"))
    }

    @Test("With the field's own onSubmit, Return commits, runs it, and stops there")
    func fieldSubmitTakesReturn() {
        let app = TestApp(width: 40, height: 4) { Dialog(fieldSubmits: true, stackSubmits: false) }
        retype("42", in: app)
        app.press(.enter)
        #expect(app.screen.contains("log: field 42"))
    }

    @Test("An enclosing onSubmit sees the committed value too")
    func stackSubmitSeesCommittedValue() {
        let app = TestApp(width: 40, height: 4) { Dialog(fieldSubmits: false, stackSubmits: true) }
        retype("42", in: app)
        app.press(.enter)
        #expect(app.screen.contains("log: stack 42"))
    }
}
