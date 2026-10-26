//  🖥️ TUI — A Terminal UI framework for Swift
//  ButtonStyleLabelTests.swift
//
//  A button style's `configuration.label` is a VIEW, as in SwiftUI, so the
//  style that every SwiftUI tutorial writes — the label, padded and
//  decorated — compiles and draws the button's label, whichever way the
//  button was built.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

/// The SwiftUI-tutorial shape: decorate the label view.
private struct Bracketing: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            Text("<")
            configuration.label
            Text(">")
        }
    }
}

@MainActor
@Suite("ButtonStyleConfiguration.label")
struct ButtonStyleLabelTests {

    private func line<V: View>(_ view: V) -> String {
        renderToBuffer(view, context: makeRenderContext(width: 20, height: 1))
            .lines.first?.stripped.trimmingCharacters(in: .whitespaces) ?? ""
    }

    @Test("A title button's label is its title, as a view")
    func titleLabel() {
        #expect(line(Button("Save") {}.buttonStyle(Bracketing())) == "<Save>")
    }

    @Test("A view-built button's label is the view it was built with")
    func viewLabel() {
        let button = Button(action: {}, label: { Text("Open").bold() })
        #expect(line(button.buttonStyle(Bracketing())) == "<Open>")
    }
}
