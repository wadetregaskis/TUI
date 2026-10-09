//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LabeledContentStyleTests.swift
//
//  `LabeledContentStyle` and the configuration initialisers of `Label` and
//  `LabeledContent`: a custom style takes a row over, in a form or out of one,
//  and a style that draws `Label(configuration)` / `LabeledContent(configuration)`
//  decorates the look the style outside it would give.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTextInput

/// Label above content, as SwiftUI's documentation sketches a custom style.
private struct Stacked: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            configuration.label
            configuration.content
        }
    }
}

/// Decorates whatever the content would otherwise look like.
private struct Bracketed: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            Text("[")
            LabeledContent(configuration)
            Text("]")
        }
    }
}

/// Decorates whatever the label would otherwise look like.
private struct StarredLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            Text("*")
            Label(configuration)
        }
    }
}

@MainActor
@Suite("LabeledContentStyle")
struct LabeledContentStyleTests {

    private func lines<V: View>(_ view: V, width: Int = 24) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: 6))
            .lines.map { $0.stripped.replacingOccurrences(of: #" +$"#, with: "", options: .regularExpression) }
    }

    @Test("The automatic style is the layout labeled content always had")
    func automaticIsTheDefault() {
        let row = LabeledContent("Name", value: "Ada")
        #expect(lines(row) == lines(row.labeledContentStyle(.automatic)))
        #expect(lines(row).first?.hasPrefix("Name") == true && lines(row).first?.hasSuffix("Ada") == true)
    }

    @Test("A custom style lays the row out")
    func customStyle() {
        #expect(Array(lines(LabeledContent("Name", value: "Ada").labeledContentStyle(Stacked())).prefix(2))
            == ["Name", "Ada"])
    }

    @Test("A custom style takes a form's row over too")
    func customStyleInForm() {
        let form = Form {
            LabeledContent("Name", value: "Ada")
        }
        let firstTwo: [String] = lines(form.labeledContentStyle(Stacked())).filter { !$0.isEmpty }.prefix(2)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(firstTwo == ["Name", "Ada"])
    }

    @Test("LabeledContent(configuration) draws the content as the style outside would")
    func configurationDecoratesOuter() {
        let plain = lines(LabeledContent("Name", value: "Ada"), width: 22)[0]
        let bracketed = lines(LabeledContent("Name", value: "Ada").labeledContentStyle(Bracketed()))[0]
        #expect(bracketed.hasPrefix("[Name") && bracketed.hasSuffix("Ada]"), "\(bracketed) around \(plain)")
    }

    @Test("Label(configuration) draws the label as the style outside would")
    func labelConfiguration() {
        let label = Label("Star", systemImage: "star")
        let starred = lines(label.labelStyle(StarredLabel()))[0]
        #expect(starred == "*" + lines(label)[0])
        #expect(lines(label.labelStyle(StarredLabel()).labelStyle(.titleOnly))[0] == "*Star",
                "inside, the title-only style that was in force outside")
    }
}

@MainActor
@Suite("Label spacing")
struct LabelSpacingTests {
    private func line<V: View>(_ view: V) -> String {
        renderToBuffer(view, context: makeRenderContext(width: 24, height: 1))
            .lines.first?.stripped.replacingOccurrences(of: #" +$"#, with: "", options: .regularExpression) ?? ""
    }

    private func titleColumn(_ drawn: String) -> Int? {
        drawn.range(of: "Star").map { drawn[..<$0.lowerBound].count }
    }

    @Test("The gap between icon and title is one cell unless set")
    func spacing() {
        let label = Label { Text("Star") } icon: { Text("*") }
        #expect(line(label) == "* Star")
        #expect(line(label.labelIconToTitleSpacing(3)) == "*   Star")
        #expect(line(label.labelIconToTitleSpacing(0)) == "*Star")
    }

    @Test("A reserved icon width lines titles up beside icons of different widths")
    func reservedWidth() {
        let narrow = Label { Text("Star") } icon: { Text("*") }
        let wide = Label { Text("Star") } icon: { Text("**") }
        #expect(titleColumn(line(narrow.labelReservedIconWidth(3)))
            == titleColumn(line(wide.labelReservedIconWidth(3))))
        #expect(titleColumn(line(narrow)) != titleColumn(line(wide)))
    }
}
