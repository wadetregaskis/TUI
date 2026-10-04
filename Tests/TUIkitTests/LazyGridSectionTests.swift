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

@testable import TUIkit

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

    @Test("A grid's spacing falls between rows and between sections, as a stack's does")
    func spacingBetweenRowsAndSections() {
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
            Array(lines.prefix(8)) == [
                "Head 0", "0.0        0.1", "", "0.2", "", "Head 1", "1.0        1.1", "",
            ])
    }
}
