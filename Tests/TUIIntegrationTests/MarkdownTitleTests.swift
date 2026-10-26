//  🖥️ TUI — A Terminal UI framework for Swift
//  MarkdownTitleTests.swift
//
//  The Markdown SwiftUI parses in a control's title key, as it parses a
//  `Text`'s (decisions B87). Measured: `Button("**Save**") {}`, `Toggle`,
//  `Label`, `Link` and `LabeledContent` draw the bold; every control whose
//  SwiftUI label is a `Text` made from the key follows.
//
//  Each control is checked both ways round, as `LocalizedTitleTests` checks
//  lookups: a literal key is parsed, and a computed `String` holding the same
//  characters is drawn as written.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIApp
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Markdown in control title keys")
struct MarkdownTitleTests {

    /// The words the key below reads as once parsed.
    static let words = "Go bold now"

    /// The same characters as the literal keys below, computed, so they are
    /// never parsed.
    static var computed: String { "Go " + "**bold** now" }

    /// The rendered text of a view: its lines, stripped of styling when
    /// `stripped`.
    private func rendered(_ view: some View, stripped: Bool = true) -> String {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 44, availableHeight: 8, environment: environment, tuiContext: tui)
        let lines = renderToBuffer(view, context: context).lines
        return (stripped ? lines.map(\.stripped) : lines).joined(separator: "\n")
    }

    /// Asserts that `literal` draws the key's words without their markup, and
    /// `computed` draws the markup as written.
    private func expectParsed(
        _ literal: some View, _ computed: some View,
        _ label: Comment, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let parsed = rendered(literal)
        #expect(parsed.contains(Self.words) && !parsed.contains("*"), "\(label): \(parsed)", sourceLocation: sourceLocation)
        #expect(rendered(computed).contains(Self.computed), label, sourceLocation: sourceLocation)
    }

    @Test("A styled key draws its style, not its markup")
    func boldIsDrawn() {
        let box = Box(false)
        let drawn = rendered(Toggle("Go **bold** now", isOn: box.binding), stripped: false)
        let plain = rendered(Toggle(Self.computed, isOn: box.binding), stripped: false)
        // SGR 1 is bold, alone or among other parameters.
        let bold = /\u{1B}\[(?:[0-9;]*;)?1(?:;[0-9;]*)?m/
        #expect(drawn.contains(bold), "\(drawn)")
        #expect(!plain.contains(bold), "\(plain)")
    }

    @Test("Buttons, menus and links")
    func buttons() {
        let url = URL(string: "https://example.com")!
        expectParsed(Button("Go **bold** now") {}, Button(Self.computed) {}, "Button")
        expectParsed(
            Button("Go **bold** now", role: .destructive) {},
            Button(Self.computed, role: .destructive) {}, "Button(role:)")
        expectParsed(
            Button("Go **bold** now", systemImage: "star") {},
            Button(Self.computed, systemImage: "star") {}, "Button(systemImage:)")
        expectParsed(
            Menu("Go **bold** now") { Button("x") {} }, Menu(Self.computed) { Button("x") {} }, "Menu")
        expectParsed(
            Link("Go **bold** now", destination: url), Link(Self.computed, destination: url), "Link")
        expectParsed(
            NavigationLink("Go **bold** now", value: 1), NavigationLink(Self.computed, value: 1),
            "NavigationLink")
    }

    @Test("Value controls")
    func valueControls() {
        let flag = Box(false)
        let choice = Box(1)
        let count = Box(0)
        let level = Box(0.5)
        let date = Box(Date(timeIntervalSince1970: 0))
        let colour = Box(Color.red)
        expectParsed(
            Toggle("Go **bold** now", isOn: flag.binding), Toggle(Self.computed, isOn: flag.binding), "Toggle")
        expectParsed(
            Toggle("Go **bold** now", systemImage: "star", isOn: flag.binding),
            Toggle(Self.computed, systemImage: "star", isOn: flag.binding), "Toggle(systemImage:)")
        expectParsed(
            Picker("Go **bold** now", selection: choice.binding) { Text("a").tag(1) },
            Picker(Self.computed, selection: choice.binding) { Text("a").tag(1) }, "Picker")
        expectParsed(
            Stepper("Go **bold** now", value: count.binding),
            Stepper(Self.computed, value: count.binding), "Stepper")
        expectParsed(
            Stepper("Go **bold** now", onIncrement: {}, onDecrement: {}),
            Stepper(Self.computed, onIncrement: {}, onDecrement: {}), "Stepper(onIncrement:)")
        expectParsed(
            Slider("Go **bold** now", value: level.binding),
            Slider(Self.computed, value: level.binding), "Slider")
        expectParsed(
            DatePicker("Go **bold** now", selection: date.binding),
            DatePicker(Self.computed, selection: date.binding), "DatePicker")
        expectParsed(
            ColorPicker("Go **bold** now", selection: colour.binding),
            ColorPicker(Self.computed, selection: colour.binding), "ColorPicker")
    }

    @Test("Read-outs and labels")
    func readOuts() {
        expectParsed(ProgressView("Go **bold** now"), ProgressView(Self.computed), "ProgressView")
        expectParsed(
            ProgressView("Go **bold** now", value: 0.5), ProgressView(Self.computed, value: 0.5),
            "ProgressView(value:)")
        expectParsed(Gauge("Go **bold** now", value: 0.5), Gauge(Self.computed, value: 0.5), "Gauge")
        expectParsed(
            Label("Go **bold** now", systemImage: "star"), Label(Self.computed, systemImage: "star"), "Label")
        expectParsed(
            LabeledContent("Go **bold** now") { Text("v") }, LabeledContent(Self.computed) { Text("v") },
            "LabeledContent")
        expectParsed(
            LabeledContent("Go **bold** now", value: "v"), LabeledContent(Self.computed, value: "v"),
            "LabeledContent(value:)")
        expectParsed(
            ContentUnavailableView("Go **bold** now"), ContentUnavailableView(Self.computed),
            "ContentUnavailableView")
        expectParsed(
            ContentUnavailableView("Go **bold** now", systemImage: "star"),
            ContentUnavailableView(Self.computed, systemImage: "star"), "ContentUnavailableView(systemImage:)")
    }

    @Test("Containers")
    func containers() {
        expectParsed(
            List { Section("Go **bold** now") { Text("row") } },
            List { Section(Self.computed) { Text("row") } }, "Section")
        expectParsed(
            DisclosureGroup("Go **bold** now") { Text("row") },
            DisclosureGroup(Self.computed) { Text("row") }, "DisclosureGroup")
        expectParsed(
            GroupBox("Go **bold** now") { Text("row") }, GroupBox(Self.computed) { Text("row") }, "GroupBox")
    }

    /// A row for the table below.
    struct Row: Identifiable {
        let id = 1
        let name = "cell"
    }

    @Test("A field's title, a column's header and a tab's title draw their words, unstyled")
    func titlesDrawnAsStrings() {
        // Measured on macOS 15 (2026-10-18): SwiftUI parses all three. A
        // field's title is its placeholder, drawn as plain words; a header
        // and a tab draw the words here in their own style (decisions
        // B-PARITYMISC-3).
        let text = Box("")
        expectParsed(
            TextField("Go **bold** now", text: text.binding), TextField(Self.computed, text: text.binding),
            "TextField")
        expectParsed(
            TextField("Go **bold** now", text: text.binding, axis: .vertical),
            TextField(Self.computed, text: text.binding, axis: .vertical), "TextField(axis:)")
        let bold = /\u{1B}\[(?:[0-9;]*;)?1(?:;[0-9;]*)?m/
        let placeholder = rendered(TextField("Go **bold** now", text: text.binding), stripped: false)
        #expect(!placeholder.contains(bold), "a placeholder is plain words, as SwiftUI's is: \(placeholder)")
        expectParsed(
            Table([Row()]) { TableColumn("Go **bold** now", value: \.name) },
            Table([Row()]) { TableColumn(Self.computed, value: \.name) }, "TableColumn")
        expectParsed(
            TabView { Tab("Go **bold** now", systemImage: "star") { Text("x") } },
            TabView { Tab(Self.computed, systemImage: "star") { Text("x") } }, "Tab")
    }

    /// Somewhere for a `Binding` to point, as in `LocalizedTitleTests`.
    final class Box<T> {
        var value: T
        init(_ value: T) { self.value = value }
        var binding: Binding<T> {
            Binding(get: { self.value }, set: { self.value = $0 })
        }
    }

    /// A styled title keeps its plain words as the title, for what reads it as
    /// text.
    @Test("A styled Button keeps its plain words as its title")
    func plainTitle() {
        let button = Button("Go **bold** now") {}
        #expect(button.label == Self.words)
        #expect(button.labelView != nil)
        #expect(Button("plain words") {}.labelView == nil, "a key with no Markdown keeps the string path")
        // Drawn as its Text, it sits in the same chrome as its words would.
        #expect(rendered(button) == rendered(Button(Self.words) {}))
        #expect(rendered(button.buttonStyle(.plain)) == rendered(Button(Self.words) {}.buttonStyle(.plain)))
    }
}
