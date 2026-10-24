//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SplitViewTests.swift
//
//  `HSplitView` and `VSplitView`: panes with a divider between each pair, sized
//  to their content where they hug it and sharing the rest where they fill, and
//  resized by the divider — with the arrow keys or a drag — within the bounds a
//  frame on a pane states.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
import TUIkitNavigation
@testable import TUIkitTestSupport

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

    @Test("Home and End take the focused divider as far as the panes allow, and no further")
    func homeAndEnd() {
        let harness = InputChainHarness(width: 20, height: 3)
        harness.play([KeyEvent(key: .end)]) { split() }
        #expect(dividerColumn(harness.frame(split())) == 18, "the right pane keeps one cell")
        harness.play([KeyEvent(key: .home)]) { split() }
        #expect(dividerColumn(harness.frame(split())) == 1, "the left pane keeps one cell")
        harness.play([KeyEvent(key: .end), KeyEvent(key: .end)]) { split() }
        #expect(dividerColumn(harness.frame(split())) == 18, "End again stays")
    }

    @Test("Home and End stop at the bounds a pane's frame states")
    func homeAndEndAreBounded() {
        let harness = InputChainHarness(width: 20, height: 3)
        harness.play([KeyEvent(key: .end)]) { boundedSplit() }
        #expect(dividerColumn(harness.frame(boundedSplit())) == 10, "the maximum")
        harness.play([KeyEvent(key: .home)]) { boundedSplit() }
        #expect(dividerColumn(harness.frame(boundedSplit())) == 4, "the minimum")
    }

    @Test("A vertical divider takes Home to the top and End to the bottom")
    func homeAndEndVertical() {
        let harness = InputChainHarness(width: 6, height: 5)
        let view = { VSplitView { Text("a"); Text("b") } }
        func rule() -> Int? { harness.frame(view()).lines.map(\.stripped).firstIndex { $0.hasPrefix("─") } }
        harness.play([KeyEvent(key: .end)]) { view() }
        #expect(rule() == 3)
        harness.play([KeyEvent(key: .home)]) { view() }
        #expect(rule() == 1)
    }

    @Test("Keys a divider has no use for are declined, so focus movement gets them")
    func otherKeysDeclined() {
        #expect(DividerKeyMove.of(KeyEvent(key: .up), along: .horizontal) == nil)
        #expect(DividerKeyMove.of(KeyEvent(key: .left), along: .vertical) == nil)
        #expect(DividerKeyMove.of(KeyEvent(key: .pageDown), along: .vertical) == nil)
        #expect(DividerKeyMove.of(KeyEvent(key: .tab), along: .horizontal) == nil)
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

    /// A split whose first pane's frame bounds it: 4 to 10 cells, starting at 6.
    private func boundedSplit() -> some View {
        HSplitView {
            Text("ab").frame(minWidth: 4, idealWidth: 6, maxWidth: .fixed(10), alignment: .leading)
            Text("filler").frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @Test("A pane's frame names where it starts, and the divider stops at its minimum and maximum")
    func frameBoundsAPane() {
        let harness = InputChainHarness(width: 20, height: 3)
        #expect(dividerColumn(harness.frame(boundedSplit())) == 6, "it starts at the ideal width")
        harness.play([KeyEvent(key: .right, shift: true)]) { boundedSplit() }
        #expect(dividerColumn(harness.frame(boundedSplit())) == 10, "five more would pass the maximum")
        harness.play([KeyEvent(key: .left, shift: true), KeyEvent(key: .left, shift: true)]) { boundedSplit() }
        #expect(dividerColumn(harness.frame(boundedSplit())) == 4, "ten fewer would pass the minimum")

        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: 4, y: 1))
        harness.mouse(MouseEvent(button: .left, phase: .dragged, x: 30, y: 1))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: 30, y: 1))
        #expect(dividerColumn(harness.frame(boundedSplit())) == 10, "a drag stops at the maximum too")
    }

    @Test("The pane on the divider's other side bounds it as well")
    func otherPaneBoundsTheDivider() {
        let harness = InputChainHarness(width: 20, height: 3)
        let view = {
            HSplitView {
                Text("ab")
                Text("filler").frame(minWidth: 12, maxWidth: .infinity, alignment: .leading)
            }
        }
        harness.play([KeyEvent(key: .right, shift: true), KeyEvent(key: .right, shift: true)]) { view() }
        // 20 cells: the right pane keeps 12, the divider one, the left 7.
        #expect(dividerColumn(harness.frame(view())) == 7)
    }

    @Test("A frame is found through an environment modifier, and not through padding")
    func boundsLookThrough() {
        let harness = InputChainHarness(width: 20, height: 3)
        let seen = {
            HSplitView {
                Text("ab").frame(minWidth: 4, idealWidth: 6, maxWidth: .fixed(10), alignment: .leading)
                    .foregroundStyle(.red)
                Text("filler").frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        #expect(dividerColumn(harness.frame(seen())) == 6)

        let padded = InputChainHarness(width: 20, height: 3)
        let unseen = {
            HSplitView {
                Text("ab").frame(minWidth: 4, idealWidth: 6, maxWidth: .fixed(10), alignment: .leading).padding(.leading, 1)
                Text("filler").frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        padded.play([KeyEvent(key: .right, shift: true), KeyEvent(key: .right, shift: true)]) { unseen() }
        #expect((dividerColumn(padded.frame(unseen())) ?? 0) > 11, "the padded pane is not bounded by the frame inside it")
    }

    @Test("A vertical pane's frame bounds it by height")
    func verticalBounds() {
        let harness = InputChainHarness(width: 6, height: 9)
        let view = {
            VSplitView {
                Text("a").frame(minHeight: 2, maxHeight: .fixed(3), alignment: .topLeading)
                Text("b").frame(maxHeight: .infinity, alignment: .topLeading)
            }
        }
        harness.play([KeyEvent(key: .down, shift: true)]) { view() }
        #expect(harness.frame(view()).lines.map(\.stripped).firstIndex { $0.hasPrefix("─") } == 3)
        harness.play([KeyEvent(key: .up, shift: true)]) { view() }
        #expect(harness.frame(view()).lines.map(\.stripped).firstIndex { $0.hasPrefix("─") } == 2)
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
