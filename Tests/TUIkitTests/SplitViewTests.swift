//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SplitViewTests.swift
//
//  `HSplitView` and `VSplitView`: panes with a divider between each pair, sized
//  to their content where they hug it and sharing the rest where they fill, and
//  resized by the divider — with the arrow keys or a drag.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Split views")
struct SplitViewTests {
    /// The column the first `│` is drawn in on the first row.
    private func dividerColumn(_ buffer: FrameBuffer) -> Int? {
        let line = buffer.lines.first?.stripped ?? ""
        return line.firstIndex(of: "│").map { line.distance(from: line.startIndex, to: $0) }
    }

    private func split() -> some View {
        HSplitView {
            Text("ab")
            Text("filler").frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @Test("A pane that hugs its content starts at its width; one that fills takes the rest")
    func initialSizes() {
        let harness = InputChainHarness(width: 20, height: 3)
        let drawn = harness.frame(split())
        #expect(dividerColumn(drawn) == 2, "\(drawn.lines.map(\.stripped))")
        #expect(drawn.width == 20)
    }

    @Test("Right moves the focused divider a cell, Shift-Right five, Left back")
    func keyboard() {
        let harness = InputChainHarness(width: 20, height: 3)
        harness.play([KeyEvent(key: .right)]) { split() }
        #expect(dividerColumn(harness.frame(split())) == 3)
        harness.play([KeyEvent(key: .right, shift: true)]) { split() }
        #expect(dividerColumn(harness.frame(split())) == 8)
        harness.play([KeyEvent(key: .left)]) { split() }
        #expect(dividerColumn(harness.frame(split())) == 7)
    }

    @Test("Dragging the divider moves it by the distance dragged, keeping each pane a cell")
    func drag() {
        let harness = InputChainHarness(width: 20, height: 3)
        harness.frame(split())
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 2, y: 1))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 6, y: 1))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 6, y: 1))
        #expect(dividerColumn(harness.frame(split())) == 6)

        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 6, y: 1))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 40, y: 1))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 40, y: 1))
        #expect(dividerColumn(harness.frame(split())) == 18, "the right pane keeps one cell")
    }

    @Test("A vertical split stacks its panes with a rule between, Up and Down moving it")
    func vertical() {
        let harness = InputChainHarness(width: 6, height: 5)
        let view = { VSplitView { Text("a"); Text("b") } }
        let drawn = harness.frame(view()).lines.map(\.stripped)
        // Neither pane fills, so they split the four rows evenly.
        #expect(drawn.firstIndex { $0.hasPrefix("─") } == 2, "\(drawn)")
        harness.play([KeyEvent(key: .up)]) { view() }
        #expect(harness.frame(view()).lines.map(\.stripped).firstIndex { $0.hasPrefix("─") } == 1)
    }
}
