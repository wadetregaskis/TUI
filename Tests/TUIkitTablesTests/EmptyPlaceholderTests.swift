//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EmptyPlaceholderTests.swift
//
//  An empty List's or Table's placeholder stands where a row's text would, in
//  the secondary ink: flush against the border in the rows' ink it read as an
//  accident (owner #18, 2026-10-23).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitLists
import TUIkitTables
@testable import TUIkitTestSupport
@testable import TUIkitView

@MainActor
@Suite("An empty list's or table's placeholder", .rendersEnglishUI)
struct EmptyPlaceholderTests {
    private struct Row: Identifiable {
        let id: String
        let name: String
    }

    private func lines<V: View>(_ view: V) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: 30, height: 8)).lines
    }

    /// The ink of the first cell drawing `text` in `lines`, and its column.
    private func firstCell(of text: String, in lines: [String]) -> (column: Int, ink: SGRState.Colour?)? {
        for line in lines {
            let cells = paintedCells(line)
            let glyphs = String(cells.map(\.glyph))
            guard let range = glyphs.range(of: text) else { continue }
            let column = glyphs.distance(from: glyphs.startIndex, to: range.lowerBound)
            return (column, cells[column].ink)
        }
        return nil
    }

    /// The ink the secondary foreground draws in, from a `Text` that asks for it.
    private var secondaryInk: SGRState.Colour? {
        firstCell(of: "x", in: lines(Text("x").foregroundStyle(.palette.foregroundSecondary)))?.ink
    }

    @Test("A list's placeholder starts where its rows' text does, in the secondary ink")
    func listPlaceholder() throws {
        let empty = try #require(firstCell(of: "No items", in: lines(List { EmptyView() })))
        let row = try #require(firstCell(of: "alpha", in: lines(List { Text("alpha") })))
        #expect(empty.column == row.column)
        #expect(empty.ink == secondaryInk)
        #expect(empty.ink != row.ink)
    }

    @Test("A table's placeholder starts where its rows' first cell does, in the secondary ink")
    func tablePlaceholder() throws {
        func table(_ rows: [Row]) -> some View {
            Table(rows, selection: .constant(String?.none)) {
                TableColumn("Name", value: \Row.name)
            }
        }
        let empty = try #require(firstCell(of: "No items", in: lines(table([]))))
        let row = try #require(firstCell(of: "alpha", in: lines(table([Row(id: "a", name: "alpha")]))))
        #expect(empty.column == row.column)
        #expect(empty.ink == secondaryInk)
    }
}
