//  🖥️ TUI — A Terminal UI framework for Swift
//  SheetSizeContainerTests.swift
//
//  Which containers hand a sized sheet's size on to the boxes in them: a
//  `Grid` and the lazy stacks clear it, as a scroll view does, so their boxes
//  are their content's size, as a lazy grid's already were (decisions
//  B-D2C-5).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUIPresentation
@testable import TUITestSupport

@MainActor
@Suite("A sheet's size in grids and lazy stacks")
struct SheetSizeContainerTests {
    private func context() -> RenderContext {
        makeRenderContext(width: 120, height: 40) { environment, _ in
            environment.mouseEventDispatcher = MouseEventDispatcher()
            environment.terminalWidth = 120
            environment.overlayContentHeight = 40
        }
    }

    /// The sheet's lines, stripped, for `content` presented in a `.form`
    /// sheet — 64 columns by 25 rows.
    private func formSheet(_ content: some View) -> [String] {
        let buffer = renderToBuffer(
            Text("page").sheet(isPresented: .constant(true)) { content.presentationSizing(.form) },
            context: context())
        return buffer.overlays.first?.content.lines.map(\.stripped) ?? []
    }

    /// Where "Beta"'s title is: row 3, under a three-row "Alpha", when each box
    /// is its content's size. Passed the sheet's size, the first box took all
    /// 25 rows, and the second was not drawn.
    private func betaRow(_ lines: [String]) -> Int? {
        lines.firstIndex { $0.contains("Beta") }
    }

    @Test("Boxes in a lazy stack in a sized sheet are their content's height")
    func lazyStack() {
        let lines = formSheet(
            LazyVStack(spacing: 0) {
                Panel("Alpha") { Text("a") }
                Panel("Beta") { Text("b") }
            })
        #expect(betaRow(lines) == 3, "\(lines)")
    }

    @Test("Boxes in a grid in a sized sheet are their content's size")
    func grid() {
        let lines = formSheet(
            Grid(verticalSpacing: 0) {
                GridRow { Panel("Alpha") { Text("a") } }
                GridRow { Panel("Beta") { Text("b") } }
            })
        #expect(betaRow(lines) == 3, "\(lines)")
    }

    /// A lazy grid needed nothing: its boxes were their content's size before
    /// the change too (this test, run on the base). Kept as the guard that
    /// they stay so.
    @Test("Boxes in a lazy grid in a sized sheet are their content's size")
    func lazyGrid() {
        let lines = formSheet(
            LazyVGrid(columns: [GridItem(.flexible())], spacing: 0) {
                Panel("Alpha") { Text("a") }
                Panel("Beta") { Text("b") }
            })
        #expect(betaRow(lines) == 3, "\(lines)")
    }

    @Test("A box in a lazy column still spans the sheet's width")
    func lazyStackKeepsTheWidth() {
        let lines = formSheet(LazyVStack(spacing: 0) { Panel("Alpha") { Text("a") } })
        let top = lines.first.map { $0.trimmingCharacters(in: .whitespaces).count }
        #expect(top == 64, "\(lines)")
    }
}
