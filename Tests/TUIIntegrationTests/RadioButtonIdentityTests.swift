//  🖥️ TUI — A Terminal UI framework for Swift
//  RadioButtonIdentityTests.swift
//
//  A radio group's options are known by their values, not their places: an
//  option's content keeps its `@State` when the options are reordered, and the
//  keyboard's cursor stays on its option, or on the last one when the options
//  shrink from under it. An option is its whole label, every line of it: a
//  click on a label's second line chooses it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
import TUITesting

/// What the page draws, changed from the test between frames.
@Observable
@MainActor
private final class Model {
    var choice = "a"
    /// The options in reverse order.
    var reversed = false
    /// Only the first two options.
    var shrunk = false
}

/// A button that counts its presses in its own `@State`.
private struct Counter: View {
    @State private var count = 0

    var body: some View {
        Button("Count \(String(count))") { count += 1 }
    }
}

private struct RadioApp: App {
    let model: Model?

    init() { model = nil }

    init(_ model: Model) { self.model = model }

    var body: some Scene {
        WindowGroup {
            if let model { RadioPage(model: model) }
        }
    }
}

private struct RadioPage: View {
    let model: Model

    var body: some View {
        let values = model.shrunk ? ["a", "b"] : ["a", "b", "c"]
        VStack(alignment: .leading, spacing: 0) {
            RadioButtonGroup(
                selection: Bindable(model).choice,
                items: (model.reversed ? values.reversed() : values).map { value in
                    RadioButtonItem(value) {
                        Counter()
                    } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: "Option \(value)")
                            Text(verbatim: "more \(value)")
                        }
                    }
                })
            Text(verbatim: "picked \(model.choice)")
        }
    }
}

@MainActor
private final class Harness {
    let model = Model()
    let app: TestApp
    private var now: Int64 = 0

    init() {
        app = TestApp(RadioApp(model), width: 40, height: 16)
        frame()
        frame()
    }

    func frame() {
        now += 16_666_667
        app.frame(atNanos: now)
    }

    var screen: String { app.screen.lines.joined(separator: "\n") }

    /// The line `offset` rows below option `value`'s first.
    func line(_ offset: Int, belowOption value: String) throws -> String {
        let lines = app.screen.lines
        let row = try #require(lines.firstIndex { $0.contains("Option \(value)") }, "\(screen)")
        return try #require(lines.indices.contains(row + offset) ? lines[row + offset] : nil, "\(screen)")
    }

    /// How many options show the selected-or-focused bullet.
    var bullets: Int {
        app.screen.lines.filter { $0.contains(TerminalSymbols.radioSelected) }.count
    }
}

@MainActor
@Suite("A radio group knows its options by value")
struct RadioButtonIdentityTests {
    @Test("An option's content keeps its state when the options are reordered")
    func contentFollowsItsOption() throws {
        let harness = Harness()
        try harness.app.click("Count 0")  // option a's, the selected one's
        harness.frame()
        #expect(try harness.line(2, belowOption: "a").contains("Count 1"), "\(harness.screen)")
        harness.model.reversed = true
        harness.frame()
        #expect(try harness.line(2, belowOption: "a").contains("Count 1"), "\(harness.screen)")
        #expect(try harness.line(2, belowOption: "b").contains("Count 0"), "\(harness.screen)")
    }

    @Test("A click on the second line of an option's label chooses it")
    func secondLabelLineIsTheOption() throws {
        let harness = Harness()
        try harness.app.click("more b")
        harness.frame()
        #expect(harness.model.choice == "b", "\(harness.screen)")
    }

    @Test("The cursor stays on its option when the options are reordered")
    func cursorFollowsItsOption() throws {
        let harness = Harness()
        try harness.app.click("Option c")
        harness.frame()
        #expect(harness.bullets == 1, "sanity: one option marked:\n\(harness.screen)")
        harness.model.reversed = true
        harness.frame()
        #expect(harness.bullets == 1, "the cursor stayed at its place, on another option:\n\(harness.screen)")
    }

    @Test("The cursor on the last option moves to the new last when the options shrink")
    func cursorClampsWhenTheOptionsShrink() throws {
        let harness = Harness()
        try harness.app.click("Option c")
        harness.frame()
        harness.model.shrunk = true
        harness.frame()
        // c, still the selection, is gone; the cursor is on b, the focused group shows it.
        #expect(try harness.line(0, belowOption: "b").contains(TerminalSymbols.radioSelected), "\(harness.screen)")
    }
}
