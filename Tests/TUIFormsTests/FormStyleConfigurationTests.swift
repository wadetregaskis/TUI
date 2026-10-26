//  🖥️ TUI — A Terminal UI framework for Swift
//  FormStyleConfigurationTests.swift
//
//  A built-in form style's body lays the form out in that style, and
//  `Form(configuration)` inside a custom style lays it out as the style outside
//  the custom one would — reading the rows through the configuration's erasure.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIForms
@testable import TUIFoundation
@testable import TUITestSupport

/// The current form, under a heading.
private struct Headed: FormStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("== Settings ==")
            Form(configuration)
        }
    }
}

/// Composes a built-in style's body.
private struct ComposesGrouped: FormStyle {
    func makeBody(configuration: Configuration) -> some View {
        GroupedFormStyle().makeBody(configuration: configuration)
    }
}

@MainActor
@Suite("Form style configurations")
struct FormStyleConfigurationTests {

    private func lines<V: View>(_ view: V) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: 30, height: 10))
            .lines.map { $0.stripped.replacingOccurrences(of: #" +$"#, with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
    }

    private var form: some View {
        Form {
            LabeledContent("Name", value: "Ada")
            LabeledContent("Language", value: "Swift")
        }
    }

    @Test("Form(configuration) lays the rows out as the style outside would")
    func configurationLaysOutRows() {
        let headed = lines(form.formStyle(Headed()))
        #expect(headed.first == "== Settings ==")
        #expect(Array(headed.dropFirst()) == lines(form), "the columns form, under the heading")
    }

    @Test("A built-in style's body is that style's layout")
    func builtInBodyComposes() {
        #expect(lines(form.formStyle(ComposesGrouped())) == lines(form.formStyle(.grouped)))
    }
}
