//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollTargetViewAlignedTests.swift
//
//  `.viewAligned` on a ScrollView (decisions A6): a step lands on the rows of
//  a vertical stack, or the columns of a horizontal one, marked with
//  `scrollTargetLayout()` — lazy or eager, under margins, limited or anchored.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("Scroll target behaviours: view-aligned on a ScrollView")
struct ScrollTargetViewAlignedTests {
    private typealias Frames = ScrollTargetFrames

    @Test("View-aligned: a tick over four-line rows lands on the next row, marked stack only",
          arguments: [true, false])
    func viewAlignedRows(marked: Bool) {
        let frames = Frames()
        let stack = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<30, id: \.self) { Text("row \($0)").frame(height: 4, alignment: .top) }
        }
        let view = ScrollView { stack.scrollTargetLayout(isEnabled: marked) }
            .scrollTargetBehavior(.viewAligned)
        frames.render(view)
        frames.wheel(.scrollDown)
        frames.render(view)
        #expect(frames.scrollView?.scrollOffset == (marked ? 4 : 3), "unmarked, nothing to align to")
        frames.wheel(.scrollDown)
        frames.render(view)
        #expect(frames.scrollView?.scrollOffset == (marked ? 8 : 6))
        _ = frames.scrollView?.handleKeyEvent(KeyEvent(key: .pageDown))
        frames.render(view)
        #expect(frames.scrollView?.scrollOffset == (marked ? 16 : 16), "a page reaches row 4")
    }

    /// Every way a stack reports its rows: the full walk (a lazy stack under
    /// 256 rows), the anchored window (over it), and an eager stack's layout.
    @Test(
        "View-aligned settles on rows of varying height, lazy or eager",
        arguments: [(true, 40), (true, 400), (false, 40)])
    func viewAlignedVariableRows(lazy: Bool, count: Int) {
        let frames = Frames()
        // Heights 2, 5, 2, 5, …: row tops 0, 2, 7, 9, 14, 16, 21, …
        let view = ScrollView { scrollTargetRows(count, height: { $0.isMultiple(of: 2) ? 2 : 5 }, lazy: lazy) }
            .scrollTargetBehavior(.viewAligned)
        frames.render(view)
        var offsets: [Int] = []
        for _ in 0..<4 {
            frames.wheel(.scrollDown)
            frames.render(view)
            offsets.append(frames.scrollView?.scrollOffset ?? -1)
        }
        // From 0, 3 lines reach the top at 2; from 2, 5 reaches nothing further
        // than 2 short of 7, so the next row, 7; from 7, 9; from 9, 14 (12 is short).
        #expect(offsets == [2, 7, 9, 14], "\(offsets)")
    }

    /// The rows reach the scroll view moved by what is drawn above the stack
    /// (`ScrollWindowRelay`): its content margins, or a `Section`'s header.
    @Test("View-aligned finds the rows below the content's top margin")
    func viewAlignedUnderAMargin() {
        let frames = Frames()
        let stack = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<30, id: \.self) { Text("row \($0)").frame(height: 4, alignment: .top) }
        }
        let view = ScrollView { stack.scrollTargetLayout() }
            .contentMargins(.top, 2)
            .scrollTargetBehavior(.viewAligned)
        frames.render(view)
        var offsets: [Int] = []
        for _ in 0..<2 {
            frames.wheel(.scrollDown)
            frames.render(view)
            offsets.append(frames.scrollView?.scrollOffset ?? -1)
        }
        // Row tops at 2, 6, 10, …: the first tick reaches row 0's, the next
        // row 1's.
        #expect(offsets == [2, 6], "\(offsets)")
    }

    /// The carousel SwiftUI's documentation shows: a horizontal stack, marked.
    @Test("View-aligned across: a tick lands on the next column, lazy or eager, under a leading margin too",
          arguments: [(true, 0), (false, 0), (true, 1)])
    func viewAlignedColumns(lazy: Bool, margin: Int) {
        let frames = Frames(width: 20, height: 3)
        let items = ForEach(0..<20, id: \.self) { Text("item\($0)").frame(width: 7, alignment: .leading) }
        let stack: AnyView =
            lazy
            ? AnyView(LazyHStack(spacing: 2) { items }.scrollTargetLayout())
            : AnyView(HStack(spacing: 2) { items }.scrollTargetLayout())
        let view = ScrollView(.horizontal) { stack }
            .contentMargins(.leading, margin)
            .scrollTargetBehavior(.viewAligned)
        frames.render(view)
        var offsets: [Int] = []
        for _ in 0..<2 {
            frames.wheel(.scrollRight)
            frames.render(view)
            offsets.append(frames.scrollView?.horizontal.scrollOffset ?? -1)
        }
        // Columns every 9 cells (7 wide, a gap of 2), from the leading margin.
        #expect(offsets == (margin == 0 ? [9, 18] : [1, 10]), "\(offsets)")
    }

    @Test("View-aligned limited to one view: a tick over one-line rows moves one row")
    func viewAlignedByOne() {
        let frames = Frames()
        let view = ScrollView { scrollTargetRows(50) }.scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        frames.render(view)
        frames.wheel(.scrollDown)
        frames.render(view)
        #expect(frames.scrollView?.scrollOffset == 1)
        _ = frames.scrollView?.handleKeyEvent(KeyEvent(key: .pageDown))
        frames.render(view)
        #expect(frames.scrollView?.scrollOffset == 2, "a page too, one view at a time")
    }

    @Test("View-aligned at an anchor: a centred row's centre meets the view's")
    func viewAlignedCentred() {
        let frames = Frames()
        let stack = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<30, id: \.self) { Text("row \($0)").frame(height: 4, alignment: .top) }
        }
        let view = ScrollView { stack.scrollTargetLayout() }.scrollTargetBehavior(.viewAligned(anchor: .center))
        frames.render(view)
        frames.wheel(.scrollDown)
        frames.render(view)
        // Row 1 spans lines 4..<8, centred in ten lines from offset 1 (lines 1..<11).
        #expect(frames.scrollView?.scrollOffset == 1)
    }

    @Test("View-aligned: a gesture with no direction near the end rests on the end")
    func viewAlignedSettlesOnTheEnd() {
        let frames = Frames()
        // Ten-line rows but the last, three: the end, 83, is no row's top.
        let view = ScrollView {
            scrollTargetRows(10, height: { $0 == 9 ? 3 : 10 })
        }
        .scrollTargetBehavior(.viewAligned)
        frames.render(view)
        guard let handler = frames.scrollView else {
            Issue.record("no scroll view")
            return
        }
        for (start, rest) in [(83, 83), (82, 83), (78, 80)] {
            handler.scrollToOffset(start)
            frames.render(view)
            handler.settleUserScroll()
            #expect(handler.scrollOffset == rest, "from \(start)")
        }
    }
}
