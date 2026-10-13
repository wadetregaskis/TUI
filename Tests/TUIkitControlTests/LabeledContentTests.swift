//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LabeledContentTests.swift
//
//  `LabeledContent` OUTSIDE a Form, where it lays itself out. (Inside one the
//  form owns the row — see `FormTests`.)
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("LabeledContent standalone")
struct LabeledContentTests {

    private func line(_ view: some View, width: Int = 40) -> String {
        renderToBuffer(view, context: makeRenderContext(width: width, height: 3))
            .lines.first?.stripped ?? ""
    }

    @Test("A fixed value sits at the trailing edge")
    func valueIsTrailing() {
        let out = line(LabeledContent("Version", value: "1.0.3"))
        #expect(out.hasPrefix("Version"), "label leads: \(out.debugDescription)")
        #expect(
            out.trimmingCharacters(in: .whitespaces).hasSuffix("1.0.3"),
            "value trails: \(out.debugDescription)")
    }

    /// The value trails, and so does each line of a value of several: as the
    /// trailing value of SwiftUI's grouped `Form` does, where "short" over "a
    /// much longer line" ends both lines at the trailing edge (measured,
    /// `Tools/SwiftUIProbes/Trailing values and labels`). Found by the BUGS13
    /// lane's review: once a frame placed its content as one block
    /// (e9c065a9e), the trailing frame drew the lines leading inside a block
    /// at the trailing edge, "short" left of the longer line's start.
    @Test("Each line of a multi-line value ends at the trailing edge")
    func multilineValueTrailsLineByLine() throws {
        let lines = renderToBuffer(
            LabeledContent { Text("short\na much longer line") } label: { Text("Notes") },
            context: makeRenderContext(width: 40, height: 3)
        ).lines.map(\.stripped)
        func end(of text: String, in line: String) -> Int? {
            line.range(of: text).map { line.distance(from: line.startIndex, to: $0.upperBound) }
        }
        let first = try #require(lines.firstIndex { $0.contains("short") }, "drawn: \(lines)")
        #expect(lines[first].hasPrefix("Notes"), "the label leads: \(lines)")
        let shortEnd = end(of: "short", in: lines[first])
        let longEnd = lines.dropFirst(first + 1).first.flatMap { end(of: "a much longer line", in: $0) }
        #expect(longEnd == 40, "the longer line trails: \(lines)")
        #expect(shortEnd == longEnd, "each line ends at the trailing edge: \(lines)")
    }

    @Test("A flexible control gets the whole remainder, not half of it")
    func flexibleContentTakesTheRest() {
        // The bug: the body put a `Spacer` between the label and the content,
        // and a spacer is width-flexible exactly like a `TextField` — so the
        // stack split the leftover evenly and a labelled field spent half the
        // line on the gap in front of it.
        let out = line(
            LabeledContent("Note") { TextField("", text: .constant("")) }, width: 40)
        let fieldStart = out.firstIndex(of: "▐").map { out.distance(from: out.startIndex, to: $0) }
        #expect(fieldStart != nil, "a field was drawn: \(out.debugDescription)")
        // "Note" (4) + one space of stack spacing: the field starts right after
        // the label, not halfway across the line.
        #expect(fieldStart == 5, "the field starts at \(fieldStart ?? -1): \(out.debugDescription)")
    }
}
