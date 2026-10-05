//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollTargetBehaviorTests.swift
//
//  SwiftUI's scroll target behaviours (decisions A6): every user step — a
//  wheel tick, a key, a scrollbar arrow — is a gesture of its own, whose target
//  the behaviour moves. `.paging` on ScrollView, List and Table; `.viewAligned`
//  on a ScrollView's marked stack and on List and Table; custom behaviours on
//  a ScrollView.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("Scroll target behaviours")
struct ScrollTargetBehaviorTests {

    /// Renders frames of one view, and drives its wheel and keys.
    @MainActor
    private final class Frames {
        let tui = TUIContext()
        let focusManager = FocusManager()
        var last = FrameBuffer()
        let width: Int
        var height: Int

        init(width: Int = 30, height: Int = 10) {
            self.width = width
            self.height = height
        }

        @discardableResult
        func render<V: View>(_ view: V) -> FrameBuffer {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.verticalScrollIndicatorVisibility = .hidden
            environment.horizontalScrollIndicatorVisibility = .hidden
            environment.applyRuntimeServices(from: tui)
            let context = RenderContext(
                availableWidth: width, availableHeight: height, environment: environment, tuiContext: tui)
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            last = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tui.stateStorage.endRenderPass()
            tui.renderCache.removeInactive()
            tui.mouseEventDispatcher.setRegions(last.hitTestRegions)
            return last
        }

        /// One wheel tick over the middle of the view.
        func wheel(_ button: MouseButton) {
            tui.mouseEventDispatcher.setActiveSupport(.standard)
            _ = tui.mouseEventDispatcher.dispatch(
                MouseEvent(button: button, phase: .scrolled, x: width / 2, y: height / 2))
        }

        var scrollView: ScrollViewHandler? {
            focusManager.activeSection?.focusables.compactMap { $0 as? ScrollViewHandler }.first
        }

        /// The first row number drawn on the frame's first line that has one.
        var topRow: Int? {
            for line in last.lines {
                let text = line.stripped
                if let marker = text.range(of: "row ") {
                    return Int(text[marker.upperBound...].prefix { $0.isNumber })
                }
            }
            return nil
        }
    }

    /// A lazy stack of `count` rows, each `height` lines tall with its number
    /// on its first line.
    private func rows(_ count: Int, height: @escaping (Int) -> Int = { _ in 1 }, lazy: Bool = true) -> AnyView {
        let rows = ForEach(0..<count, id: \.self) { index in
            Text("row \(index)").frame(height: height(index), alignment: .top)
        }
        return lazy
            ? AnyView(LazyVStack(alignment: .leading, spacing: 0) { rows }.scrollTargetLayout())
            : AnyView(VStack(alignment: .leading, spacing: 0) { rows }.scrollTargetLayout())
    }

    // MARK: - Paging on a ScrollView

    @Test("Paging: every wheel tick and key step moves a page, and the last page ends at the end")
    func pagingSteps() {
        let frames = Frames()
        let view = ScrollView { rows(95) }.scrollTargetBehavior(.paging)
        frames.render(view)
        frames.wheel(.scrollDown)
        frames.render(view)
        #expect(frames.scrollView?.scrollOffset == 10, "a 3-line tick is a page")
        #expect(frames.topRow == 10)
        frames.wheel(.scrollDown)
        frames.render(view)
        #expect(frames.scrollView?.scrollOffset == 20)
        frames.wheel(.scrollUp)
        frames.render(view)
        #expect(frames.scrollView?.scrollOffset == 10)
        _ = frames.scrollView?.handleKeyEvent(KeyEvent(key: .down))
        frames.render(view)
        #expect(frames.scrollView?.scrollOffset == 20, "an arrow is a page")
        _ = frames.scrollView?.handleKeyEvent(KeyEvent(key: .pageDown))
        frames.render(view)
        #expect(frames.scrollView?.scrollOffset == 30)
        _ = frames.scrollView?.handleKeyEvent(KeyEvent(key: .end))
        frames.render(view)
        #expect(frames.scrollView?.scrollOffset == 85, "End is the content's end")
        frames.wheel(.scrollUp)
        frames.render(view)
        #expect(frames.scrollView?.scrollOffset == 80, "back to the boundary before it")
        frames.wheel(.scrollDown)
        frames.render(view)
        #expect(frames.scrollView?.scrollOffset == 85, "and the last page ends at the end")
    }

    @Test("A paging view resized between pages is put back on one, as SwiftUI consults on a size change")
    func pagingResettlesOnResize() {
        let frames = Frames()
        let view = ScrollView { rows(95) }.scrollTargetBehavior(.paging)
        frames.render(view)
        frames.wheel(.scrollDown)
        frames.render(view)
        frames.wheel(.scrollDown)
        frames.render(view)
        #expect(frames.scrollView?.scrollOffset == 20)
        frames.height = 8
        frames.render(view)
        let offset = frames.scrollView?.scrollOffset ?? -1
        #expect(offset.isMultiple(of: 8) && abs(offset - 20) <= 4, "a page of eight near 20: \(offset)")
        // At an edge it stays: the end is where every behaviour rests.
        _ = frames.scrollView?.handleKeyEvent(KeyEvent(key: .end))
        frames.render(view)
        frames.height = 9
        frames.render(view)
        #expect(frames.scrollView?.scrollOffset == frames.scrollView?.maxOffset, "still at the end")
    }

    /// The rows readable on the last frame: every line but an "N more" one.
    private func readableRows(_ frames: Frames) -> [Int] {
        frames.last.lines.compactMap { line -> Int? in
            let text = line.stripped
            guard !text.contains("more"), let marker = text.range(of: "row ") else { return nil }
            return Int(text[marker.upperBound...].prefix { $0.isNumber })
        }
    }

    @Test("Paging under the \"N more\" lines: a page is the lines between them, so every line is read")
    func pagingUnderTextIndicators() {
        let frames = Frames()
        let view = ScrollView { rows(30) }
            .frame(height: 10)
            .scrollIndicators(.automatic)
            .scrollIndicatorStyle(.text)
            .scrollTargetBehavior(.paging)
        frames.render(view)
        var read = Set(readableRows(frames))
        var stops = [frames.scrollView?.scrollOffset ?? -1]
        for _ in 0..<4 {
            frames.wheel(.scrollDown)
            frames.render(view)
            read.formUnion(readableRows(frames))
            stops.append(frames.scrollView?.scrollOffset ?? -1)
        }
        // Eight readable lines a page: the band starts a line below the offset.
        #expect(stops == [0, 7, 15, 20, 20], "\(stops)")
        #expect(read == Set(0..<30), "never readable: \(Set(0..<30).subtracting(read).sorted())")
    }

    @Test("View-aligned under the \"N more\" lines: the row a tick lands on is read whole, below \"▲\"")
    func viewAlignedUnderTextIndicators() {
        let frames = Frames()
        let view = ScrollView { rows(30, height: { _ in 2 }) }
            .frame(height: 10)
            .scrollIndicators(.automatic)
            .scrollIndicatorStyle(.text)
            .scrollTargetBehavior(.viewAligned)
        frames.render(view)
        frames.wheel(.scrollDown)
        frames.render(view)
        let lines = frames.last.lines.map(\.stripped)
        #expect(lines.first?.contains("more") == true, "\(lines)")
        // Rows are two lines with the number on the first: the row landed on
        // starts on the first line the indicator leaves.
        #expect(lines.dropFirst().first?.contains("row 2") == true, "\(lines)")
        #expect(frames.scrollView?.scrollOffset == 3)
    }

    @Test("Without a behaviour a wheel tick moves three lines")
    func freeControl() {
        let frames = Frames()
        let view = ScrollView { rows(95) }
        frames.render(view)
        frames.wheel(.scrollDown)
        frames.render(view)
        #expect(frames.scrollView?.scrollOffset == 3)
    }

    @Test("Paging a horizontal scroll view: a tick is a page of columns")
    func horizontalPaging() {
        let frames = Frames(width: 10, height: 3)
        let view = ScrollView(.horizontal) {
            Text(String(repeating: "abcdefghij", count: 5))
        }
        .scrollTargetBehavior(.paging)
        frames.render(view)
        frames.wheel(.scrollRight)
        frames.render(view)
        #expect(frames.scrollView?.horizontal.scrollOffset == 10)
        _ = frames.scrollView?.handleKeyEvent(KeyEvent(key: .right))
        frames.render(view)
        #expect(frames.scrollView?.horizontal.scrollOffset == 20, "an arrow is a page across too")
    }

    @Test("A released scrollbar thumb settles on the nearest page")
    func thumbReleaseSettles() {
        let handler = ScrollViewHandler(focusID: "t")
        // 95 lines, so a thumb cell is not a whole number of pages.
        handler.contentHeight = 95
        handler.viewportHeight = 10
        handler.scrollTargeting = ScrollViewTargeting(
            behavior: PagingScrollTargetBehavior(), axes: .vertical, environment: EnvironmentValues(),
            containerWidth: 10, contentWidth: 10)
        let bar = ScrollbarRenderer.verticalMouseHandler(
            for: handler, length: 10, arrows: .none, proportional: true, behavior: .page)
        _ = bar(MouseEvent(button: .left, phase: .pressed, x: 0, y: 0))  // the thumb, at the top
        _ = bar(MouseEvent(button: .left, phase: .dragged, x: 0, y: 1))
        let dragged = handler.scrollOffset
        #expect(!dragged.isMultiple(of: 10), "the drag itself is free: \(dragged)")
        _ = bar(MouseEvent(button: .left, phase: .released, x: 0, y: 1))
        #expect(handler.scrollOffset == Int((Double(dragged) / 10).rounded()) * 10, "from \(dragged)")
    }

    // MARK: - A behaviour of the app's own

    /// What a behaviour of the app's own was asked.
    nonisolated private final class Asked {
        var originals: [Int] = []
        var proposals: [Int] = []
        var velocities: [CellVector] = []
        var containers: [CellSize] = []
        var contents: [CellSize] = []
        var axes: [Axis.Set] = []
        var scrollEnabled: [Bool] = []
    }

    private struct EveryFifth: ScrollTargetBehavior {
        let asked: Asked

        /// Records what it was asked, and rounds each step up to a multiple of 5.
        func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
            asked.originals.append(context.originalTarget.rect.y)
            asked.proposals.append(target.rect.y)
            asked.velocities.append(context.velocity)
            asked.containers.append(context.containerSize)
            asked.contents.append(context.contentSize)
            asked.axes.append(context.axes)
            asked.scrollEnabled.append(context.isScrollEnabled)
            target.rect.y = (target.rect.y + 4) / 5 * 5
        }
    }

    @Test("A custom behaviour moves each step's target, and is told the gesture")
    func customBehaviour() {
        let frames = Frames()
        let asked = Asked()
        let view = ScrollView { rows(95) }.scrollTargetBehavior(EveryFifth(asked: asked))
        frames.render(view)
        frames.wheel(.scrollDown)
        frames.render(view)
        #expect(frames.scrollView?.scrollOffset == 5)
        frames.wheel(.scrollDown)
        frames.render(view)
        #expect(frames.scrollView?.scrollOffset == 10)
        #expect(asked.originals == [0, 5])
        #expect(asked.proposals == [3, 8])
        #expect(asked.velocities == [CellVector(dx: 0, dy: 3), CellVector(dx: 0, dy: 3)])
        #expect(asked.containers.first == CellSize(width: 30, height: 10))
        #expect(asked.contents.first == CellSize(width: 30, height: 95))
        #expect(asked.axes.first == .vertical)
        #expect(asked.scrollEnabled.first == true, "the environment, by dynamic member")
    }

    /// A behaviour that keeps the view where it is.
    private struct Stay: ScrollTargetBehavior, Equatable {
        func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
            target = context.originalTarget
        }
    }

    @Test("A behaviour that holds the view short of an edge engages no edge anchor")
    func heldStepEngagesNothing() {
        let frames = Frames()
        let anchor = Box<ScrollAnchor<Int>?>(nil)
        let binding = Binding(get: { anchor.value }, set: { anchor.value = $0 })
        let view = ScrollView { rows(95) }
            .scrollTargetBehavior(Stay())
            .anchorPosition(binding)
        frames.render(view)
        frames.wheel(.scrollDown)
        frames.render(view)
        #expect(frames.scrollView?.scrollOffset == 0)
        #expect(anchor.value == nil, "nothing was pushed past the bottom: \(String(describing: anchor.value))")
    }

    nonisolated private final class Box<T> {
        var value: T
        init(_ value: T) { self.value = value }
    }

    // MARK: - View-aligned on a ScrollView

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
        let view = ScrollView { rows(count, height: { $0.isMultiple(of: 2) ? 2 : 5 }, lazy: lazy) }
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
        let view = ScrollView { rows(50) }.scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
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

    // MARK: - List and Table

    private func listHandler(_ frames: Frames) -> ItemListHandler<Int>? {
        frames.focusManager.activeSection?.focusables.compactMap { $0 as? ItemListHandler<Int> }.first
    }

    @Test("A List pages under .paging, scrolls whole rows under .viewAligned, and ignores its own behaviours")
    func listBehaviours() {
        func offsetAfterTick(_ configure: (AnyView) -> AnyView) -> (Int, Int) {
            let frames = Frames(height: 12)
            let list = AnyView(
                List(0..<60, id: \.self) { Text("row \($0)").frame(height: $0.isMultiple(of: 3) ? 2 : 1) })
            let view = configure(list)
            frames.render(view)
            frames.wheel(.scrollDown)
            frames.render(view)
            let handler = listHandler(frames)
            return (handler?.scrollOffset ?? -1, handler?.scrollTopClipLines ?? -1)
        }
        let free = offsetAfterTick { $0 }
        let paged = offsetAfterTick { AnyView($0.scrollTargetBehavior(.paging)) }
        let aligned = offsetAfterTick { AnyView($0.scrollTargetBehavior(.viewAligned)) }
        let byOne = offsetAfterTick {
            AnyView($0.scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne)))
        }
        let custom = offsetAfterTick { AnyView($0.scrollTargetBehavior(EveryFifth(asked: Asked()))) }
        let reset = offsetAfterTick {
            AnyView($0.scrollGranularity(.line).scrollTargetBehavior(.viewAligned))
        }
        // Free: three lines — rows 0 (2 lines) and 1, so the top is row 2.
        #expect(free == (2, 0), "\(free)")
        // A page of the ten lines inside the border: rows 0…6 (2+1+1+2+1+1+2).
        #expect(paged == (7, 0), "a page: \(paged)")
        #expect(aligned == (3, 0), "three whole rows: \(aligned)")
        #expect(byOne == (1, 0), "one row: \(byOne)")
        #expect(custom == free, "a list consults no behaviour of the app's own: \(custom)")
        #expect(reset == free, "`.scrollGranularity(.line)` nearer the list wins: \(reset)")
    }

    @Test("A Table scrolls whole rows under .viewAligned")
    func tableViewAligned() {
        struct Item: Identifiable {
            let id: Int
            var name: String { "row \(id)" }
        }
        func offsetAfterTick(aligned: Bool) -> Int {
            let frames = Frames(height: 12)
            let table = Table((0..<60).map(Item.init)) { TableColumn("Name", value: \Item.name) }
            let view =
                aligned
                ? AnyView(table.scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne)))
                : AnyView(table)
            frames.render(view)
            frames.wheel(.scrollDown)
            frames.render(view)
            return frames.focusManager.activeSection?.focusables
                .compactMap { $0 as? ItemListHandler<Int> }.first?.scrollOffset ?? -1
        }
        #expect(offsetAfterTick(aligned: false) == 3)
        #expect(offsetAfterTick(aligned: true) == 1)
    }
}
