//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ControlGroupTests.swift
//
//  SwiftUI's ControlGroup and its styles.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation

/// Puts the label in front of the current group.
private struct Prefixed: ControlGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 1) {
            configuration.label
            ControlGroup(configuration)
        }
    }
}

@MainActor
@Suite("ControlGroup")
struct ControlGroupTests {

    private func line<V: View>(_ view: V) -> String {
        renderToBuffer(view, context: makeRenderContext(width: 40, height: 3))
            .lines.first?.stripped.replacingOccurrences(of: #" +$"#, with: "", options: .regularExpression) ?? ""
    }

    private var group: some View {
        ControlGroup {
            Button("Bold") {}
            Button("Italic") {}
        } label: {
            Text("Format")
        }
    }

    @Test("The default style draws the controls side by side, touching")
    func automatic() {
        let drawn = line(group)
        #expect(drawn.contains("Bold") && drawn.contains("Italic"))
        #expect(!drawn.contains("Format"), "the label is for a menu or an overflow, not drawn beside")
        let bold = line(Button("Bold") {}), italic = line(Button("Italic") {})
        #expect(drawn.hasPrefix(bold + italic), "no gap: \(drawn)")
    }

    @Test("The menu style puts the controls behind the label")
    func menuStyle() {
        let drawn = line(group.controlGroupStyle(.menu))
        #expect(drawn.contains("Format") && !drawn.contains("Italic"))
    }

    @Test("ControlGroup(configuration) keeps the label and draws as the style outside")
    func configuration() {
        let drawn = line(group.controlGroupStyle(Prefixed()))
        #expect(drawn.hasPrefix("Format ") && drawn.contains("Bold") && drawn.contains("Italic"))
        let overMenu = line(group.controlGroupStyle(Prefixed()).controlGroupStyle(.menu))
        #expect(overMenu.hasPrefix("Format ") && !overMenu.contains("Italic"),
                "inside, the menu style that was in force outside: \(overMenu)")
    }
}
