//  🖥️ TUI — A Terminal UI framework for Swift
//  ForegroundStyleReachesContentTests.swift
//
//  `.foregroundStyle(_:)` on a control colours the text in it that the app
//  supplied or the user typed (CLAUDE.md: a control's modifiers MUST reach its
//  content), on every control that draws such text, where SwiftUI's does
//  (measured on macOS 15.8:
//  `Tools/SwiftUIProbes/Foreground style on controls (FGSWEEP)/fgsweep.out`).
//
//  Found as a class: the TextEditor lane found TextField and SecureField drawing
//  their text in the palette's foreground whatever the style said, and a past
//  review found "one site of a class" fixes recurring, so every control is
//  swept here, not just those two. One family of probes a fix.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// A control drawn under `.foregroundStyle(_:)`, and the words in it that take
/// the style, as they do in SwiftUI.
struct ForegroundStyleProbe: CustomStringConvertible, Sendable {
    let description: String
    let words: [String]
    let make: @MainActor @Sendable () -> AnyView

    init<V: View>(_ name: String, _ words: [String] = ["Hello"], _ make: @escaping @MainActor @Sendable () -> V) {
        description = name
        self.words = words
        self.make = { AnyView(make()) }
    }

    /// The controls that took the style before the sweep, as SwiftUI's do.
    static let matched: [Self] = [
        Self("Text") { Text("Hello") },
        Self("Label") { Label("Hello", systemImage: "star") },
        Self("Toggle(.switch)") { Toggle("Hello", isOn: .constant(true)).toggleStyle(.switch) },
        Self("Toggle(.checkbox)") { Toggle("Hello", isOn: .constant(true)).toggleStyle(.checkbox) },
        Self("Picker(.menu)'s label") {
            Picker("Hello", selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) }.pickerStyle(.menu)
        },
        Self("Picker(.radioGroup)", ["Hello", "One", "Two"]) {
            Picker("Hello", selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) }
                .pickerStyle(.radioGroup)
        },
        Self("Picker(.inline)", ["Hello", "One", "Two"]) {
            Picker("Hello", selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) }.pickerStyle(.inline)
        },
        Self("Stepper") { Stepper("Hello", value: .constant(1)) },
        Self("Slider") { Slider(value: .constant(0.5)) { Text("Hello") }.frame(width: 30) },
        Self("TextEditor", ["typed"]) { TextEditor(text: .constant("typed")).frame(width: 20, height: 3) },
        Self("DatePicker's label") {
            DatePicker("Hello", selection: .constant(Date(timeIntervalSince1970: 0)), displayedComponents: .date)
        },
        Self("List row") { List { Text("Hello") }.frame(height: 3) },
        Self("Section header", ["Header", "Row"]) { List { Section("Header") { Text("Row") } }.frame(height: 4) },
        Self("Form row") { Form { Toggle("Hello", isOn: .constant(true)) } },
        Self("GroupBox", ["Title", "Body"]) { GroupBox("Title") { Text("Body") } },
        Self("LabeledContent", ["Key", "Value"]) { LabeledContent("Key", value: "Value") },
        Self("ProgressView") { ProgressView("Hello", value: 0.5) },
        Self("Gauge") { Gauge(value: 0.5) { Text("Hello") } },
    ]

    /// A value in a grouped form or a list's row, which is in the secondary
    /// tier unless a style is stated, and then takes it whole.
    static let formValues: [Self] = [
        Self("A grouped form's value", ["Key", "Value"]) {
            Form { LabeledContent("Key", value: "Value") }.formStyle(.grouped)
        },
        Self("A list row's value", ["Key", "Value"]) { List { LabeledContent("Key", value: "Value") }.frame(height: 3) },
    ]
}

@MainActor
@Suite("A control's .foregroundStyle reaches the text in it")
struct ForegroundStyleReachesContentTests {
    /// A colour no palette draws text in.
    static let stated = Color.rgb(222, 17, 99)

    /// The ink a cell drawn in `colour` states.
    static func ink(_ colour: Color) -> SGRState.Colour? {
        var style = TextStyle()
        style.foregroundColor = colour.opaqueSpelling
        var state = SGRState()
        if let sequence = ANSIRenderer.styleSequence(for: style) { state.apply(sequence) }
        return state.foregroundColour
    }

    /// `view` under `.foregroundStyle(stated)`, below a button that holds the
    /// focus so the control is drawn at rest, as the screen shows it.
    static func rows(_ view: some View) -> [[PaintedCell]] {
        writtenRows(
            of: VStack(alignment: .leading) {
                Button("Anchor") {}
                view.foregroundStyle(stated)
            }, width: 50, height: 12)
    }

    /// The cells of the first place `word` shows in `rows`, or `nil` where it
    /// does not show.
    static func cells(of word: String, in rows: [[PaintedCell]]) -> ArraySlice<PaintedCell>? {
        let target = Array(word)
        for row in rows where target.count <= row.count {
            let glyphs = row.map(\.glyph)
            for start in 0...(glyphs.count - target.count) where Array(glyphs[start..<(start + target.count)]) == target {
                return row[start..<(start + target.count)]
            }
        }
        return nil
    }

    /// Every cell of every word of `probe` is in the stated colour.
    static func expectStyled(_ probe: ForegroundStyleProbe) throws {
        let drawn = Self.rows(probe.make())
        let screen = drawn.map { String($0.map(\.glyph)) }.joined(separator: "\n")
        for word in probe.words {
            let found = try #require(Self.cells(of: word, in: drawn), "\(word) not on screen:\n\(screen)")
            for cell in found {
                #expect(cell.ink == Self.ink(Self.stated), "\(probe): '\(cell.glyph)' of \(word) is not in the style")
            }
        }
    }

    @Test("The controls that already took the style still do", arguments: ForegroundStyleProbe.matched)
    func matched(_ probe: ForegroundStyleProbe) throws { try Self.expectStyled(probe) }

    @Test("A form value takes a stated style whole, where it is otherwise secondary",
        arguments: ForegroundStyleProbe.formValues)
    func formValues(_ probe: ForegroundStyleProbe) throws { try Self.expectStyled(probe) }
}

// MARK: - Fields

extension ForegroundStyleProbe {
    /// What a field's user typed, in every field style.
    static let fields: [Self] = [
        Self("TextField", ["typed"]) { TextField("hint", text: .constant("typed")) },
        Self("TextField(.plain)", ["typed"]) { TextField("hint", text: .constant("typed")).textFieldStyle(.plain) },
        Self("TextField(.roundedBorder)", ["typed"]) {
            TextField("hint", text: .constant("typed")).textFieldStyle(.roundedBorder)
        },
        Self("TextField(.squareBorder)", ["typed"]) {
            TextField("hint", text: .constant("typed")).textFieldStyle(.squareBorder)
        },
        Self("TextField(axis: .vertical)", ["typed"]) { TextField("hint", text: .constant("typed"), axis: .vertical) },
        Self("SecureField", [String(repeating: TerminalSymbols.maskBullet, count: 5)]) {
            SecureField("hint", text: .constant("typed"))
        },
        Self("A TextField in a Form", ["typed"]) { Form { TextField("Label", text: .constant("typed")) } },
        Self("A TextField as a grouped form's value", ["Email", "typed"]) {
            Form { LabeledContent("Email") { TextField("", text: .constant("typed")) } }.formStyle(.grouped)
        },
        Self("The search field", ["query", "Body"]) {
            NavigationStack { Text("Body").searchable(text: .constant("query")) }.frame(height: 6)
        },
    ]
}

extension ForegroundStyleReachesContentTests {
    @Test("A field's typed text takes the style", arguments: ForegroundStyleProbe.fields)
    func fields(_ probe: ForegroundStyleProbe) throws { try Self.expectStyled(probe) }

    @Test("A field's prompt keeps its own colour under a style, as SwiftUI's does", arguments: [false, true])
    func promptKeepsItsColour(secure: Bool) throws {
        let field =
            secure
            ? AnyView(SecureField("hint", text: .constant(""))) : AnyView(TextField("hint", text: .constant("")))
        let cells = try #require(Self.cells(of: "hint", in: Self.rows(field)))
        for cell in cells { #expect(cell.ink != Self.ink(Self.stated), "'\(cell.glyph)'") }
    }
}
