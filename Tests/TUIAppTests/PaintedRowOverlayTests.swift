//  🖥️ TUI — A Terminal UI framework for Swift
//  PaintedRowOverlayTests.swift
//
//  A painted overlay as wide as the canvas, from its first column, covers its
//  rows whole, and the in-place composite writes those rows as the overlay
//  without splitting the base around it (SCROLL-FIT P6b: a table's header
//  pinned to a scroll view's top, drawn over a row every frame that scrolls
//  past it). The rows it writes are not the bytes the split writes — the split
//  keeps the base's escapes before its first cell and after its last, and
//  restates the style the row ends in — but they paint the same cells in the
//  same styling, which is what the terminal shows: the copying composite,
//  which always splits, is the oracle.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore

@Suite("A painted overlay as wide as the canvas paints its rows as the split composite does")
struct PaintedRowOverlayTests {
    private static let reset = "\u{1B}[0m"

    /// Rows a table draws under its pinned header: plain, on a background, reversed for the cursor, bold
    /// runs, and a row whose last style is left open.
    private static let base = [
        "\u{1B}[48;5;236m r12   alpha-12   \(reset)",
        "\u{1B}[7m r13   alpha-13   \(reset)",
        " r14   \u{1B}[1malpha\(reset)-14   ",
        "\u{1B}[38;5;45m r15   alpha-15   ",
        "\u{1B}[2m\u{1B}[48;2;10;20;30m r16 \(reset)  alpha-16   \(reset)",
    ]

    private static let header = "\u{1B}[1m│ Name  Alpha     \(reset)"

    @Test("Each row the overlay covers paints the cells the split composite paints", arguments: 0..<base.count)
    func paintsAsTheSplitDoes(_ row: Int) {
        let base = FrameBuffer(lines: Self.base.map { $0.padToVisibleWidth(18) })
        let overlay = FrameBuffer(lines: [Self.header])
        #expect(overlay.width == base.width)
        var inPlace = base
        inPlace.composite(with: overlay, at: (x: 0, y: row), overlayIsPainted: true, terminalForeground: { nil })
        let split = base.composited(with: overlay, at: (x: 0, y: row), overlayIsPainted: true)
        for line in inPlace.lines.indices {
            #expect(
                inPlace.lines[line].ansiCellDiff(replacing: split.lines[line], width: 18, mergingGapsUpTo: 0)
                    == .identical,
                "row \(line): \(inPlace.lines[line].debugDescription) against \(split.lines[line].debugDescription)")
        }
    }
}
