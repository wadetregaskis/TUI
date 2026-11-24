//  🖥️ TUI — A Terminal UI framework for Swift
//  ColumnOfSeveralReadBackTests.swift
//
//  The owner's O-14 (c), 2026-11-21: a lazy stack of several views with a
//  loop among them — `LazyVStack { heading; ForEach(rows); footer }` — is
//  drawn in scroll content as a column of those views
//  (`_ImplicitColumnOfSeveral`) whatever the loop's count, the loop a lazy
//  stack of its own. What its scroll view reads back is still each row, as
//  the same stack drawn flat reads it: the ids `.scrollPosition(id:)` is
//  handed, the ids `onScrollTargetVisibilityChange` lists, the rows a
//  `.viewAligned` behaviour settles on under `scrollTargetLayout()`, and the
//  row a request for an id scrolls to. Each is checked against the flat
//  stack (`drawsContainerRowsWhole`, the twin), below the threshold (256) and
//  past it. Before, the column reported its own views — the heading and the
//  loop's stack — so content read back that way kept the flat stack below
//  the threshold and changed identity crossing it (H-71's exceptions).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

@MainActor
@Suite("O-14 (c): a lazy column of several reads back each row, as the flat stack does")
struct ColumnOfSeveralReadBackTests {
    /// The content around the loop.
    enum Shape: String, CaseIterable, Sendable {
        /// A heading, rows of one and two lines, a footer.
        case headed
        /// The same, centred, a line apart.
        case spaced
        /// A heading, the loop, and a second loop of three.
        case twoLoops
        /// A heading and a footer tagged with `.id(_:)`.
        case tagged
    }

    /// Renders frames of one view and drives its scroll view, as the run loop
    /// does: the read-back is a side effect of the render.
    @MainActor private final class Frames {
        let tui = TUIContext()
        let focus = FocusManager()
        var lines: [String] = []

        func render<V: View>(_ view: V) {
            var environment = EnvironmentValues()
            environment.focusManager = focus
            environment.verticalScrollIndicatorVisibility = .hidden
            environment.horizontalScrollIndicatorVisibility = .hidden
            environment.applyRuntimeServices(from: tui)
            let context = RenderContext(
                availableWidth: 30, availableHeight: 8, environment: environment, tuiContext: tui)
            tui.preferences.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            focus.beginRenderPass()
            let buffer = tui.stateStorage.inRenderPass { renderToBuffer(view, context: context) }
            focus.endRenderPass()
            tui.stateStorage.endRenderPass()
            tui.renderCache.removeInactive()
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
            lines = buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
        }

        var scrollView: ScrollViewHandler? {
            focus.activeSection?.focusables.compactMap { $0 as? ScrollViewHandler }.first
        }

        func wheel() {
            tui.mouseEventDispatcher.setActiveSupport(.standard)
            _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .scrollDown, phase: .scrolled, x: 15, y: 4))
        }
    }

    /// What each frame read back.
    @MainActor private final class Readings {
        var position: Int?
        var visible: [[Int]] = []
    }

    @ViewBuilder private static func content(_ shape: Shape, rows: Int) -> some View {
        let loop = ForEach(0..<rows, id: \.self) { index in
            Text(verbatim: index.isMultiple(of: 3) ? "row \(index)\n  more" : "row \(index)")
        }
        switch shape {
        case .headed:
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("heading")
                loop
                Text("footer")
            }
        case .spaced:
            LazyVStack(alignment: .center, spacing: 1) {
                Text("heading")
                loop
                Text("footer")
            }
        case .twoLoops:
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("heading")
                loop
                ForEach(10_000..<10_003, id: \.self) { Text(verbatim: "tail \($0)") }
            }
        case .tagged:
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("heading").id(-1)
                loop
                Text("footer").id(-2)
            }
        }
    }

    /// `shape` in a scroll view that reads its rows back every way, drawn as
    /// the column, or `flat` as before the column (the twin).
    private static func view(
        _ shape: Shape, rows: Int, flat: Bool, marked: Bool, readings: Readings
    ) -> some View {
        ScrollView {
            content(shape, rows: rows).scrollTargetLayout(isEnabled: marked)
        }
        .scrollPosition(id: Binding(get: { readings.position }, set: { readings.position = $0 }))
        .onScrollTargetVisibilityChange(idType: Int.self) { readings.visible.append($0) }
        .scrollTargetBehavior(.viewAligned)
        .environment(\.drawsContainerRowsWhole, flat)
    }

    /// One run: scrolled by the wheel, by lines and by pages, and sent to a
    /// row by id; at each step what the frame showed and read back.
    private static func run(_ shape: Shape, rows: Int, flat: Bool, marked: Bool) -> [String] {
        let readings = Readings()
        let frames = Frames()
        let view = view(shape, rows: rows, flat: flat, marked: marked, readings: readings)
        var log: [String] = []
        func step(_ name: String) {
            frames.render(view)
            frames.render(view)
            log.append(
                "\(name): offset \(frames.scrollView?.scrollOffset ?? -1) top \(frames.lines.first ?? "")"
                    + " position \(readings.position.map(String.init) ?? "nil")"
                    + " visible \(readings.visible.last ?? [])")
        }
        step("first")
        for tick in 1...3 {
            frames.wheel()
            step("wheel \(tick)")
        }
        frames.scrollView?.userScrollFine(by: 1)
        step("a line")
        _ = frames.scrollView?.handleKeyEvent(KeyEvent(key: .pageDown))
        step("a page")
        frames.scrollView?.userScrollFine(by: 23)
        step("lines")
        readings.position = 31
        step("to 31")
        frames.scrollView?.userScrollFine(by: -60)
        step("back to the top")
        return log
    }

    /// The proxy a reader hands its content.
    @MainActor private final class ProxyBox {
        var proxy: ScrollViewProxy?
    }

    /// Under H-71 alone the column was taken whatever the count where nothing
    /// read its rows back, and below the threshold it drew as an eager stack,
    /// which found no row of its loop: `scrollTo` moved nowhere.
    @Test("ScrollViewReader.scrollTo reaches a row of the loop beside a heading", arguments: Shape.allCases, [40, 300])
    func readerReachesALoopRow(_ shape: Shape, _ rows: Int) {
        func top(flat: Bool) -> String {
            let box = ProxyBox()
            let frames = Frames()
            let view = ScrollViewReader { proxy in
                // swiftlint:disable:next redundant_discardable_let
                let _ = box.proxy = proxy
                ScrollView { Self.content(shape, rows: rows) }
            }
            .environment(\.drawsContainerRowsWhole, flat)
            frames.render(view)
            box.proxy?.scrollTo(31, anchor: .top)
            frames.render(view)
            frames.render(view)
            return frames.lines.first ?? ""
        }
        let column = top(flat: false)
        #expect(column.hasPrefix("row 31"), "\(shape) \(rows): \(column)")
        #expect(column == top(flat: true), "\(shape) \(rows)")
    }

    @Test(
        "Scrolled and sent to a row, the column reads back what the flat stack does",
        arguments: Shape.allCases, [40, 300])
    func readsBackAsTheFlatStack(_ shape: Shape, _ rows: Int) {
        for marked in [false, true] {
            let column = Self.run(shape, rows: rows, flat: false, marked: marked)
            let flat = Self.run(shape, rows: rows, flat: true, marked: marked)
            #expect(column.count == flat.count)
            // Past the threshold the loop is a windowed lazy stack, which
            // knows its rows' places in its band only, as any lazy stack of
            // that many does (`ScrollTargetViewAlignedTests`); the flat twin
            // draws every row. So a behaviour settles alike for the steps
            // that land within a band — the wheel, a line, a page — and not
            // for a jump of three screens, after which the two part.
            let steps = rows > 256 && marked ? 6 : column.count
            for (index, (got, want)) in zip(column, flat).enumerated().prefix(steps) where got != want {
                Issue.record("\(shape) \(rows) marked \(marked) step \(index):\n  column \(got)\n  flat   \(want)")
            }
        }
    }
}
