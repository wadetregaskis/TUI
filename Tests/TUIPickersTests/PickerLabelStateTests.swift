//  🖥️ TUI — A Terminal UI framework for Swift
//  PickerLabelStateTests.swift
//
//  A `.menu` picker's option labels and its `currentValueLabel` keep `@State`
//  of their own, and the picker keeps its own slots beside them.
//
//  The menu core drew its labels at its own identity, where its handler,
//  focus id, hover flag and undo live at indices 0–3. An option's label is a
//  `Subview`, which draws at the identity it resolved to, so its state was its
//  own already; but the `currentValueLabel` is the caller's view itself, and
//  its first `@State` landed on the handler's key: the two replaced each
//  other's box every frame, the label's count read 0 again and the drop-down
//  never opened.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUIPickers
import TUITesting
@testable import TUITestSupport

/// Where the labels below leave a way for the test to write their state.
@MainActor
private final class LabelNotes {
    var writers: [String: (String) -> Void] = [:]
}

/// An option label whose `@State` the test writes, as a key would.
private struct NotedLabel: View {
    let name: String
    let notes: LabelNotes
    @State private var note = ""

    var body: some View {
        notes.writers[name] = { note = $0 }
        return Text(verbatim: "\(name)\(note)")
    }
}

/// A current-value label that counts its own appearances into `@State` of a
/// type no slot of the core's holds, so sharing a key with one replaces the box
/// each frame and the count reads 0 again. Short, as the collapsed control is
/// as wide as its widest option.
private struct CountingLabel: View {
    let fruit: String
    @State private var count = 0

    var body: some View {
        Text(verbatim: "\(fruit.prefix(1))#\(count)").onAppear { count = 7 }
    }
}

private struct FruitPage: View {
    let notes: LabelNotes
    let showsCurrentValue: Bool
    @State private var fruit = "Apple"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            picker.pickerStyle(.menu)
            Text(verbatim: "chose \(fruit)")
            Spacer()
        }
    }

    @ViewBuilder private var picker: some View {
        if showsCurrentValue {
            Picker(selection: $fruit) {
                options
            } label: {
                Text("Fruit")
            } currentValueLabel: {
                CountingLabel(fruit: fruit)
            }
        } else {
            Picker(selection: $fruit) { options } label: { Text("Fruit") }
        }
    }

    @ViewBuilder private var options: some View {
        NotedLabel(name: "Apple", notes: notes).tag("Apple")
        NotedLabel(name: "Banana", notes: notes).tag("Banana")
        NotedLabel(name: "Cherry", notes: notes).tag("Cherry")
    }
}

@MainActor
@Suite("A menu picker's labels keep their own @State")
struct PickerLabelStateTests {
    private func app(_ notes: LabelNotes, showsCurrentValue: Bool = false) -> TestApp {
        TestApp(width: 60, height: 16) {
            FruitPage(notes: notes, showsCurrentValue: showsCurrentValue)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// Opens the drop-down, focusing the picker first if it is not.
    private func open(_ app: TestApp) {
        app.press(.enter)
        if app.screen.location(of: "Cherry") == nil {
            app.press(.tab)
            app.press(.enter)
        }
    }

    @Test("Each option label keeps its own state, and the picker still opens and chooses")
    func optionLabelsKeepTheirState() throws {
        let notes = LabelNotes()
        let app = app(notes)
        _ = app.screen
        notes.writers["Banana"]?("+b")
        notes.writers["Cherry"]?("+c")
        open(app)
        try #require(app.screen.location(of: "Cherry+c") != nil, "the drop-down opens: \(app.screen)")
        #expect(app.screen.location(of: "Banana+b") != nil, "Banana kept its own note: \(app.screen)")
        #expect(app.screen.location(of: "Apple+") == nil, "Apple was handed another label's note: \(app.screen)")
        app.press(.down)
        app.press(.enter)
        #expect(app.screen.contains("chose Banana"), "the picker chose the row: \(app.screen)")
        #expect(app.screen.location(of: "Cherry") == nil, "the drop-down closed: \(app.screen)")
        #expect(app.screen.contains("Banana+b"), "the chosen label still holds its note: \(app.screen)")
        open(app)
        #expect(app.screen.location(of: "Cherry+c") != nil, "reopened, Cherry still holds its note: \(app.screen)")
    }

    @Test("The current-value label keeps its own state, and the picker still opens and chooses")
    func currentValueLabelKeepsItsState() throws {
        let notes = LabelNotes()
        let app = app(notes, showsCurrentValue: true)
        _ = app.screen
        #expect(app.screen.contains("A#7"), "the label's appear wrote its state: \(app.screen)")
        notes.writers["Cherry"]?("+c")
        open(app)
        try #require(app.screen.location(of: "Cherry+c") != nil, "the drop-down opens: \(app.screen)")
        app.press(.down)
        app.press(.down)
        app.press(.enter)
        #expect(app.screen.contains("chose Cherry"), "the picker chose the row: \(app.screen)")
        #expect(app.screen.contains("C#7"), "the label kept its count: \(app.screen)")
    }
}
