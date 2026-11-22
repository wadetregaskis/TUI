//  🖥️ TUI — A Terminal UI framework for Swift
//  GridNegativeSpacingTests.swift
//
//  A negative spacing in a grid: rows pulled up over the rows before them, the
//  later row on top, as a column's children are; columns held apart (hunt
//  H-20, SCROLL-16).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUIGrid
@testable import TUITestSupport
@testable import TUIView

@MainActor
@Suite("Negative spacing in a grid")
struct GridNegativeSpacingTests {
    private func context() -> RenderContext {
        makeBareRenderContext(width: 20, height: 10).isolatingRenderCache()
    }

    @Test("Rows pulled up are drawn over the rows above, measured as drawn, and clicked where drawn")
    func pulledRows() {
        let grid = Grid(alignment: .leading, verticalSpacing: -1) {
            GridRow { Text("a\na") }
            GridRow { Button("b") {} }
            GridRow { Button("c") {} }
        }
        let measured = measureChild(grid, proposal: .unspecified, context: context())
        let buffer = renderToBuffer(grid, context: context())
        let rows = buffer.lines.map(\.stripped)
        #expect(measured.height == 2)
        #expect(rows.count == 2, "\(rows)")
        #expect(rows.first?.hasPrefix("a") == true, "\(rows)")
        #expect(rows.last?.contains("c") == true, "the last row on top: \(rows)")
        #expect(buffer.hitTestRegions.map(\.offsetY).sorted() == [1, 1], "each region on the row its button is drawn on")
    }

    @Test("A negative column spacing is held at zero: the columns never go below nothing")
    func columnsHeldApart() {
        let grid = Grid(horizontalSpacing: -5) {
            GridRow {
                Text("ab")
                Text("cd")
            }
        }
        let measured = measureChild(grid, proposal: .unspecified, context: context())
        let buffer = renderToBuffer(grid, context: context())
        #expect(measured.width == 4)
        #expect(buffer.lines.map(\.stripped) == ["abcd"])
    }

    @Test("A lazy grid's lines pulled past the content never make it shorter than nothing")
    func lazyGridAlong() {
        let grid = LazyVGrid(columns: [GridItem(.fixed(2))], spacing: -3) {
            Text("a")
            Text("b")
        }
        let measured = measureChild(grid, proposal: .unspecified, context: context())
        #expect(measured.height == 1)
    }
}
