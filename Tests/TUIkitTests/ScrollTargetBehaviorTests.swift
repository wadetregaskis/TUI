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

    private typealias Frames = ScrollTargetFrames

    // MARK: - Paging on a ScrollView

    @Test("Paging: every wheel tick and key step moves a page, and the last page ends at the end")
    func pagingSteps() {
        let frames = Frames()
        let view = ScrollView { scrollTargetRows(95) }.scrollTargetBehavior(.paging)
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
        let view = ScrollView { scrollTargetRows(95) }.scrollTargetBehavior(.paging)
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

    @Test("Paging under the \"N more\" lines: they are kept out of the page, so every line is read")
    func pagingUnderTextIndicators() {
        let frames = Frames()
        let view = ScrollView { scrollTargetRows(30) }
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
        // Eight lines a page, between the two lines the indicators keep at
        // every stop; the last page ends at the end.
        #expect(stops == [0, 8, 16, 22, 22], "\(stops)")
        #expect(read == Set(0..<30), "never readable: \(Set(0..<30).subtracting(read).sorted())")
    }

    /// SwiftUI's paging idiom: pages as tall as the scroll view's container.
    /// Each page marks its first and last line.
    private func containerPages(_ count: Int) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                VStack(spacing: 0) {
                    Text("top \(index)")
                    Spacer(minLength: 0)
                    Text("end \(index)")
                }
                .containerRelativeFrame(.vertical)
            }
        }
    }

    @Test(
        "Container-sized pages under the \"N more\" lines: every stop shows one page whole, between them",
        arguments: [ScrollIndicatorVisibility.visible, .automatic])
    func containerPagesUnderTextIndicators(visibility: ScrollIndicatorVisibility) {
        let frames = Frames()
        let view = ScrollView { containerPages(5) }
            .frame(height: 10)
            .scrollIndicators(visibility)
            .scrollIndicatorStyle(.text)
            .scrollTargetBehavior(.paging)
        frames.render(view)
        for page in 0..<5 {
            let lines = frames.last.lines.map(\.stripped)
            // The window is lines 1 to 8: the "N more" lines are the first and
            // the last, at every stop.
            #expect(lines.first?.contains("more") == true && lines.last?.contains("more") == true, "\(lines)")
            #expect(lines[1].contains("top \(page)") && lines[8].contains("end \(page)"), "page \(page): \(lines)")
            #expect(lines.count { $0.contains("top") || $0.contains("end") } == 2, "one page: \(lines)")
            frames.wheel(.scrollDown)
            frames.render(view)
        }
    }

    @Test("View-aligned under the \"N more\" lines: the row a tick lands on is read whole, below \"▲\"")
    func viewAlignedUnderTextIndicators() {
        let frames = Frames()
        let view = ScrollView { scrollTargetRows(30, height: { _ in 2 }) }
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
        #expect(lines.dropFirst().first?.contains("row 1") == true, "\(lines)")
        #expect(frames.scrollView?.scrollOffset == 2)
    }

    @Test("Without a behaviour a wheel tick moves three lines")
    func freeControl() {
        let frames = Frames()
        let view = ScrollView { scrollTargetRows(95) }
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

    @Test("A horizontal pager keeps no \"N more\" lines: they count rows it does not scroll")
    func horizontalPagerReservesNoLines() {
        let frames = Frames(width: 10, height: 4)
        let view = ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<4, id: \.self) { Text("row\($0) " + String(repeating: "abcdefghij", count: 5)) }
            }
        }
        .scrollIndicators(.automatic)
        .scrollIndicatorStyle(.text)
        .scrollTargetBehavior(.paging)
        frames.render(view)
        let lines = frames.last.lines.map(\.stripped)
        #expect(lines.allSatisfy { !$0.contains("more") }, "\(lines)")
        #expect(lines.first?.hasPrefix("row0") == true, "\(lines)")
    }

    @Test("A horizontal pager resized between pages is put back on one of the new width")
    func horizontalPagingResettlesOnResize() {
        let frames = Frames(width: 20, height: 3)
        let view = ScrollView(.horizontal) { Text(String(repeating: "abcdefghij", count: 20)) }
            .scrollTargetBehavior(.paging)
        frames.render(view)
        frames.wheel(.scrollRight)
        frames.render(view)
        frames.wheel(.scrollRight)
        frames.render(view)
        #expect(frames.scrollView?.horizontal.scrollOffset == 40)
        frames.width = 30
        frames.render(view)
        // The nearest boundary of a thirty-column page, not of the old twenty.
        #expect(frames.scrollView?.horizontal.scrollOffset == 30)
    }

    /// A behaviour that keeps the view's offset down its axis and moves it four
    /// columns across with every step.
    private struct StepAcross: ScrollTargetBehavior, Equatable {
        func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
            target.rect.y = context.originalTarget.rect.y
            target.rect.x = context.originalTarget.rect.x + 4
        }
    }

    private func wide(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { Text("row \($0) " + String(repeating: "-", count: 60)) }
        }
    }

    @Test("A step that moves only the other axis is a scroll: consumed, recorded, never chained")
    func stepMovingAcrossIsAScroll() {
        let frames = Frames(width: 20, height: 10)
        let view = ScrollView([.horizontal, .vertical]) { wide(40) }
            .scrollTargetBehavior(StepAcross())
            .scrollChainingDelay(.zero)
        frames.render(view)
        guard let handler = frames.scrollView else {
            Issue.record("no scroll view")
            return
        }
        handler.userScrolledSinceRender = false
        let consumed = handler.handleWheelEvent(MouseEvent(button: .scrollDown, phase: .scrolled, x: 1, y: 1))
        #expect(handler.horizontal.scrollOffset == 4, "the behaviour moved it across")
        #expect(consumed, "it moved, so the tick is not passed to an enclosing scroller")
        #expect(handler.userScrolledSinceRender, "and the user scrolled it")
    }

    @Test("Left or Right that moves only the vertical axis is consumed")
    func horizontalKeyMovingDownIsConsumed() {
        let frames = Frames(width: 20, height: 10)
        let view = ScrollView([.horizontal, .vertical]) { wide(93) }
            .scrollTargetBehavior(.paging)
        frames.render(view)
        guard let handler = frames.scrollView else {
            Issue.record("no scroll view")
            return
        }
        // Off every page, as a programmatic scroll can leave it.
        handler.scrollToOffset(41)
        frames.render(view)
        handler.userScrolledSinceRender = false
        let consumed = handler.handleKeyEvent(KeyEvent(key: .left))
        // Nothing to the left, but the gesture's target settles on a page down
        // the other axis too.
        #expect(handler.scrollOffset == 40, "\(handler.scrollOffset)")
        #expect(consumed, "the view moved, so the key is spent")
        #expect(handler.userScrolledSinceRender)
    }

    @Test("Left at the tail of a two-axis pager leaves its rows at the end, and it goes on following them")
    func horizontalKeyAtTheTailKeepsTheEnd() {
        let frames = Frames(width: 20, height: 10)
        // 93 rows over 10 lines: the end, 83, is not a multiple of the page.
        func view(_ count: Int) -> some View {
            ScrollView([.horizontal, .vertical]) { wide(count) }
                .scrollTargetBehavior(.paging)
                .defaultScrollAnchor(.bottom)
        }
        frames.render(view(93))
        guard let handler = frames.scrollView else {
            Issue.record("no scroll view")
            return
        }
        #expect(handler.scrollOffset == 83, "opens at the tail")
        let consumed = handler.handleKeyEvent(KeyEvent(key: .left))
        // The end is the last page's boundary, so nothing moves: the rows used
        // to settle to 80, off the tail, and stopped following it.
        #expect(handler.scrollOffset == 83)
        #expect(!consumed, "nothing moved, so the key is the parent's")
        frames.render(view(95))
        #expect(handler.scrollOffset == 85, "new rows are followed")
    }

    /// `count` rows, each wide enough to scroll across: nine ten lines tall,
    /// then one three lines tall, so the end of the first ten (83 over a
    /// 10-line view) is no row's top, and one line each after that.
    private func tallWideRows(_ count: Int) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                Text("row \(index) " + String(repeating: "-", count: 60))
                    .frame(height: index < 9 ? 10 : index == 9 ? 3 : 1, alignment: .top)
            }
        }
        .scrollTargetLayout()
    }

    @Test("A step along the other axis leaves a view-aligned view at its tail, and it goes on following it")
    func crossAxisStepKeepsTheTail() {
        let frames = Frames(width: 20, height: 10)
        func view(_ count: Int) -> some View {
            ScrollView([.horizontal, .vertical]) { tallWideRows(count) }
                .scrollTargetBehavior(.viewAligned)
                .defaultScrollAnchor(.bottom)
        }
        frames.render(view(10))
        guard let handler = frames.scrollView else {
            Issue.record("no scroll view")
            return
        }
        #expect(handler.scrollOffset == 83, "opens at the tail")
        #expect(handler.scrollTargeting?.rows.isEmpty == false, "the rows are there to align to")
        // The nearest row's top is 80, which the rows used to settle to.
        _ = handler.handleKeyEvent(KeyEvent(key: .left))
        #expect(handler.scrollOffset == 83)
        frames.render(view(11))
        #expect(handler.scrollOffset == 84, "still following the tail")
    }

    @Test("A step along the other axis that moves this one is this one's scroll: a bound anchor is released")
    func crossAxisMoveReleasesTheAnchor() {
        final class Box { var anchor: ScrollAnchor<Int>? }
        let box = Box()
        let frames = Frames(width: 20, height: 10)
        let view = ScrollView([.horizontal, .vertical]) { wide(93) }
            .scrollTargetBehavior(.paging)
            .anchorPosition(Binding(get: { box.anchor }, set: { box.anchor = $0 }))
        frames.render(view)
        guard let handler = frames.scrollView else {
            Issue.record("no scroll view")
            return
        }
        // Off every page, holding the row at the top.
        handler.scrollToOffset(41)
        box.anchor = .row(41)
        frames.render(view)
        _ = handler.handleKeyEvent(KeyEvent(key: .left))
        #expect(handler.scrollOffset == 40)
        #expect(box.anchor == .window, "the user moved the rows, so they are no longer held")
        frames.render(view)
        #expect(handler.scrollOffset == 40, "and nothing puts them back")
    }

    @Test("A behaviour that holds the view mid-content keeps the wheel: nothing chains to the parent")
    func heldStepDoesNotChain() {
        let frames = Frames()
        let view = ScrollView { scrollTargetRows(95) }
            .scrollTargetBehavior(Stay())
            .scrollChainingDelay(.zero)
        frames.render(view)
        frames.scrollView?.scrollToOffset(20)
        frames.render(view)
        let consumed = frames.scrollView?.handleWheelEvent(
            MouseEvent(button: .scrollDown, phase: .scrolled, x: 1, y: 1))
        #expect(frames.scrollView?.scrollOffset == 20)
        #expect(consumed == true, "held short of the bottom, the tick is this view's, not its parent's")
    }

    @Test("A vertical-only pager's Left key moves nothing, and is not consumed")
    func horizontalKeyOnVerticalPager() {
        let frames = Frames()
        let view = ScrollView { scrollTargetRows(93) }.scrollTargetBehavior(.paging)
        frames.render(view)
        _ = frames.scrollView?.handleKeyEvent(KeyEvent(key: .end))
        frames.render(view)
        let end = frames.scrollView?.scrollOffset
        let consumed = frames.scrollView?.handleKeyEvent(KeyEvent(key: .left))
        #expect(frames.scrollView?.scrollOffset == end, "a horizontal key does not page a vertical view")
        #expect(consumed == false)
    }

    /// With a margin: the page's content margins reach the menu's scroller
    /// too, and it used to draw them through a copy of itself that forgot it
    /// was the framework's.
    @Test(
        "The framework's own scroller — a tall inline menu's — does not take the page's behaviour",
        arguments: [0, 1])
    func chromeScrollerIgnoresBehaviour(margin: Int) {
        let frames = Frames(width: 30, height: 14)
        let view = VStack {
            Menu("Pick") {
                ForEach(0..<60, id: \.self) { index in Button("item \(index)") {} }
            }
            .menuStyle(.inline)
        }
        .contentMargins(margin)
        .scrollTargetBehavior(.paging)
        frames.render(view)
        #expect(frames.scrollView?.maxOffset ?? 0 > 0, "the menu scrolls inside its box")
        // Over the menu's rows, which sit at the leading edge.
        frames.tui.mouseEventDispatcher.setActiveSupport(.standard)
        _ = frames.tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .scrollDown, phase: .scrolled, x: 4, y: 6))
        frames.render(view)
        #expect(frames.scrollView?.scrollOffset == 3, "three lines a tick, not a page")
    }

    @Test("A released scrollbar thumb settles on the nearest page")
    func thumbReleaseSettles() {
        let handler = ScrollViewHandler(focusID: "t")
        // 95 lines, so a thumb cell is not a whole number of pages.
        handler.contentHeight = 95
        handler.viewportHeight = 10
        handler.scrollTargeting = ScrollViewTargeting(
            behavior: PagingScrollTargetBehavior(), axes: .vertical, environment: EnvironmentValues(),
            width: 10)
        let bar = ScrollbarRenderer.verticalMouseHandler(
            for: handler, length: 10, arrows: .none, proportional: true, behavior: .page)
        _ = bar(MouseEvent(button: .left, phase: .pressed, x: 0, y: 0))  // the thumb, at the top
        _ = bar(MouseEvent(button: .left, phase: .dragged, x: 0, y: 1))
        let dragged = handler.scrollOffset
        #expect(!dragged.isMultiple(of: 10), "the drag itself is free: \(dragged)")
        _ = bar(MouseEvent(button: .left, phase: .released, x: 0, y: 1))
        #expect(handler.scrollOffset == Int((Double(dragged) / 10).rounded()) * 10, "from \(dragged)")
    }

    @Test("A gesture with no direction near the end rests on the end, the last page's boundary")
    func settleNearTheEndRestsOnIt() {
        let handler = ScrollViewHandler(focusID: "t")
        // 93 lines over 10: the end, 83, is not a multiple of the page.
        handler.contentHeight = 93
        handler.viewportHeight = 10
        handler.scrollTargeting = ScrollViewTargeting(
            behavior: PagingScrollTargetBehavior(), axes: .vertical, environment: EnvironmentValues(),
            width: 10)
        for (start, rest) in [(83, 83), (82, 83), (78, 80)] {
            handler.scrollToOffset(start)
            handler.settleUserScroll()
            #expect(handler.scrollOffset == rest, "from \(start)")
        }
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
        let view = ScrollView { scrollTargetRows(95) }.scrollTargetBehavior(EveryFifth(asked: asked))
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
        let view = ScrollView { scrollTargetRows(95) }
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
