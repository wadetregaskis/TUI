//  🖥️ TUI — A Terminal UI framework for Swift
//  LabeledContentTests.swift
//
//  `LabeledContent` OUTSIDE a Form, where it lays itself out. (Inside one the
//  form owns the row — see `FormTests`.)
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("LabeledContent standalone")
struct LabeledContentTests {

    private func line(_ view: some View, width: Int = 40) -> String {
        renderToBuffer(view, context: makeRenderContext(width: width, height: 3))
            .lines.first?.stripped ?? ""
    }

    @Test("On its own, a fixed value follows its label and the row hugs, as SwiftUI's does")
    func standaloneValueFollowsLabel() {
        let out = line(LabeledContent("Version", value: "1.0.3"))
        #expect(out.trimmingCharacters(in: .whitespaces) == "Version 1.0.3", "\(out.debugDescription)")
    }

    @Test("On its own, the lines of a multi-line value lead after the label")
    func standaloneMultilineValueLeads() {
        let lines = renderToBuffer(
            LabeledContent { Text("short\na much longer line") } label: { Text("Notes") },
            context: makeRenderContext(width: 40, height: 3)
        ).lines.map(\.stripped)
        let starts = lines.compactMap { line in
            ["short", "a much longer line"].lazy.compactMap { line.range(of: $0) }.first
                .map { line.distance(from: line.startIndex, to: $0.lowerBound) }
        }
        #expect(starts == [6, 6], "both lines start after \"Notes \": \(lines)")
    }

    @Test("In a list's row, a fixed value sits at the trailing edge")
    func listRowValueIsTrailing() throws {
        let lines = renderToBuffer(
            List { LabeledContent("Version", value: "1.0.3") },
            context: makeRenderContext(width: 40, height: 4)
        ).lines.map(\.stripped)
        let row = try #require(lines.first { $0.contains("Version") }, "drawn: \(lines)")
        let label = try #require(row.range(of: "Version"))
        let value = try #require(row.range(of: "1.0.3"))
        let gap = row.distance(from: label.upperBound, to: value.lowerBound)
        #expect(gap > 20, "the value is across the row from its label: \(row.debugDescription)")
    }

    @Test("In a list's row, a value's text is secondary; on its own it is not")
    func listRowValueIsSecondary() throws {
        func colour(of view: some View) -> String? {
            let lines = renderToBuffer(view, context: makeRenderContext(width: 40, height: 4)).lines
            guard let line = lines.first(where: { $0.contains("1.0.3") }), let range = line.range(of: "1.0.3")
            else { return nil }
            let before = line[..<range.lowerBound]
            return before.range(of: "\u{1B}[", options: .backwards).map { String(before[$0.lowerBound...]) }
        }
        let secondary = try #require(colour(of: Text("1.0.3").foregroundStyle(.secondary)))
        let primary = try #require(colour(of: Text("1.0.3")))
        #expect(colour(of: List { LabeledContent("Version", value: "1.0.3") }) == secondary)
        #expect(colour(of: LabeledContent("Version", value: "1.0.3")) == primary)
    }

    /// The value trails, and so does each line of a value of several: as the
    /// trailing value of SwiftUI's grouped `Form` does, where "short" over "a
    /// much longer line" ends both lines at the trailing edge (measured,
    /// `Tools/SwiftUIProbes/Trailing values and labels`). Found by the BUGS13
    /// lane's review: once a frame placed its content as one block
    /// (e9c065a9e), the trailing frame drew the lines leading inside a block
    /// at the trailing edge, "short" left of the longer line's start.
    @Test("In a list's row, each line of a multi-line value ends at the trailing edge")
    func multilineValueTrailsLineByLine() throws {
        let lines = renderToBuffer(
            LabeledContent { Text("short\na much longer line") } label: { Text("Notes") }
                .environment(\.labeledContentPlacement, .listRow),
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

    /// Found by the BUGS13 lane's second review: the value's trailing lines
    /// were a `.multilineTextAlignment(.trailing)` written inside the
    /// `LabeledContent`, which overrode one the app wrote on it. The value
    /// trails its lines only where nothing states an alignment.
    @Test("An alignment stated on a LabeledContent wins over its value's trailing lines",
          arguments: [TextAlignment.leading, .center])
    func statedAlignmentWins(alignment: TextAlignment) throws {
        let lines = renderToBuffer(
            LabeledContent { Text("short\na much longer line") } label: { Text("Notes") }
                .multilineTextAlignment(alignment)
                .environment(\.labeledContentPlacement, .listRow),
            context: makeRenderContext(width: 40, height: 3)
        ).lines.map(\.stripped)
        func range(of text: String, in line: String) -> (start: Int, end: Int)? {
            line.range(of: text).map {
                (line.distance(from: line.startIndex, to: $0.lowerBound),
                 line.distance(from: line.startIndex, to: $0.upperBound))
            }
        }
        let first = try #require(lines.firstIndex { $0.contains("short") }, "drawn: \(lines)")
        let short = try #require(range(of: "short", in: lines[first]))
        let long = try #require(
            lines.dropFirst(first + 1).first.flatMap { range(of: "a much longer line", in: $0) }, "drawn: \(lines)")
        #expect(long.end == 40, "the block still sits at the trailing edge: \(lines)")
        if alignment == .leading {
            #expect(short.start == long.start, "the lines lead, as stated: \(lines)")
        } else {
            // Thirteen cells to share: six before "short", seven after it.
            let (before, after) = (short.start - long.start, long.end - short.end)
            #expect(before > 0 && abs(before - after) <= 1, "the lines are centred, as stated: \(lines)")
        }
    }

    @Test("A flexible control gets the whole remainder, not half of it")
    func flexibleContentTakesTheRest() {
        // The bug: the body put a `Spacer` between the label and the content,
        // and a spacer is width-flexible exactly like a `TextField` — so the
        // stack split the leftover evenly and a labelled field spent half the
        // line on the gap in front of it.
        let out = line(
            LabeledContent("Note") { TextField("", text: .constant("")) }, width: 40)
        let fieldStart = out.firstIndex(of: TerminalSymbols.openCap).map { out.distance(from: out.startIndex, to: $0) }
        #expect(fieldStart != nil, "a field was drawn: \(out.debugDescription)")
        // "Note" (4) + one space of stack spacing: the field starts right after
        // the label, not halfway across the line.
        #expect(fieldStart == 5, "the field starts at \(fieldStart ?? -1): \(out.debugDescription)")
    }
}
