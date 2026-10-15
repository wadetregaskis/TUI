//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FormGroupedRowTests.swift
//
//  A grouped form's labelled rows, laid out as SwiftUI's are (measured on
//  macOS 15.8, PROBES-1014/labeledcontent): the label at the leading edge, a
//  fixed value at the trailing edge, a field or a slider from 45% of the row.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("Grouped form rows")
struct FormGroupedRowTests {

    private func lines(_ view: some View, width: Int = 60) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: 12)).lines.map(\.stripped)
    }

    private func column(of text: String, in line: String) -> Int? {
        line.range(of: text).map { line.distance(from: line.startIndex, to: $0.lowerBound) }
    }

    /// A row wide enough to spread across: the field makes the form fill.
    private struct Rows: View {
        let label: String
        @State private var text = "alice"

        var body: some View {
            Form {
                LabeledContent("Name", value: "Alice")
                LabeledContent(label) { TextField("", text: $text) }
            }
            .formStyle(.grouped)
        }
    }

    @Test("A fixed value sits at the trailing edge, the label at the leading one")
    func fixedValueTrails() throws {
        let drawn = lines(Rows(label: "Email"))
        let row = try #require(drawn.first { $0.contains("Name") }, "drawn: \(drawn)")
        #expect(row.hasPrefix("Name"), "\(row.debugDescription)")
        #expect(row.hasSuffix("Alice"), "\(row.debugDescription)")
    }

    @Test("A field starts at 45% of the row")
    func fieldStartsAtTheShare() throws {
        let drawn = lines(Rows(label: "Email"))
        let row = try #require(drawn.first { $0.contains("Email") }, "drawn: \(drawn)")
        #expect(row.hasPrefix("Email"))
        #expect(column(of: "▐", in: row) == 27, "45% of 60: \(row.debugDescription)")
        #expect(row.hasSuffix("▌"), "and runs to the trailing edge: \(row.debugDescription)")
    }

    @Test("A field after a label longer than the share starts just after the label")
    func fieldFollowsALongLabel() throws {
        let label = "A label longer than the first share"
        let drawn = lines(Rows(label: label))
        let row = try #require(drawn.first { $0.contains(label) }, "drawn: \(drawn)")
        #expect(column(of: "▐", in: row) == label.count + 1, "\(row.debugDescription)")
    }

    @Test("Each line of a multi-line value ends at the trailing edge")
    func multilineValueTrails() throws {
        let drawn = lines(
            Form {
                LabeledContent("Address") { Text("1 Infinite Loop\nCupertino, CA") }
                LabeledContent("Email") { TextField("", text: .constant("")) }
            }
            .formStyle(.grouped))
        let first = try #require(drawn.firstIndex { $0.contains("Infinite") }, "drawn: \(drawn)")
        #expect(drawn[first].hasSuffix("1 Infinite Loop"), "\(drawn)")
        #expect(drawn[first + 1].hasSuffix("Cupertino, CA"), "\(drawn)")
    }

    @Test("A LabeledContent inside a grouped form's row spreads as the form's own rows do")
    func nestedLabeledContentSpreads() throws {
        let drawn = lines(
            Form {
                VStack(alignment: .leading) {
                    LabeledContent("Version", value: "1.0.3")
                }
                LabeledContent("Email") { TextField("", text: .constant("")) }
            }
            .formStyle(.grouped))
        let row = try #require(drawn.first { $0.contains("Version") }, "drawn: \(drawn)")
        let gap = try #require(column(of: "1.0.3", in: row)) - "Version".count
        #expect(gap > 10, "the value is across the row from its label: \(row.debugDescription)")
    }

    /// The SGR a cell's text is written in, just before `text` on its line.
    private func colour(of text: String, in view: some View) -> String? {
        let lines = renderToBuffer(view, context: makeRenderContext(width: 60, height: 12)).lines
        guard let line = lines.first(where: { $0.contains(text) }), let range = line.range(of: text) else {
            return nil
        }
        let before = line[..<range.lowerBound]
        return before.range(of: "\u{1B}[", options: .backwards).map { String(before[$0.lowerBound...]) }
    }

    @Test("A value's text is secondary, as SwiftUI's is; a field's own text is not")
    func valueTextIsSecondary() throws {
        let secondary = try #require(colour(of: "Alice", in: Text("Alice").foregroundStyle(.secondary)))
        let primary = try #require(colour(of: "Alice", in: Text("Alice")))
        #expect(secondary != primary, "precondition: the two styles differ")
        let form = Form {
            LabeledContent("Name", value: "Alice")
            LabeledContent("Email") { TextField("", text: .constant("bob")) }
        }
        .formStyle(.grouped)
        #expect(colour(of: "Alice", in: form) == secondary)
        let field = try #require(colour(of: "bob", in: TextField("", text: .constant("bob"))))
        #expect(colour(of: "bob", in: form) == field, "a field draws its text as it would anywhere")
    }

    @Test("A columns form keeps its label column")
    func columnsUnchanged() throws {
        let drawn = lines(
            Form {
                LabeledContent("Name", value: "Alice")
                LabeledContent("Email") { TextField("", text: .constant("")) }
            })
        let row = try #require(drawn.first { $0.contains("Name") }, "drawn: \(drawn)")
        #expect(row.hasPrefix(" Name Alice"), "right-aligned to the pillar, the value after: \(row.debugDescription)")
    }
}
