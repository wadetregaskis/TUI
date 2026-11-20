//  🖥️ TUI — A Terminal UI framework for Swift
//  TextParagraphLineHeightTests.swift
//
//  An attributed string's paragraph `lineHeight` (G3 L4, the owner's rulings
//  A-ATTRED-3 of 2026-11-17 and A-ATTRED-13 (b) of 2026-11-19): the rule from
//  a line height to whole rows (`ParagraphLineRows`), which every platform
//  runs; Core Text's or TUI's `LineHeight` read by it; and a `Text` putting a
//  paragraph's blank rows after its lines, measured as drawn.
//
//  A Mac before macOS 26 has no line height (as SwiftUI's has none), so the
//  drawing is tested through `Text`'s runs, which hold the rows a line, and
//  through the attribute itself where it exists: macOS 26, Linux, Windows.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Paragraph line height in an AttributedString")
struct TextParagraphLineHeightTests {
    /// The stripped lines of `view` drawn `width` cells wide, trailing spaces
    /// dropped.
    private func render(_ view: some View, width: Int, height: Int = 20) -> [String] {
        renderToBuffer(AnyView(view), context: makeBareRenderContext(width: width, height: height))
            .lines.map { $0.stripped.replacingOccurrences(of: " +$", with: "", options: .regularExpression) }
    }

    private func size(_ view: some View, width: Int, height: Int = 20) -> ViewSize {
        measureChild(
            view, proposal: ProposedViewSize(width: width, height: height),
            context: makeBareRenderContext(width: width, height: height))
    }

    /// A text of `paragraphs`, each with the rows a line it states (`nil` for
    /// none), as `Text(AttributedString)` keeps them.
    private func text(_ paragraphs: [(String, Int?)]) -> Text {
        var text = Text(verbatim: paragraphs.map(\.0).joined(separator: "\n"))
        text.runs = paragraphs.enumerated().map { index, paragraph in
            Text.Run(
                text: paragraph.0 + (index < paragraphs.count - 1 ? "\n" : ""), style: TextStyle(),
                lineRows: paragraph.1)
        }
        return text
    }

    // MARK: - The rule, on every platform

    @Test("A factor takes its rounded rows, half away from zero, from one to eight")
    func rowsForFactor() {
        let expected: [(Double, Int)] = [
            (1, 1), (1.2, 1), (1.49, 1), (1.5, 2), (2, 2), (2.25, 2), (2.49, 2), (2.5, 3), (3, 3), (7.6, 8),
            (8.49, 8), (8.5, 8), (1e300, 8), (.infinity, 8), (0, 1), (0.5, 1), (-3, 1), (.nan, 1), (-.infinity, 1),
        ]
        for (factor, rows) in expected {
            #expect(ParagraphLineRows.rows(forFactor: factor) == rows, "factor \(factor)")
        }
    }

    @Test("Core Text's factors are read wherever the rows a line could be more than one")
    func readableFactorsCoverTheRows() {
        let grid = ParagraphLineRows.readableTwentieths
        // Below the grid every factor takes one row, so nothing is lost there.
        #expect(ParagraphLineRows.rows(forFactor: Double(grid.lowerBound - 1) / 20) == 1)
        #expect(ParagraphLineRows.rows(forFactor: Double(grid.lowerBound) / 20) == 2)
        // Its top is the last factor below the cap's rounding.
        #expect(ParagraphLineRows.rows(forFactor: Double(grid.upperBound) / 20) == ParagraphLineRows.maximum)
        #expect(Double(grid.upperBound + 1) / 20 == Double(ParagraphLineRows.maximum) + 0.5)
    }

    /// Each value's rows, on the platform's own `LineHeight`: Core Text's,
    /// read by comparison, on a Mac (macOS 26, which CI's macOS 26 lane runs),
    /// and TUI's, read directly, on Linux, Windows and WebAssembly.
    nonisolated private static let drawnRowsByValue: [(String, Int)] = [
        ("multiple 2", 2), ("multiple 1.5", 2), ("multiple 1.75", 2), ("multiple 1.2", 1), ("multiple 3", 3),
        ("multiple 2.5", 3), ("multiple 8", 8), ("normal", 1), ("tight", 1), ("loose", 1), ("variable", 1),
        ("leading 20", 1), ("exact 40", 1),
    ]

    @Test("A line height is drawn as its rule's rows", arguments: Self.drawnRowsByValue)
    func drawnRows(_ named: String, _ rows: Int) throws {
        guard LineHeightProbe.isAvailable else { return }
        #expect(try LineHeightProbe.drawnRows(named) == rows, "\(named)")
    }

    @Test("A factor off Core Text's grid draws one row on a Mac, and its rows elsewhere")
    func offTheGrid() throws {
        guard LineHeightProbe.isAvailable else { return }
        // Held per side, never both accepted: Core Text's factor is read only on
        // its grid; TUI's own type reads every factor.
        #if canImport(CoreText)
            #expect(try LineHeightProbe.drawnRows("multiple 2.33") == 1)
            #expect(try LineHeightProbe.drawnRows("multiple 100") == 1)
        #else
            #expect(try LineHeightProbe.drawnRows("multiple 2.33") == 2)
            #expect(try LineHeightProbe.drawnRows("multiple 100") == 8)
        #endif
    }

    @Test("SwiftUI's lineHeight exists where Core Text has it, which on a Mac is macOS 26")
    func lineHeightRunsWhereCoreTextHasIt() {
        #if canImport(CoreText)
            if #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
                #expect(LineHeightProbe.isAvailable)
            } else {
                #expect(!LineHeightProbe.isAvailable)
            }
        #else
            #expect(LineHeightProbe.isAvailable)
        #endif
    }

    // MARK: - A Text's rows

    @Test("A paragraph of two rows a line has a blank row after each of its lines")
    func blankRowAfterEachLine() {
        // "one two" wraps at 4 into "one", "two"; "end" states none.
        let drawn = render(text([("one two", 2), ("end", nil)]), width: 4)
        #expect(drawn == ["one", "", "two", "", "end"])
        #expect(size(text([("one two", 2), ("end", nil)]), width: 4).height == 5)
    }

    @Test("Nothing follows the text's last line")
    func noTrailingRows() {
        #expect(render(text([("a", nil), ("b", 3)]), width: 4) == ["a", "b"])
        #expect(size(text([("a", nil), ("b", 3)]), width: 4).height == 2)
        #expect(size(text([("solo", 3)]), width: 8).height == 1)
    }

    @Test("Three rows a line is two blank rows, beside the text's line spacing")
    func withLineSpacing() {
        let view = text([("a", 3), ("b", nil), ("c", nil)]).lineSpacing(1)
        #expect(render(view, width: 4) == ["a", "", "", "", "b", "", "c"])
        #expect(size(view, width: 4).height == 7)
    }

    @Test("The rows offered are shared out by the lines' own heights, as the measure counts them")
    func offeredRows() {
        // "one", blank, "two", blank, "end": four rows hold two lines.
        let view = text([("one two", 2), ("end", nil)])
        let drawn = render(view, width: 4, height: 4)
        #expect(drawn.count <= 4, "\(drawn)")
        #expect(drawn.first == "one" && drawn.dropFirst().first?.isEmpty == true)
        for height in 1...6 {
            let measured = size(view, width: 4, height: height)
            #expect(
                measured.height == render(view, width: 4, height: measured.height).count,
                "measured \(measured.height) at a height of \(height)")
            #expect(measured.height <= max(1, height))
        }
    }

    @Test("A line limit counts lines of text, not rows")
    func lineLimitCountsLines() {
        let view = text([("one", 2), ("two", 2), ("three", nil)]).lineLimit(2)
        let drawn = render(view, width: 8)
        #expect(drawn.count == 3, "two lines and the blank row between: \(drawn)")
        #expect(drawn[1].isEmpty)
    }

    @Test("Through the attribute, set on a word: its whole paragraph takes the rows")
    func throughTheAttribute() throws {
        guard LineHeightProbe.isAvailable else { return }
        var string = AttributedString("one two\nend")
        try LineHeightProbe.set(&string, try #require(string.range(of: "two")), "multiple 2")
        // Bounded by paragraphs, as alignment is (on a Mac, Core Text's key:
        // measured here, by CI's macOS 26 lane).
        let runs = Array(string.runs)
        #expect(String(string[runs[0].range].characters) == "one two\n")
        #expect(
            string[runs[0].range].drawnLineRows == 2 && runs.count == 2 && string[runs[1].range].drawnLineRows == 1)
        #expect(render(Text(string), width: 4) == ["one", "", "two", "", "end"])
    }
}

/// SwiftUI's spelling of a line height, where this machine has it: Core
/// Text's on a Mac from macOS 26, TUI's own on Linux, Windows and WebAssembly.
private enum LineHeightProbe {
    static var isAvailable: Bool {
        #if canImport(CoreText)
            if #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) { return true }
            return false
        #else
            return true
        #endif
    }

    struct Unknown: Error {}

    /// The rows a line takes at the line height `named` ("multiple 2",
    /// "normal", "exact 40"…).
    static func drawnRows(_ named: String) throws -> Int {
        #if canImport(CoreText)
            guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { throw Unknown() }
        #endif
        return try value(named).drawnRows
    }

    /// Sets the line height of the paragraph `range` is in to the one `named`.
    static func set(_ string: inout AttributedString, _ range: Range<AttributedString.Index>, _ named: String) throws {
        #if canImport(CoreText)
            guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { throw Unknown() }
        #endif
        string[range].lineHeight = try value(named)
    }

    #if canImport(CoreText)
        @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    #endif
    private static func value(_ named: String) throws -> AttributedString.LineHeight {
        let parts = named.split(separator: " ")
        let amount = parts.count > 1 ? CGFloat(Double(parts[1]) ?? 0) : 0
        switch parts[0] {
        case "multiple": return .multiple(factor: amount)
        case "leading": return .leading(increase: amount)
        case "exact": return .exact(points: amount)
        case "normal": return .normal
        case "tight": return .tight
        case "loose": return .loose
        case "variable": return .variable
        default: throw Unknown()
        }
    }
}
