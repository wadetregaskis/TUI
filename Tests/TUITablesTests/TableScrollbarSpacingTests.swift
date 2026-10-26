//  🖥️ TUI — A Terminal UI framework for Swift
//  TableScrollbarSpacingTests.swift
//
//  `.scrollbarSpacing(_:)`: the cells a table keeps between its rows' content
//  and its vertical scrollbar — one unless stated — with the bar still the
//  table's last interior column, on the single-line and the multi-line path.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
import TUITables
@testable import TUITestSupport

@MainActor
@Suite("A table's spacing before its scrollbar")
struct TableScrollbarSpacingTests {

    private struct Row: Identifiable {
        let id: Int
        let name: String
        let note: String
    }

    private static let rows = (0..<8).map {
        Row(id: $0, name: "row\($0)", note: "a note long enough to wrap over two lines for sure")
    }

    /// The table's lines with a bar, plain text, at `spacing` (`nil`: unstated).
    private func lines(spacing: Int?, multiLine: Bool) -> [String] {
        let table = Table(Self.rows) {
            TableColumn("Name", value: \Row.name)
            TableColumn("Note", value: \Row.note).lineLimit(multiLine ? 2 : 1)
        }
        .scrollIndicators(.visible)
        let view = spacing.map { AnyView(table.scrollbarSpacing($0)) } ?? AnyView(table)
        return renderToBuffer(view, context: makeRenderContext(width: 40, height: 8)).lines.map(\.stripped)
    }

    /// The cells between the last of the content and the bar on the line with
    /// the bar's `arrow`, and the cells between the bar and the border.
    private func gaps(_ lines: [String], arrow: Character) throws -> (beforeBar: Int, afterBar: Int) {
        let line = Array(try #require(lines.first { $0.contains(arrow) }))
        let bar = try #require(line.firstIndex(of: arrow))
        let lastInk = try #require(line[..<bar].lastIndex { $0 != " " })
        return (bar - lastInk - 1, line.count - 1 - bar - 1)
    }

    @Test("One cell by default, none at 0, two at 2 — the bar stays the last interior column",
        arguments: [false, true])
    func spacing(multiLine: Bool) throws {
        for (spacing, expected) in [(nil, 1), (0, 0), (2, 2)] as [(Int?, Int)] {
            let drawn = lines(spacing: spacing, multiLine: multiLine)
            for arrow: Character in ["▲", "▼"] {
                let gaps = try gaps(drawn, arrow: arrow)
                #expect(gaps.afterBar == 1, "\(arrow) one padding cell from the border: \(drawn)")
                if multiLine { continue }  // a wrapped row's last line ends short
                #expect(gaps.beforeBar == expected, "spacing \(String(describing: spacing)): \(drawn)")
            }
        }
    }

    @Test("A table with no bar takes no spacing")
    func noBarNoSpacing() {
        // Three rows in a table that fits them: nothing to scroll, no bar.
        let table = Table(Array(Self.rows.prefix(3))) {
            TableColumn("Name", value: \Row.name)
            TableColumn("Note", value: \Row.note)
        }
        // Fresh contexts: two renders in one would share the table's state.
        #expect(
            renderToBuffer(table.scrollbarSpacing(3), context: makeRenderContext(width: 40, height: 8)).lines.map(\.stripped)
                == renderToBuffer(table, context: makeRenderContext(width: 40, height: 8)).lines.map(\.stripped))
    }
}
