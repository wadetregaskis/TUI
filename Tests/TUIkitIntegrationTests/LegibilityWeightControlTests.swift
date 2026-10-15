//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LegibilityWeightControlTests.swift
//
//  Under `\.legibilityWeight == .bold` the text a control draws itself, not
//  through a `Text`, is a tier heavier too, as SwiftUI draws control labels a
//  weight heavier (decisions B2). Its chrome is not text, and is not.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitTextInput

@MainActor
@Suite("Legibility weight in the controls that draw their own text")
struct LegibilityWeightControlTests {
    /// The SGR state at `word` when `view` is drawn under `weight`.
    private func state(of word: String, in view: some View, under weight: LegibilityWeight?) -> SGRState? {
        let lines = renderToBuffer(
            view.environment(\.legibilityWeight, weight), context: makeRenderContext(width: 40, height: 12)
        ).lines
        return sgrState(of: word, in: lines)
    }

    /// Whether `word` is drawn bold under `.bold`, and plain under no weight.
    private func heavier(_ word: String, in view: some View) -> Bool {
        state(of: word, in: view, under: .bold)?.isBold == true
            && state(of: word, in: view, under: nil)?.isBold == false
    }

    @Test("A text field's text, and its prompt, are drawn bold")
    func textField() {
        #expect(heavier("typed", in: TextField("Name", text: .constant("typed"))))
        #expect(heavier("Prompt", in: TextField("Name", text: .constant(""), prompt: Text("Prompt"))))
    }

    @Test("A secure field's bullets are drawn bold")
    func secureField() {
        let bullet = String(TerminalSymbols.maskBullet)
        #expect(heavier(bullet, in: SecureField("Password", text: .constant("secret"))))
    }

    @Test("A text editor's text is drawn bold")
    func textEditor() {
        #expect(heavier("edited", in: TextEditor(text: .constant("edited")).frame(width: 20, height: 3)))
    }

    @Test("A vertical text field's text is drawn bold")
    func verticalField() {
        #expect(heavier("down", in: TextField("Notes", text: .constant("down"), axis: .vertical)))
    }
    private struct Mail: Identifiable {
        let id: Int
        let subject: String
    }

    @Test("A button's label, drawn by its style as a string, is drawn bold")
    func button() {
        // A second button takes the focus first, so these are drawn unfocused:
        // a focused label is bold whatever the weight.
        #expect(heavier("Send", in: VStack { Button("Other") {}; Button("Send") {} }))
        #expect(heavier("Plain", in: VStack { Button("Other") {}; Button("Plain") {}.buttonStyle(.plain) }))
    }

    @Test("A toggle's label and a radio group's options are drawn bold")
    func toggleAndRadio() {
        #expect(heavier("Wi-Fi", in: Toggle("Wi-Fi", isOn: .constant(true))))
        let radio = Picker("Size", selection: .constant(1)) {
            Text("Small").tag(1)
            Text("Large").tag(2)
        }.pickerStyle(.radioGroup)
        #expect(heavier("Large", in: radio))
    }

    @Test("A stepper's read-out is drawn bold")
    func stepper() {
        #expect(heavier("42", in: Stepper("Count", value: .constant(42), in: 0...100)))
    }

    @Test("A graphical date picker's title, weekdays and days are drawn bold")
    func graphicalDatePicker() {
        var components = DateComponents()
        (components.year, components.month, components.day) = (2026, 3, 18)
        let date = Calendar(identifier: .gregorian).date(from: components) ?? Date()
        let picker = DatePicker("Day", selection: .constant(date), displayedComponents: .date)
            .datePickerStyle(.graphical)
        // The calendar takes the focus once, and its title is bold while it has it.
        #expect(state(of: "2026", in: picker, under: .bold)?.isBold == true, "the month's title")
        #expect(heavier("18", in: picker), "the selected day")
        #expect(heavier("25", in: picker), "another day")
    }

    @Test("A compact date picker's components are drawn bold")
    func compactDatePicker() {
        var components = DateComponents()
        (components.year, components.month, components.day) = (2026, 3, 18)
        let date = Calendar(identifier: .gregorian).date(from: components) ?? Date()
        #expect(heavier("2026", in: DatePicker("Day", selection: .constant(date), displayedComponents: .date)))
    }

    @Test("A spinner's label is drawn bold")
    func spinner() {
        #expect(heavier("Loading", in: Spinner("Loading")))
    }

    @Test("A table's header and cells, and a list row's badge, are drawn bold")
    func tableAndList() {
        let mail = [Mail(id: 1, subject: "Lunch")]
        let table = Table(mail) { TableColumn("Subject", value: \.subject) }
        // The header is bold already, and bold stays bold.
        #expect(state(of: "Subject", in: table, under: .bold)?.isBold == true, "the header")
        #expect(state(of: "Subject", in: table, under: nil)?.isBold == true, "the header")
        #expect(heavier("Lunch", in: table), "a cell")
        #expect(heavier("17", in: List { Text("Inbox").badge(17) }))
    }

    @Test("A tab's title is drawn bold")
    func tabTitles() {
        let tabs = TabView {
            Tab("Mail", systemImage: "envelope") { Text("first") }
            Tab("Notes", systemImage: "note") { Text("second") }
        }
        #expect(heavier("Notes", in: tabs))
    }
}
