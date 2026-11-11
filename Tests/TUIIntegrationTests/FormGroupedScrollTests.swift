//  🖥️ TUI — A Terminal UI framework for Swift
//  FormGroupedScrollTests.swift
//
//  A grouped form is a scroll view, as SwiftUI's is on macOS: content taller
//  than the window scrolls by the wheel and by the paging keys the focused
//  control leaves, and Tab onto a row below the visible area scrolls it in
//  (measured, `Tools/SwiftUIProbes/Tab into rows off screen (1110F)`). A
//  columns form is not one, as SwiftUI's is not ("a non-scrolling form
//  style", Apple's `FormStyle.columns`; the probe found no scroll view).
//  FORM-SCROLL, 2026-11-11.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
import TUITesting

@MainActor
@Suite("A grouped form scrolls, as SwiftUI's does; a columns form does not")
struct FormGroupedScrollTests {
    /// Twenty toggles in two sections, under a button: taller than the
    /// twelve-row window in either style.
    private struct Page: View {
        let grouped: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button("Top") {}.focusID("top")
                if grouped {
                    form.formStyle(.grouped)
                } else {
                    form.formStyle(.columns)
                }
            }
        }

        private var form: some View {
            Form {
                Section("First") {
                    ForEach(0..<10, id: \.self) { index in
                        Toggle("Option \(index)", isOn: .constant(false)).focusID("option-\(index)")
                    }
                }
                Section("Second") {
                    ForEach(10..<20, id: \.self) { index in
                        Toggle("Option \(index)", isOn: .constant(false)).focusID("option-\(index)")
                    }
                }
            }
        }
    }

    private func app(grouped: Bool) -> TestApp {
        let app = TestApp(width: 50, height: 12) { Page(grouped: grouped) }
        app.advance(by: .milliseconds(20))
        return app
    }

    /// Whether `Option <index>` is drawn whole: its own line holds it, so
    /// `Option 1` does not match the line of `Option 15`.
    private func shows(_ app: TestApp, _ index: Int) -> Bool {
        app.screen.lines.contains { line in
            let words = line.split(separator: " ")
            return zip(words, words.dropFirst()).contains { $0 == "Option" && $1 == "\(index)" }
        }
    }

    @Test("Tab onto a row below the visible area scrolls it in, and Shift-Tab back up scrolls the first in")
    func tabRevealsTheFocusedRow() {
        let app = app(grouped: true)
        #expect(!shows(app, 15), "the form is not taller than the window: \(app.screen)")
        app.press(.tab, times: 16)
        #expect(app.focusedID == "option-15")
        #expect(shows(app, 15), "the focused row is not on screen: \(app.screen)")
        app.press(.tab, modifiers: .shift, times: 15)
        #expect(app.focusedID == "option-0")
        #expect(shows(app, 0), "the focused row is not on screen: \(app.screen)")
    }

    @Test("The wheel scrolls the form")
    func wheelScrolls() {
        let app = app(grouped: true)
        #expect(shows(app, 0))
        app.scroll(.down, by: 4)
        #expect(!shows(app, 0), "the wheel did not move the form: \(app.screen)")
        #expect(app.focusedID == "top", "the wheel moved the focus")
    }

    @Test("Page Down that the focused button leaves scrolls the form, Home scrolls it back")
    func pagingKeysScroll() {
        let app = app(grouped: true)
        #expect(app.focusedID == "top")
        app.press(.pageDown)
        #expect(!shows(app, 0), "Page Down did not move the form: \(app.screen)")
        #expect(app.focusedID == "top", "Page Down moved the focus")
        app.press(.home)
        #expect(shows(app, 0), "Home did not bring the form back: \(app.screen)")
    }

    @Test("The form itself is no Tab stop: Tab goes from the last row back to the first control")
    func formIsNoTabStop() {
        let app = app(grouped: true)
        app.press(.tab, times: 20)
        #expect(app.focusedID == "option-19")
        app.press(.tab)
        #expect(app.focusedID == "top", "Tab stopped on \(app.focusedID ?? "nothing")")
    }

    @Test("A columns form does not scroll, as SwiftUI's does not")
    func columnsFormDoesNotScroll() {
        let app = app(grouped: false)
        let before = app.screen.lines
        app.scroll(.down, by: 4)
        app.press(.pageDown)
        #expect(app.screen.lines == before, "the columns form moved: \(app.screen)")
    }
}
