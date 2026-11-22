//  🖥️ TUI — A Terminal UI framework for Swift
//  NegativeColumnSpacingTests.swift
//
//  A negative `spacing` in a column pulls each child up over the one before
//  it, the later child drawn on top, as SwiftUI's `VStack` draws it — and the
//  rows it draws, the rows it reports and the rows its controls answer clicks
//  on are the same rows (hunt H-20: LAYOUT-3, LAYOUT-7, LAYOUT-11, CORE1-3).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

@MainActor
@Suite("Negative spacing in a column")
struct NegativeColumnSpacingTests {
    private func context(width: Int = 10, height: Int = 10) -> RenderContext {
        makeBareRenderContext(width: width, height: height).isolatingRenderCache()
    }

    @Test("A later child pulled up is drawn over the earlier, and clicked where it is drawn")
    func pulledChildDrawsAndClicksWhereItIs() throws {
        let buffer = renderToBuffer(
            VStack(alignment: .leading, spacing: -1) {
                Text("a\nb\nc")
                Button("x") {}
            },
            context: context())
        let rows = buffer.lines.map(\.stripped)
        #expect(rows.count == 3, "three rows, the button over the last of the text: \(rows)")
        #expect(rows.last?.contains("x") == true, "the button is on the text's last row: \(rows)")
        #expect(rows.last?.contains("c") == false, "drawn over \"c\": \(rows)")
        let region = try #require(buffer.hitTestRegions.last, "the button registers a region")
        #expect(region.offsetY == 2, "the region is on the row the button is drawn on")
    }

    @Test("A column measures the rows it draws, which a parent then gives it")
    func measureAgreesWithDrawing() {
        let column = VStack(spacing: -1) {
            Text("a\nb\nc")
            Text("d\ne")
        }
        let measured = measureChild(column, proposal: .unspecified, context: context())
        let drawn = renderToBuffer(VStack(spacing: 0) { column; Text("z") }, context: context())
        #expect(measured.height == 4)
        #expect(drawn.lines.map(\.stripped) == ["a", "b", "d", "e", "z"], "\(drawn.lines.map(\.stripped))")
    }

    /// Two boxes sharing a border row: given exactly the rows it measured, the
    /// column must deal each box its whole height. With the gap charged as
    /// nothing, the deal handed out a row the overlap then took back, and the
    /// second box lost its bottom row.
    @Test("A column given its measured height deals each child its whole height")
    func distributionChargesTheOverlap() {
        let column = VStack(spacing: -1) {
            Text("1\n2\n3")
            Text("4\n5\n6")
        }
        let measured = measureChild(column, proposal: .unspecified, context: context())
        #expect(measured.height == 5)
        let drawn = renderToBuffer(column.frame(height: measured.height), context: context())
        #expect(drawn.lines.map(\.stripped) == ["1", "2", "4", "5", "6"], "\(drawn.lines.map(\.stripped))")
    }

    @Test("A spacing past the content never makes a stack's size negative")
    func spacingPastTheContent() {
        let column = VStack(spacing: -3) {
            Text("a")
            Text("b")
        }
        let row = HStack(spacing: -5) {
            Text("ab")
            Text("cd")
        }
        let columnSize = measureChild(column, proposal: .unspecified, context: context())
        let rowSize = measureChild(row, proposal: .unspecified, context: context())
        #expect(columnSize.height == 1, "\"b\" over \"a\": one row")
        #expect(rowSize.width == 2, "\"cd\" over \"ab\": two columns")
        let outer = renderToBuffer(VStack(spacing: 0) { column; Text("z") }, context: context())
        #expect(outer.lines.map(\.stripped) == ["b", "z"], "\(outer.lines.map(\.stripped))")
        #expect(renderToBuffer(row, context: context()).lines.map(\.stripped) == ["cd"])
    }

    @Test("A later child shorter than its pull cuts the rows below it, as the measure charges")
    func shortLaterChildCutsTheRowsBelow() {
        let column = VStack(alignment: .leading, spacing: -2) {
            Text("a\nb\nc")
            Text("x")
        }
        let measured = measureChild(column, proposal: .unspecified, context: context())
        let drawn = renderToBuffer(column, context: context())
        #expect(measured.height == 2)
        #expect(drawn.lines.map(\.stripped) == ["a", "x"], "\(drawn.lines.map(\.stripped))")
    }
}
