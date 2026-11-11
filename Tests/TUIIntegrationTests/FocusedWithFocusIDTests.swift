//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusedWithFocusIDTests.swift
//
//  A control named with `.focusID(_:)` and bound with `.focused(_:equals:)`
//  answers to its `@FocusState`. The binding offers an id of its own to the
//  control below it, and a control with an id of its app's ranks that one
//  first, as it should; but the binding went on mapping its value to the id it
//  had offered, which no control registered under. Writing the state moved the
//  focus nowhere and reading it never saw the control focused — for a test
//  that named its fields to read `TestApp.focusedID`, the whole `@FocusState`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
import TUITesting

private enum Field: Hashable { case name, email }

private struct NamedFields: View {
    @FocusState var field: Field?
    @FocusState var flagged: Bool

    var body: some View {
        VStack {
            TextField("Name", text: .constant("")).focusID("name").focused($field, equals: .name)
            TextField("Email", text: .constant("")).focusID("email").focused($field, equals: .email)
            Button("Flag") {}.focusID("flag").focused($flagged)
            Button("To email") { field = .email }.focusID("to-email")
            Button("To flag") { flagged = true }.focusID("to-flag")
            Text(verbatim: "field=\(field.map { "\($0)" } ?? "none") flagged=\(flagged)")
        }
    }
}

@MainActor
@Suite("`.focused` reaches a control named with `.focusID`")
struct FocusedWithFocusIDTests {
    @Test("Writing the state focuses the named control")
    func writeFocuses() throws {
        let app = TestApp(width: 40, height: 10) { NamedFields() }
        try app.click("To email")
        #expect(app.focusedID == "email")
        try app.click("To flag")
        #expect(app.focusedID == "flag")
    }

    @Test("The state reads the named control's focus")
    func readsFocus() {
        let app = TestApp(width: 40, height: 10) { NamedFields() }
        #expect(app.focusedID == "name")
        #expect(app.screen.contains("field=name flagged=false"))
        app.press(.tab)
        #expect(app.focusedID == "email")
        #expect(app.screen.contains("field=email flagged=false"))
        app.press(.tab)
        #expect(app.focusedID == "flag")
        #expect(app.screen.contains("field=none flagged=true"))
    }
}
