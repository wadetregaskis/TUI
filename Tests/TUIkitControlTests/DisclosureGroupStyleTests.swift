//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DisclosureGroupStyleTests.swift
//
//  `DisclosureGroupStyle`: a custom style lays the group out from its label,
//  its content and `$isExpanded`, and the content is built only when the style
//  places it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// Label and a +/- marker on one row, the content under it while expanded.
private struct PlusMinusStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Text(configuration.isExpanded ? "-" : "+")
                configuration.label
            }
            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}

/// Counts how often the content was built.
private final class BuildCount: @unchecked Sendable {
    var value = 0
}

@MainActor
@Suite("DisclosureGroupStyle")
struct DisclosureGroupStyleTests {
    private func lines<V: View>(_ view: V) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: 20, height: 4)).lines.map(\.stripped)
            .map { $0.replacingOccurrences(of: #" +$"#, with: "", options: .regularExpression) }
    }

    @Test("A custom style draws the group")
    func customStyle() {
        let open = DisclosureGroup("Info", isExpanded: .constant(true)) { Text("body") }
            .disclosureGroupStyle(PlusMinusStyle())
        #expect(lines(open).prefix(2) == ["- Info", "body"])
        let closed = DisclosureGroup("Info", isExpanded: .constant(false)) { Text("body") }
            .disclosureGroupStyle(PlusMinusStyle())
        #expect(lines(closed).first == "+ Info")
    }

    @Test("The automatic style is the look a group has always had")
    func automaticIsTheDefault() {
        let group = DisclosureGroup("Info", isExpanded: .constant(true)) { Text("body") }
        #expect(lines(group) == lines(group.disclosureGroupStyle(.automatic)))
    }

    @Test("A collapsed group builds none of its content")
    func collapsedBuildsNothing() {
        let count = BuildCount()
        _ = lines(DisclosureGroup("Info", isExpanded: .constant(false)) {
            count.value += 1
            return Text("body")
        })
        #expect(count.value == 0)
    }
}
