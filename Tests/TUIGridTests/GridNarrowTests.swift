//  🖥️ TUI — A Terminal UI framework for Swift
//  GridNarrowTests.swift
//
//  A grid offered less width than its columns ask for shares it among them, as
//  an HStack shares a row among its children: SwiftUI's, measured
//  (`Tools/SwiftUIProbes/Grid narrower than its columns/grid.out`). Columns
//  were never squeezed, so the grid was drawn at its full width and clipped:
//  at 5 cells only the first column showed.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
import TUIGrid
@testable import TUITestSupport

/// The probe's grids, in TUI's cells.
@MainActor
@Suite("A grid narrower than its columns")
struct GridNarrowTests {

    private func lines(_ view: some View, width: Int, height: Int = 30) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .lines.map { $0.stripped.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
    }

    /// Three columns of text: short words, a sentence that wraps, short words.
    private var threeText: some View {
        Grid(alignment: .topLeading) {
            GridRow { Text("Name"); Text("Description"); Text("Size") }
            GridRow { Text("README"); Text("A longer line of text"); Text("2048 KB") }
        }
    }

    /// Four columns: the third rigid, the fourth filling, its text at its
    /// trailing edge so the column's width shows.
    private var fourColumns: some View {
        Grid(alignment: .topLeading) {
            GridRow {
                Text("Name"); Text("Description"); Text("Size").fixedSize()
                Text("Flex").frame(maxWidth: .infinity, alignment: .trailing)
            }
            GridRow {
                Text("README"); Text("A longer line of text"); Text("2048 KB").fixedSize()
                Text("Wide").frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    @Test("At its ideal width the grid is unchanged")
    func idealWidth() {
        #expect(lines(threeText, width: 36) == ["Name   Description           Size", "README A longer line of text 2048 KB"])
    }

    /// 20 cells less 2 gaps: the first column, least flexible, is offered 6
    /// and keeps its 6; the third is offered 6 and wraps to 4; the sentence
    /// takes the 8 left. SwiftUI: 6, 7, 5 (its wrapped text counts a trailing
    /// space), and every column shown.
    @Test("Squeezed, every column stays, its text wrapping, as an HStack shares a row")
    func squeezedColumnsWrap() {
        #expect(
            lines(threeText, width: 20) == [
                "Name   Descript Size",
                "       ion",
                "README A longer 2048",
                "       line of  KB",
                "       text",
            ])
    }

    @Test("At 5 cells each column gets one, rather than only the first showing")
    func fiveCells() {
        let drawn = lines(threeText, width: 5)
        #expect(drawn.first == "N D S", "\(drawn)")
    }

    @Test("Under lineLimit(1) a squeezed column truncates and the grid stays two lines")
    func squeezedColumnsTruncate() {
        let drawn = lines(threeText.lineLimit(1), width: 20)
        #expect(drawn.count == 2, "\(drawn)")
        #expect(drawn[0].hasPrefix("Name"), "\(drawn)")
        #expect(drawn[0].hasSuffix("Size"), "\(drawn)")
        #expect(drawn[1].contains("…"), "\(drawn)")
    }

    /// The rigid column is dealt first and keeps its 7; the filling column is
    /// dealt last and takes what the others leave. SwiftUI at 40: 6, 11, 7, 13.
    @Test("A rigid column keeps its width, and a filling one takes what is left")
    func rigidAndFilling() {
        #expect(
            lines(fourColumns, width: 40) == [
                "Name   Description  Size            Flex",
                "README A longer     2048 KB         Wide",
                "       line of text",
            ])
        // At 10 the rigid column is all there is room for.
        #expect(lines(fourColumns, width: 10).first?.contains("Size") == true, "\(lines(fourColumns, width: 10))")
    }

    @Test("Wider than its columns, a filling column takes the rest, as SwiftUI's does (23 at 60)")
    func fillingColumnGrows() {
        let drawn = lines(fourColumns, width: 60)
        #expect(drawn[0].count == 60, "\(drawn)")
        #expect(drawn[0].hasSuffix("Flex"), "\(drawn)")
    }

    @Test("The size a squeezed grid reports is the size it draws")
    func measureMatchesRender() {
        for width in [5, 10, 15, 20, 26, 34] {
            let measured = measureChild(
                threeText, proposal: ProposedViewSize(width: width, height: nil),
                context: makeRenderContext(width: 60, height: 30))
            let drawn = renderToBuffer(threeText, context: makeRenderContext(width: width, height: 30))
            #expect(measured.width == drawn.width, "at \(width)")
            #expect(measured.height == drawn.lines.count, "at \(width)")
        }
    }

    @Test("GridLayout shares a short width as Grid does")
    func gridLayoutAgrees() {
        let layout = GridLayout(alignment: .topLeading) {
            GridRow { Text("Name"); Text("Description"); Text("Size") }
            GridRow { Text("README"); Text("A longer line of text"); Text("2048 KB") }
        }
        #expect(lines(layout, width: 20) == lines(threeText, width: 20))
    }
}
