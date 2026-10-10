//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LazyGridSectionTests.swift
//
//  A `Section` in a `LazyVGrid`, as SwiftUI lays one out (measured on macOS
//  15.8): its header starts a new row and spans every column, its views flow
//  across the columns from the row below, and its footer spans the columns
//  after them. Drawn as one view, a section used to take a single cell.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore
@testable import TUIkitLists

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("A lazy vertical grid lays out its sections")
struct LazyGridSectionTests {
    private func painted(_ view: some View, width: Int = 20, height: Int = 20) -> [String] {
        renderToBuffer(view, context: makeBareRenderContext(width: width, height: height))
            .lines
            .map { $0.stripped.replacingOccurrences(of: " +$", with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
    }

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    @Test("A header and a footer span the columns, and the section's views start a row of their own")
    func sectionsStartRows() {
        let grid = LazyVGrid(columns: columns, alignment: .leading) {
            Text("a")
            Text("b")
            Text("c")
            Section {
                Text("1")
                Text("2")
                Text("3")
            } header: {
                Text("Head")
            } footer: {
                Text("Foot")
            }
            Text("z")
        }
        #expect(
            painted(grid) == [
                "a          b",
                "c",
                "Head",
                "1          2",
                "3",
                "Foot",
                "z",
            ])
    }

    @Test("A section's header sits across the grid where its alignment puts a view in a cell")
    func headerFollowsTheGridsAlignment() {
        // Measured: centred by a `.center` grid, at the leading edge by a
        // `.leading` one.
        func header(_ alignment: HorizontalAlignment) -> String? {
            painted(
                LazyVGrid(columns: columns, alignment: alignment) {
                    Section("Head") { Text("1") }
                }
            ).first
        }
        #expect(header(.leading) == "Head")
        #expect(header(.center) == "        Head")
        #expect(header(.trailing) == "                Head")
    }

    @Test("A grid with no sections lays out as it always did")
    func noSectionsNoChange() {
        let grid = LazyVGrid(columns: columns, alignment: .leading) {
            ForEach(0..<5, id: \.self) { Text("\($0)") }
        }
        #expect(painted(grid) == ["0          1", "2          3", "4"])
    }

    @Test("A grid's spacing falls between every two of a section's rows, its header and footer too, as SwiftUI's does")
    func spacingBetweenRowsAndSections() {
        // Measured on macOS 15.8 (`w10b/probe/p5`, `spacing: 10`): the gap
        // falls between a header and its section's first row as between any
        // two rows. The grid's sections are a loop's rows, each a section a
        // stack takes apart (decisions B15).
        let grid = LazyVGrid(columns: columns, alignment: .leading, spacing: 1) {
            ForEach(0..<2, id: \.self) { section in
                Section("Head \(section)") {
                    ForEach(0..<3, id: \.self) { Text("\(section).\($0)") }
                }
            }
        }
        let lines = renderToBuffer(grid, context: makeBareRenderContext(width: 20, height: 20))
            .lines.map { $0.stripped.replacingOccurrences(of: " +$", with: "", options: .regularExpression) }
        #expect(
            Array(lines.prefix(9)) == [
                "Head 0", "", "0.0        0.1", "", "0.2", "", "Head 1", "", "1.0        1.1",
            ])
    }

    /// A cell that is not `Equatable`, so its loop builds it each time a walk
    /// resolves the grid's children rather than serving it from the row memo.
    private struct Cell {
        let name: String
    }

    @MainActor
    private final class Builds {
        var count = 0
    }

    @Test("A grid of a loop of cells resolves its children once a render, not again to look for sections")
    func noSectionWalkForCells() {
        let builds = Builds()
        let cells = (0..<5).map { Cell(name: "c\($0)") }
        func cell(_ cell: Cell) -> Text {
            builds.count += 1
            return Text(cell.name)
        }
        _ = renderToBuffer(
            LazyHGrid(rows: [GridItem(.fixed(1)), GridItem(.fixed(1))]) { ForEach(cells, id: \.name) { cell($0) } },
            context: makeBareRenderContext(width: 30, height: 4))
        #expect(builds.count == cells.count, "a row grid built \(builds.count) cells for \(cells.count)")
        builds.count = 0
        _ = renderToBuffer(
            LazyVGrid(columns: columns) { ForEach(cells, id: \.name) { cell($0) } },
            context: makeBareRenderContext(width: 30, height: 8))
        #expect(builds.count == cells.count, "a column grid built \(builds.count) cells for \(cells.count)")
    }

    @Test("Whether a section can be among a view's children is read from its type, or looked for when it cannot be")
    func sectionMembershipFromTheType() {
        #expect(!mayHandOver(.section, ForEach<Range<Int>, Int, Text>.self))
        #expect(!mayHandOver(.section, TupleView<Text, Text>.self))
        #expect(mayHandOver(.section, TupleView<Text, Section<Text, Text, EmptyView>>.self))
        #expect(mayHandOver(.section, ForEach<Range<Int>, Int, Section<Text, Text, EmptyView>>.self))
        #expect(mayHandOver(.section, Optional<Group<Section<EmptyView, Text, EmptyView>>>.self))
        // A view of the app's own is one child, which no grid takes apart.
        #expect(!mayHandOver(.section, Cells.self))
        // A provider whose members its type does not spell is walked.
        #expect(mayHandOver(.section, SubviewsCollection.self))
    }
}

/// A view of the app's own around a loop of cells.
private struct Cells: View {
    var body: some View {
        ForEach(0..<2, id: \.self) { Text("\($0)") }
    }
}
