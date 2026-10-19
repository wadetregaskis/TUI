//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FormAppViewRowTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitTestSupport

/// A view of the app's own whose body is one row the form lays out is that
/// row: `struct ModeRow: View { var body: some View { Picker("Mode", …) } }`
/// in a form is drawn as the `Picker` written bare there — a field row, its
/// label in the label column — as SwiftUI's form lays it out (measured on macOS
/// 15.8, `Tools/SwiftUIProbes/Form rows/appview.swift`: every control, two such
/// views deep and under a modifier, in both styles). It was a plain row, its
/// label drawn beside the control at the row's start: the form read through a
/// view of the app's own only where its body was a `LabeledContent`.
@MainActor
@Suite("Form: a view of the app's own is the row its body is")
struct FormAppViewRowTests {
    private func lines(_ view: some View) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: 60, height: 24)).lines.map { $0.stripped }
    }

    /// `row` after a labelled row that sets the label column, in a form of
    /// `style`.
    private func form(_ row: some View, grouped: Bool) -> [String] {
        let form = Form {
            LabeledContent("Email address", value: "a@b.c")
            row
        }
        return grouped ? lines(form.formStyle(.grouped)) : lines(form.formStyle(.columns))
    }

    /// Expects `wrapped` drawn in a form exactly as `bare` is, in both styles.
    private func expectSameRow(_ name: String, bare: some View, wrapped: some View) {
        for grouped in [false, true] {
            let expected = form(bare, grouped: grouped)
            let actual = form(wrapped, grouped: grouped)
            #expect(actual == expected, "\(name), \(grouped ? "grouped" : "columns"): \(actual) ≠ \(expected)")
        }
    }

    private static func picker() -> some View {
        Picker("Mode", selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) }
    }

    @Test("Each row the form lays out, as the whole body of a view of the app's own")
    func eachRowKind() {
        expectSameRow("picker", bare: Self.picker(), wrapped: AppRow(content: Self.picker()))
        let toggle = Toggle("Enabled", isOn: .constant(true))
        expectSameRow("checkbox", bare: toggle, wrapped: AppRow(content: toggle))
        let switchToggle = Toggle("Enabled", isOn: .constant(true)).toggleStyle(.switch)
        expectSameRow("switch", bare: switchToggle, wrapped: AppRow(content: switchToggle))
        let slider = Slider(value: .constant(0.5)) { Text("Level") }
        expectSameRow("slider", bare: slider, wrapped: AppRow(content: slider))
        let stepper = Stepper("Count", value: .constant(3))
        expectSameRow("stepper", bare: stepper, wrapped: AppRow(content: stepper))
        let button = Button("Go") {}
        expectSameRow("button", bare: button, wrapped: AppRow(content: button))
        let labeled = LabeledContent("Name", value: "Alice")
        expectSameRow("labelled content", bare: labeled, wrapped: AppRow(content: labeled))
    }

    @Test("Two views of the app's own deep, and with a modifier in the body")
    func nestedAndModified() {
        expectSameRow("nested", bare: Self.picker(), wrapped: AppRow(content: AppRow(content: Self.picker())))
        let disabled = Self.picker().disabled(true)
        expectSameRow("under .disabled", bare: disabled, wrapped: AppRow(content: disabled))
        let padded = Self.picker().padding(.leading, 2)
        expectSameRow("under .padding", bare: padded, wrapped: AppRow(content: padded))
    }

    @Test("A view of the app's own keeps its @State, read through")
    func keepsItsState() {
        expectSameRow(
            "stateful toggle", bare: Toggle("Enabled", isOn: .constant(true)), wrapped: StatefulToggleRow())
    }

    @Test("A body of any other one view is still a row drawn whole")
    func otherBodiesStayPlain() {
        let stack = HStack { Text("Mode"); Text("One") }
        expectSameRow("an HStack", bare: stack, wrapped: AppRow(content: stack))
    }
}

/// A view of the app's own whose body is the view it is given.
private struct AppRow<Content: View>: View {
    let content: Content
    var body: some View { content }
}

/// A view of the app's own whose body is a toggle bound to its own `@State`.
private struct StatefulToggleRow: View {
    @State private var isOn = true
    var body: some View { Toggle("Enabled", isOn: $isOn) }
}
