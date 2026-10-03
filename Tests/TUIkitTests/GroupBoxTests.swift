//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GroupBoxTests.swift
//
//  SwiftUI's GroupBox and GroupBoxStyle.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// The current box, preceded by a marker.
private struct Marked: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(">>")
            GroupBox(configuration)
        }
    }
}

/// Label and content side by side, unboxed.
private struct Inline: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 1) {
            configuration.label
            configuration.content
        }
    }
}

@MainActor
@Suite("GroupBox")
struct GroupBoxTests {

    private func lines<V: View>(_ view: V) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: 24, height: 8))
            .lines.map { $0.stripped.replacingOccurrences(of: #" +$"#, with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
    }

    @Test("A titled group box draws its title, then its content in a box")
    func titled() {
        let drawn = lines(GroupBox("Terms") { Text("Agree?") })
        #expect(drawn.first == "Terms")
        #expect(drawn.count == 4, "title, the box's top, the content, the box's bottom: \(drawn)")
        #expect(drawn[2].contains("Agree?"))
        #expect(drawn[1] != drawn[2] && !drawn[1].contains("Agree?"), "the content is boxed")
    }

    @Test("An unlabelled group box is just the box")
    func unlabelled() {
        #expect(lines(GroupBox { Text("Agree?") }).count == 3)
    }

    @Test("A custom style lays the box out")
    func customStyle() {
        #expect(lines(GroupBox("Terms") { Text("Agree?") }.groupBoxStyle(Inline())) == ["Terms Agree?"])
    }

    @Test("GroupBox(configuration) draws the box as the style outside would")
    func configurationDecorates() {
        let plain = lines(GroupBox("Terms") { Text("Agree?") })
        #expect(lines(GroupBox("Terms") { Text("Agree?") }.groupBoxStyle(Marked())) == [">>"] + plain)
    }
}
