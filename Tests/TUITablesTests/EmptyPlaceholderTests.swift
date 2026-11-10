//  🖥️ TUI — A Terminal UI framework for Swift
//  EmptyPlaceholderTests.swift
//
//  An empty List's or Table's placeholder stands where a row's text would, in
//  the secondary ink: flush against the border in the rows' ink it read as an
//  accident (owner #18, 2026-10-23).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUILists
import TUITables
@testable import TUITestSupport
@testable import TUIView

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

    /// A placeholder that says why: more than a row of 30 columns holds.
    private let why = "The folder can't be opened because you don't have permission to see its contents."

    /// The rows of `lines` that draw part of ``why``, as plain text, trimmed.
    private func whyRows(_ lines: [String]) -> [String] {
        lines.map { String(paintedCells($0).map(\.glyph)) }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " │")) }
            .filter { !$0.isEmpty && !$0.contains("─") && !$0.hasPrefix("Name") }
    }

    @Test("A list's placeholder too long for its width wraps onto the rows below, all of it in the secondary ink")
    func listPlaceholderWraps() throws {
        let drawn = lines(List { EmptyView() }.listEmptyPlaceholder(why))
        let rows = whyRows(drawn)
        #expect(rows.count > 1, "\(drawn)")
        #expect(rows.joined(separator: " ") == why, "\(rows)")
        let last = try #require(firstCell(of: "contents.", in: drawn))
        #expect(last.ink == secondaryInk)
        #expect(last.column == firstCell(of: "The", in: drawn)?.column)
    }

    @Test("A table's placeholder too long for its width wraps onto the rows below")
    func tablePlaceholderWraps() throws {
        let table = Table([Row](), selection: .constant(String?.none)) {
            TableColumn("Name", value: \Row.name)
        }
        .tableEmptyPlaceholder(why)
        let drawn = lines(table)
        let rows = whyRows(drawn)
        #expect(rows.count > 1, "\(drawn)")
        #expect(rows.joined(separator: " ") == why, "\(rows)")
        #expect(try #require(firstCell(of: "contents.", in: drawn)).ink == secondaryInk)
    }

    @Test("A placeholder too long for the list's rows keeps those it has, the last ending in an ellipsis")
    func placeholderFoldsIntoTheRowsThereAre() {
        let drawn = renderToBuffer(
            List { EmptyView() }.listEmptyPlaceholder(why), context: makeRenderContext(width: 30, height: 4)
        ).lines
        let rows = whyRows(drawn)
        #expect(rows.count == 2, "\(drawn)")
        #expect(rows.last?.hasSuffix("…") == true, "\(rows)")
    }
}
